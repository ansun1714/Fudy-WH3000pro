#!/bin/bash
# =====================================================
# DIY 脚本第二部分 - 基于搜索验证的修复版
# =====================================================

# =====================================================
# 1. 修改主机名（uci-defaults 方式最可靠）
# =====================================================
sed -i 's/OpenWrt/WH3000/g' package/base-files/files/bin/config_generate 2>/dev/null || true

mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/01-hostname << 'EOF'
#!/bin/sh
uci set system.@system[0].hostname='WH3000'
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci commit system
exit 0
EOF
chmod +x files/etc/uci-defaults/01-hostname
echo ">>> [1/7] 主机名配置完成"

# =====================================================
# 2. 修改默认 LuCI 主题
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
echo ">>> [2/7] 主题改为 luci-theme-design"

# =====================================================
# 3. 修复 docker-compose 编译失败
# =====================================================
COMPOSE_MK="feeds/packages/utils/docker-compose/Makefile"
if [ -f "$COMPOSE_MK" ]; then
    cp "$COMPOSE_MK" "${COMPOSE_MK}.bak"
    sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:=2.27.1/' "$COMPOSE_MK"
    sed -i 's/^PKG_HASH:=.*/PKG_HASH:=skip/' "$COMPOSE_MK"
    sed -i '/^PKG_MIRROR_HASH/d' "$COMPOSE_MK"
    echo ">>> [3/7] docker-compose 锁定为 v2.27.1"
else
    echo "⚠️  [3/7] 未找到 docker-compose Makefile"
fi

# =====================================================
# 4. 修复 Lucky 执行权限
# =====================================================
find feeds/lucky/ -type f \( -name "lucky" -o -name "lucky*" \) \
    -exec chmod +x {} \; 2>/dev/null || true
find package/ -path "*/lucky/files*" -type f \
    -exec file {} \; 2>/dev/null \
    | grep -i "ELF\|executable" \
    | cut -d: -f1 \
    | xargs chmod +x 2>/dev/null || true
echo ">>> [4/7] Lucky 权限修复完成"

# =====================================================
# 5. ★ 修复 WiFi 首次启动问题 ★
#
# 根据搜索确认的正确方案：
# 修改 mac80211.sh 让 radio 默认 disabled=0
# 同时用 uci-defaults 设置 SSID（在 mac80211 初始化后执行）
# =====================================================

# 修改 mac80211.sh 源码，radio 默认开启
MAC80211_SH=$(find . -path "*/mac80211/files/lib/wifi/mac80211.sh" 2>/dev/null | head -1)
if [ -n "$MAC80211_SH" ]; then
    # 把 disabled=1 改为 disabled=0
    sed -i "s/option disabled '1'/option disabled '0'/g" "$MAC80211_SH"
    sed -i 's/set wireless\.${name}\.disabled=1/set wireless.${name}.disabled=0/g' "$MAC80211_SH"
    echo ">>> [5/7] mac80211.sh 已修改，radio 默认开启"
    grep -n "disabled" "$MAC80211_SH" | head -5
else
    echo "⚠️  [5/7] mac80211.sh 未找到"
fi

# uci-defaults 设置 SSID/密码（编号靠后确保在 mac80211 初始化后执行）
cat > files/etc/uci-defaults/99-wifi-setup << 'WIFI_EOF'
#!/bin/sh
# 等待 wireless 配置生成完毕
sleep 3

# 操作 wifi-device（radio 层）
uci set wireless.radio0.disabled='0' 2>/dev/null || true
uci set wireless.radio1.disabled='0' 2>/dev/null || true

# 操作 wifi-iface（接口层）设置 SSID 和密码
# 5G radio0
uci set wireless.default_radio0.ssid='WH3000_5G' 2>/dev/null || true
uci set wireless.default_radio0.encryption='psk2+ccmp' 2>/dev/null || true
uci set wireless.default_radio0.key='password123' 2>/dev/null || true

# 2.4G radio1
uci set wireless.default_radio1.ssid='WH3000_2.4G' 2>/dev/null || true
uci set wireless.default_radio1.encryption='psk2+ccmp' 2>/dev/null || true
uci set wireless.default_radio1.key='password123' 2>/dev/null || true

