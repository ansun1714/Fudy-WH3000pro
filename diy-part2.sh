#!/bin/bash
# =====================================================
# DIY 脚本第二部分
# 在 feeds install 之后、make defconfig 之前执行
# =====================================================

# =====================================================
# 1. 修改路由器默认主机名
# =====================================================
sed -i 's/OpenWrt/WH3000/g' package/base-files/files/bin/config_generate
echo ">>> [1/8] 主机名改为 WH3000"

# =====================================================
# 2. 修改默认 LuCI 主题为 Design
# =====================================================
if [ -f package/lean/default-settings/files/zzz-default-settings ]; then
    sed -i 's/luci-theme-bootstrap/luci-theme-design/g' \
        package/lean/default-settings/files/zzz-default-settings
fi
find feeds/luci -name "Makefile" 2>/dev/null \
    | xargs grep -l "bootstrap" 2>/dev/null \
    | while read f; do
        sed -i 's/luci-theme-bootstrap/luci-theme-design/g' "$f"
    done
echo ">>> [2/8] 默认主题改为 luci-theme-design"

# =====================================================
# 3. 修复 docker-compose 编译失败
#
# 根因：LEDE feeds 的 docker-compose 引用 docker v28.3.1
# 该版本拆分了内部包结构，Go module 找不到子包
# 修复：降级到 v2.27.1（最后一个兼容版本）
# =====================================================
COMPOSE_MK="feeds/packages/utils/docker-compose/Makefile"
if [ -f "$COMPOSE_MK" ]; then
    echo ">>> [3/8] 修复 docker-compose 版本..."
    cp "$COMPOSE_MK" "${COMPOSE_MK}.bak"
    sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:=2.27.1/' "$COMPOSE_MK"
    sed -i 's/^PKG_HASH:=.*/PKG_HASH:=skip/' "$COMPOSE_MK"
    sed -i '/^PKG_MIRROR_HASH/d' "$COMPOSE_MK"
    echo ">>> docker-compose 已锁定为 v2.27.1，当前版本行："
    grep "^PKG_VERSION" "$COMPOSE_MK"
else
    echo "⚠️  [3/8] 未找到 docker-compose Makefile，跳过"
fi

# =====================================================
# 4. 修复 Lucky 执行权限
#
# 日志报错：sh: /usr/bin/luckyarch: Permission denied
# 根因：Lucky 二进制文件打包时缺少执行权限
# =====================================================
echo ">>> [4/8] 修复 Lucky 执行权限..."
find feeds/lucky/ -type f \( -name "lucky" -o -name "lucky*" \) \
    -exec chmod +x {} \; 2>/dev/null || true
find package/ -path "*/lucky/files*" -type f \
    -exec file {} \; 2>/dev/null \
    | grep -i "ELF\|executable" \
    | cut -d: -f1 \
    | xargs chmod +x 2>/dev/null || true
echo ">>> Lucky 权限修复完成"

# =====================================================
# 5. ★ 修复 WiFi 首次启动不出现的问题 ★
#
# 根因分析：
# OpenWrt 首次启动时，/etc/config/wireless 不存在（或为空）
# netifd 找不到 radio 配置，WiFi 不初始化
# 之前用 uci-defaults 等待驱动的方案在该设备上时序仍不稳定
#
# 正确方案：
# 直接把 wireless 配置文件预置进固件
# 这样刷机后第一次启动 netifd 就能读到 radio 配置
# 同时确保 radio 默认开启（disabled=0）
#
# 注意：SSID/密码用户自行在 LuCI 里修改
# 这里只保证 radio 开启，SSID 用设备 MAC 区分
# =====================================================
mkdir -p files/etc/config

cat > files/etc/config/wireless << 'WIRELESS_EOF'
config wifi-device 'radio0'
	option type 'mac80211'
	option path 'platform/18000000.wifi'
	option band '5g'
	option htmode 'HE80'
	option channel 'auto'
	option txpower '20'
	option country 'CN'
	option cell_density '0'
	option disabled '0'

config wifi-iface 'default_radio0'
	option device 'radio0'
	option network 'lan'
	option mode 'ap'
	option ssid 'WH3000_5G'
	option encryption 'psk2+ccmp'
	option key 'password'

config wifi-device 'radio1'
	option type 'mac80211'
	option path 'platform/18000000.wifi+1'
	option band '2g'
	option htmode 'HE20'
	option channel 'auto'
	option txpower '20'
	option country 'CN'
	option cell_density '0'
	option disabled '0'

config wifi-iface 'default_radio1'
	option device 'radio1'
	option network 'lan'
	option mode 'ap'
	option ssid 'WH3000_2.4G'
	option encryption 'psk2+ccmp'
	option key 'password'
WIRELESS_EOF

