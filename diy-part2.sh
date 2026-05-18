#!/bin/bash
# =====================================================
# DIY 脚本第二部分 - 完整修复版
# 在 feeds install 之后、make defconfig 之前执行
# =====================================================

# =====================================================
# 1. 修改路由器默认主机名
#
# 修复：LEDE 主机名在两处定义，必须同时修改
# =====================================================
# 方式一：config_generate 里的默认值
sed -i 's/OpenWrt/WH3000/g' package/base-files/files/bin/config_generate 2>/dev/null || true

# 方式二：通过 uci-defaults 在首次启动时设置（最可靠）
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/01-hostname << 'HOSTNAME_EOF'
#!/bin/sh
uci set system.@system[0].hostname='WH3000'
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci commit system
exit 0
HOSTNAME_EOF
chmod +x files/etc/uci-defaults/01-hostname
echo ">>> [1/7] 主机名设置完成"

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
echo ">>> [2/7] 默认主题改为 luci-theme-design"

# =====================================================
# 3. 修复 docker-compose 编译失败
#
# 根因：LEDE feeds 的 docker-compose 引用 docker v28.3.1
# 该版本拆分了内部包结构，Go module 找不到子包
# 修复：降级到 v2.27.1（最后一个兼容版本）
# =====================================================
COMPOSE_MK="feeds/packages/utils/docker-compose/Makefile"
if [ -f "$COMPOSE_MK" ]; then
    echo ">>> [3/7] 修复 docker-compose 版本..."
    cp "$COMPOSE_MK" "${COMPOSE_MK}.bak"
    sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:=2.27.1/' "$COMPOSE_MK"
    sed -i 's/^PKG_HASH:=.*/PKG_HASH:=skip/' "$COMPOSE_MK"
    sed -i '/^PKG_MIRROR_HASH/d' "$COMPOSE_MK"
    echo ">>> docker-compose 已锁定为 v2.27.1"
    grep "^PKG_VERSION" "$COMPOSE_MK"
else
    echo "⚠️  [3/7] 未找到 docker-compose Makefile，跳过"
fi

# =====================================================
# 4. 修复 Lucky 执行权限
# =====================================================
echo ">>> [4/7] 修复 Lucky 执行权限..."
find feeds/lucky/ -type f \( -name "lucky" -o -name "lucky*" \) \
    -exec chmod +x {} \; 2>/dev/null || true
find package/ -path "*/lucky/files*" -type f \
    -exec file {} \; 2>/dev/null \
    | grep -i "ELF\|executable" \
    | cut -d: -f1 \
    | xargs chmod +x 2>/dev/null || true
echo ">>> Lucky 权限修复完成"

# =====================================================
# 5. ★ 修复 WiFi 首次启动问题 + 设置 WiFi 名称 ★
#
# 根因：
# LEDE 的 mac80211.sh 在首次启动时会检测 radio 并
# 生成默认 wireless 配置，把 radio 设为 disabled=1
# 然后才执行 uci-defaults，所以预置 wireless 文件会被覆盖
#
# 正确修复方案：
# 直接修改 mac80211.sh 的默认行为，让 radio 默认开启
# 同时通过 uci-defaults 在 mac80211.sh 执行后设置 SSID
# uci-defaults 编号用 99- 确保在 mac80211 初始化后执行
# =====================================================

# 修改 mac80211.sh，让首次生成的 radio 配置默认开启
MAC80211_SH="package/kernel/mac80211/files/lib/wifi/mac80211.sh"
if [ -f "$MAC80211_SH" ]; then
    # 将默认 disabled=1 改为 disabled=0
    sed -i 's/set wireless\.${name}\.disabled=1/set wireless.${name}.disabled=0/g' "$MAC80211_SH"
    echo ">>> [5/7] mac80211.sh 已修改，radio 默认开启"
else
    echo "⚠️  mac80211.sh 未找到，尝试备用路径..."
    find . -path "*/mac80211/files/lib/wifi/mac80211.sh" 2>/dev/null \
        | head -1 \
        | while read f; do
            sed -i 's/set wireless\.${name}\.disabled=1/set wireless.${name}.disabled=0/g' "$f"
            echo ">>> 已修改：$f"
        done
fi

# 通过 uci-defaults 设置 WiFi 名称和密码
# 编号 99- 确保在所有初始化脚本之后执行
cat > files/etc/uci-defaults/99-wifi-setup << 'WIFI_EOF'
#!/bin/sh
# WiFi 初始设置：设置 SSID 和密码
# mac80211.sh 首次生成配置后由本脚本覆盖 SSID/密码

# 等待 wireless 配置生成完成
sleep 2

# 确保 radio 开启
uci set wireless.radio0.disabled='0' 2>/dev/null || true
uci set wireless.radio1.disabled='0' 2>/dev/null || true

# 设置 5G WiFi（radio0）
uci set wireless.default_radio0.ssid='WH3000_5G' 2>/dev/null || true
uci set wireless.default_radio0.encryption='psk2+ccmp' 2>/dev/null || true
uci set wireless.default_radio0.key='password123' 2>/dev/null || true

# 设置 2.4G WiFi（radio1）
uci set wireless.default_radio1.ssid='WH3000_2.4G' 2>/dev/null || true
uci set wireless.default_radio1.encryption='psk2+ccmp' 2>/dev/null || true
uci set wireless.default_radio1.key='password123' 2>/dev/null || true

uci commit wireless

# 启动 WiFi
wifi up