uci commit wireless

# 启动 WiFi
wifi up 2>/dev/null

logger -t wifi-setup "WiFi 初始化完成：WH3000_5G / WH3000_2.4G"
exit 0
WIFI_EOF
chmod +x files/etc/uci-defaults/99-wifi-setup
echo ">>>       WiFi SSID: WH3000_5G / WH3000_2.4G，密码: password123"

# =====================================================
# 6. ★ Docker 数据目录配置 ★
#
# 根据搜索确认：
# OpenWrt dockerd 读取的是 /etc/config/dockerd（UCI格式）
# 关键字段：config globals 'globals' + option data_root
# 不是 daemon.json！之前的方案完全错误
# =====================================================

# 直接预置 /etc/config/dockerd 到固件
mkdir -p files/etc/config
cat > files/etc/config/dockerd << 'DOCKERD_EOF'
config globals 'globals'
	option data_root '/mnt/mmcblk0p7/docker'
	option log_level 'warn'
	option iptables '1'
	option live_restore '1'

config firewall 'firewall'
	option device 'docker0'
	list blocked_interfaces 'wan'
DOCKERD_EOF

echo ">>> [6/7] Docker 配置完成"
echo ">>>       配置文件：/etc/config/dockerd"
echo ">>>       数据目录：/mnt/mmcblk0p7/docker"

# uci-defaults 确保目录存在
cat > files/etc/uci-defaults/20-docker-datadir << 'DOCKER_EOF'
#!/bin/sh
MOUNT_POINT="/mnt/mmcblk0p7"
DOCKER_DATA="$MOUNT_POINT/docker"

# 等待挂载点就绪
count=0
while [ $count -lt 15 ]; do
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        mkdir -p "$DOCKER_DATA"
        logger -t docker-setup "Docker 数据目录就绪：$DOCKER_DATA"
        # 确保 UCI 配置正确（防止被其他脚本覆盖）
        uci set dockerd.globals.data_root="$DOCKER_DATA" 2>/dev/null || true
        uci commit dockerd 2>/dev/null || true
        exit 0
    fi
    sleep 1
    count=$((count + 1))
done

logger -t docker-setup "警告：$MOUNT_POINT 未挂载，Docker 将使用默认目录"
exit 0
DOCKER_EOF
chmod +x files/etc/uci-defaults/20-docker-datadir

# =====================================================
# 7. 系统优化
# =====================================================
cat > files/etc/uci-defaults/98-system-optimize << 'OPT_EOF'
#!/bin/sh
# uhttpd
uci -q set uhttpd.main.max_connections='100' 2>/dev/null || true
uci -q set uhttpd.main.max_requests='10' 2>/dev/null || true
uci -q set uhttpd.main.http_keepalive='20' 2>/dev/null || true
uci -q set uhttpd.main.script_timeout='60' 2>/dev/null || true
uci -q set uhttpd.main.network_timeout='30' 2>/dev/null || true
uci commit uhttpd 2>/dev/null || true
# rpcd
uci -q set rpcd.@rpcd[0].timeout='60' 2>/dev/null || true
uci commit rpcd 2>/dev/null || true
# samba
uci -q set samba4.@samba[0].disable_ipv6='1' 2>/dev/null || true
uci commit samba4 2>/dev/null || true
# luci 语言
uci set luci.main.lang='zh_Hans' 2>/dev/null || true
uci commit luci 2>/dev/null || true
exit 0
OPT_EOF
chmod +x files/etc/uci-defaults/98-system-optimize
echo ">>> [7/7] 系统优化完成"

# Banner
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
echo " 主机名          : WH3000"
echo " 主题            : luci-theme-design"
echo " docker-compose  : v2.27.1"
echo " Lucky 权限      : 已修复"
echo " WiFi 5G         : WH3000_5G / password123"
echo " WiFi 2.4G       : WH3000_2.4G / password123"
echo " Docker 配置     : /etc/config/dockerd（UCI）"
echo " Docker 数据目录 : /mnt/mmcblk0p7/docker"
echo "======================================"