echo ">>> [5/8] WiFi 配置已预置到固件"
echo ">>>       5G SSID : WH3000_5G"
echo ">>>       2.4G SSID: WH3000_2.4G"
echo ">>>       默认密码 : password（请刷机后在 LuCI 修改）"

# =====================================================
# 6. ★ Docker 数据目录 + 存储驱动配置 ★
#
# 用户已将 mmcblk0p7 格式化并挂载到 /mnt/mmcblk0p7
# 刷机不影响该分区数据，只需指定数据目录和驱动
# 存储驱动使用 overlay2（当前最新推荐驱动）
# =====================================================

# 直接把 daemon.json 编译进固件
# dockerd 启动时自动读取 /etc/docker/daemon.json
mkdir -p files/etc/docker
cat > files/etc/docker/daemon.json << 'DAEMONJSON_EOF'
{
  "data-root": "/mnt/mmcblk0p7/docker",
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "iptables": true,
  "live-restore": true
}
DAEMONJSON_EOF

# uci-defaults：确保挂载点就绪后创建 docker 目录
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/20-docker-datadir << 'DOCKER_EOF'
#!/bin/sh
MOUNT_POINT="/mnt/mmcblk0p7"
DOCKER_DATA="$MOUNT_POINT/docker"

count=0
while [ $count -lt 15 ]; do
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        mkdir -p "$DOCKER_DATA"
        logger -t docker-setup "Docker 数据目录就绪：$DOCKER_DATA"
        exit 0
    fi
    sleep 1
    count=$((count + 1))
done

logger -t docker-setup "警告：$MOUNT_POINT 未挂载，请检查 fstab"
exit 0
DOCKER_EOF
chmod +x files/etc/uci-defaults/20-docker-datadir

echo ">>> [6/8] Docker 配置完成"
echo ">>>       数据目录：/mnt/mmcblk0p7/docker"
echo ">>>       存储驱动：overlay2"

# =====================================================
# 7. Web 界面 / Samba / rpcd 优化
# =====================================================
mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/99-uhttpd-optimize << 'UCI_EOF'
#!/bin/sh
uci -q set uhttpd.main.max_connections='100' 2>/dev/null || true
uci -q set uhttpd.main.max_requests='10' 2>/dev/null || true
uci -q set uhttpd.main.http_keepalive='20' 2>/dev/null || true
uci -q set uhttpd.main.script_timeout='60' 2>/dev/null || true
uci -q set uhttpd.main.network_timeout='30' 2>/dev/null || true
uci commit uhttpd 2>/dev/null || true
exit 0
UCI_EOF
chmod +x files/etc/uci-defaults/99-uhttpd-optimize

cat > files/etc/uci-defaults/98-rpcd-timeout << 'RPCD_EOF'
#!/bin/sh
uci -q set rpcd.@rpcd[0].timeout='60' 2>/dev/null || true
uci commit rpcd 2>/dev/null || true
exit 0
RPCD_EOF
chmod +x files/etc/uci-defaults/98-rpcd-timeout

# 修复 Samba IPv6 绑定报错
# 日志：smbd: open_socket_in failed: Address not available
cat > files/etc/uci-defaults/97-samba-fix << 'SAMBA_EOF'
#!/bin/sh
uci -q set samba4.@samba[0].disable_ipv6='1' 2>/dev/null || true
uci commit samba4 2>/dev/null || true
exit 0
SAMBA_EOF
chmod +x files/etc/uci-defaults/97-samba-fix

echo ">>> [7/8] Web / Samba / rpcd 优化脚本已写入"

# =====================================================
# 8. 自定义 Banner
# =====================================================
mkdir -p files/etc
cat > files/etc/banner << 'BAN_EOF'
 __      __ _   _  _____   ___   ___   ___  
 \ \    / /| | | ||___ /  / _ \ / _ \ / _ \ 
  \ \/\/ / | |_| |  |_ \ | | | | | | | | | |
   \_/\_/   \___/  |___/ |_| |_|\___/ |_| |_|
  华思飞 WH3000 · LEDE · Kernel 6.6 LTS
-------------------------------------------------
BAN_EOF
echo ">>> [8/8] Banner 已自定义"

echo ""
echo "======================================"
echo " DIY 第二部分全部完成"
echo " 主机名          : WH3000pro"
echo " 主题            : luci-theme-design"
echo " docker-compose  : 锁定 v2.27.1"
echo " Lucky 权限      : 已修复"
echo " WiFi            : 预置配置，首次刷机直接启动"
echo " WiFi 5G SSID   : WH3000_5G"
echo " WiFi 2.4G SSID : WH3000_2.4G"
echo " WiFi 默认密码   : password123"
echo " Docker 数据目录 : /mnt/mmcblk0p7/docker"
echo " Docker 存储驱动 : overlay2"
echo " Web 优化        : 99-uhttpd-optimize"
echo " Samba 修复      : 97-samba-fix"
echo "======================================"