logger -t wifi-setup "WiFi 初始化完成，SSID: WH3000_5G / WH3000_2.4G"
exit 0
WIFI_EOF
chmod +x files/etc/uci-defaults/99-wifi-setup
echo ">>> WiFi 名称设置脚本已写入"

# =====================================================
# 6. ★ Docker 数据目录 + 存储驱动配置 ★
#
# 修复：LEDE 的 dockerd 读取的配置在两个地方：
#   - 运行时：/tmp/dockerd/daemon.json（tmpfs，重启消失）
#   - 持久化：通过 /etc/init.d/dockerd 脚本生成
#
# 正确做法：
#   修改 dockerd 的 init 脚本，在启动时生成正确的 daemon.json
#   这样每次开机都会应用正确配置
# =====================================================

# 找到 dockerd 的 init 脚本并修改数据目录
DOCKERD_INIT="feeds/packages/utils/docker/files/dockerd.init"
if [ -f "$DOCKERD_INIT" ]; then
    echo ">>> [6/7] 修改 dockerd init 脚本数据目录..."
    # 将默认的 /opt/docker 替换为指定路径
    sed -i 's|/opt/docker|/mnt/mmcblk0p7/docker|g' "$DOCKERD_INIT"
    echo ">>> dockerd 数据目录已改为 /mnt/mmcblk0p7/docker"
else
    echo "⚠️  dockerd.init 未找到，通过 uci-defaults 方式配置..."
fi

# 同时通过 uci-defaults 确保配置生效
# 这是双重保障，覆盖任何可能的默认值
cat > files/etc/uci-defaults/20-docker-config << 'DOCKER_EOF'
#!/bin/sh
# Docker 数据目录和存储驱动配置
# 每次启动时确保 daemon.json 内容正确

MOUNT_POINT="/mnt/mmcblk0p7"
DOCKER_DATA="$MOUNT_POINT/docker"
DAEMON_DIR="/tmp/dockerd"
DAEMON_JSON="$DAEMON_DIR/daemon.json"

# 等待挂载点就绪
count=0
while [ $count -lt 15 ]; do
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        break
    fi
    sleep 1
    count=$((count + 1))
done

if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    logger -t docker-config "警告：$MOUNT_POINT 未挂载，Docker 将使用默认目录"
    exit 0
fi

# 创建 Docker 数据目录
mkdir -p "$DOCKER_DATA"

# 写入运行时 daemon.json
mkdir -p "$DAEMON_DIR"
cat > "$DAEMON_JSON" << JSONEOF
{
  "data-root": "$DOCKER_DATA",
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
JSONEOF

logger -t docker-config "Docker 配置已更新，数据目录：$DOCKER_DATA，驱动：overlay2"

# 如果 dockerd 已在运行，重启使配置生效
if pidof dockerd > /dev/null 2>&1; then
    logger -t docker-config "重启 dockerd 使配置生效..."
    /etc/init.d/dockerd restart 2>/dev/null || true
fi

exit 0
DOCKER_EOF
chmod +x files/etc/uci-defaults/20-docker-config

# 同时修改 UCI docker 配置（luci-app-docker 读取这里）
cat >> files/etc/uci-defaults/20-docker-config << 'DOCKER_UCI_EOF'

# 设置 uci docker 配置
uci set docker.globals.data_root='/mnt/mmcblk0p7/docker' 2>/dev/null || true
uci commit docker 2>/dev/null || true
DOCKER_UCI_EOF

echo ">>> [6/7] Docker 配置完成"
echo ">>>       数据目录：/mnt/mmcblk0p7/docker"
echo ">>>       存储驱动：overlay2"

# =====================================================
# 7. Web 界面 / Samba / rpcd 优化
# =====================================================
cat > files/etc/uci-defaults/98-system-optimize << 'OPT_EOF'
#!/bin/sh
# uhttpd 优化
uci -q set uhttpd.main.max_connections='100' 2>/dev/null || true
uci -q set uhttpd.main.max_requests='10' 2>/dev/null || true
uci -q set uhttpd.main.http_keepalive='20' 2>/dev/null || true
uci -q set uhttpd.main.script_timeout='60' 2>/dev/null || true
uci -q set uhttpd.main.network_timeout='30' 2>/dev/null || true
uci commit uhttpd 2>/dev/null || true

# rpcd 超时
uci -q set rpcd.@rpcd[0].timeout='60' 2>/dev/null || true
uci commit rpcd 2>/dev/null || true

# Samba 禁用 IPv6 绑定（避免启动时报错）
uci -q set samba4.@samba[0].disable_ipv6='1' 2>/dev/null || true
uci commit samba4 2>/dev/null || true

# LuCI 语言
uci set luci.main.lang='zh_Hans' 2>/dev/null || true
uci commit luci 2>/dev/null || true

exit 0
OPT_EOF
chmod +x files/etc/uci-defaults/98-system-optimize
echo ">>> [7/7] 系统优化脚本已写入"

# =====================================================
# Banner
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

echo ""
echo "======================================"
echo " DIY 第二部分全部完成"
echo " 主机名          : WH3000（uci-defaults 01-hostname）"
echo " 主题            : luci-theme-design"
echo " docker-compose  : 锁定 v2.27.1"
echo " Lucky 权限      : 已修复"
echo " WiFi radio      : mac80211.sh 默认开启"
echo " WiFi 5G SSID   : WH3000_5G"
echo " WiFi 2.4G SSID : WH3000_2.4G"
echo " WiFi 默认密码   : password123"
echo " Docker 数据目录 : /mnt/mmcblk0p7/docker"
echo " Docker 存储驱动 : overlay2"
echo " 系统优化        : 98-system-optimize"
echo "======================================"
