#!/bin/bash

echo "========================================"
echo " WH3000 专用优化脚本开始"
echo "========================================"

# =====================================================
# 1. 主机名
# =====================================================
mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/01-system << 'EOF'
#!/bin/sh
uci set system.@system[0].hostname='WH3000'
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci commit system
exit 0
EOF
chmod +x files/etc/uci-defaults/01-system
echo ">>> [1] 主机名配置完成"

# =====================================================
# 2. 默认主题
# =====================================================
sed -i 's/luci-theme-bootstrap/luci-theme-design/g' \
    package/lean/default-settings/files/zzz-default-settings 2>/dev/null
echo ">>> [2] 默认主题修改完成"

# =====================================================
# 3. Lucky 权限
# =====================================================
find . -type f -name "lucky*" -exec chmod +x {} \; 2>/dev/null
echo ">>> [3] Lucky 权限修复完成"

# =====================================================
# 4. WiFi 预配置
# =====================================================
mkdir -p files/etc/config

cat > files/etc/config/wireless << 'EOF'
config wifi-device 'radio0'
	option type 'mac80211'
	option path 'platform/soc/18000000.wifi'
	option band '2g'
	option channel 'auto'
	option htmode 'HT40'
	option country 'CN'
	option cell_density '0'
	option disabled '0'

config wifi-iface 'default_radio0'
	option device 'radio0'
	option network 'lan'
	option mode 'ap'
	option ssid 'WH3000_2.4G'
	option encryption 'psk2'
	option key '12345678'

config wifi-device 'radio1'
	option type 'mac80211'
	option path 'platform/soc/18000000.wifi+1'
	option band '5g'
	option channel '36'
	option htmode 'HE80'
	option country 'CN'
	option cell_density '0'
	option disabled '0'

config wifi-iface 'default_radio1'
	option device 'radio1'
	option network 'lan'
	option mode 'ap'
	option ssid 'WH3000_5G'
	option encryption 'psk2'
	option key '12345678'
EOF
echo ">>> [4] WiFi 预配置完成"

# =====================================================
# 5. WiFi 首启优化
# =====================================================
cat > files/etc/uci-defaults/99-wifi-fast << 'EOF'
#!/bin/sh
rm -f /etc/uci-defaults/network
rm -f /etc/uci-defaults/wireless
wifi reload >/dev/null 2>&1
exit 0
EOF
chmod +x files/etc/uci-defaults/99-wifi-fast
echo ">>> [5] WiFi 首启优化完成"

# =====================================================
# 6. Docker 数据目录
# =====================================================
cat > files/etc/config/fstab << 'EOF'
config global
	option anon_mount '1'
	option auto_mount '1'
	option auto_swap '1'

config mount
	option target '/mnt/mmcblk0p7'
	option device '/dev/mmcblk0p7'
	option fstype 'ext4'
	option options 'rw,sync,noatime'
	option enabled '1'
EOF

cat > files/etc/uci-defaults/30-docker << 'EOF'
#!/bin/sh
mkdir -p /mnt/mmcblk0p7/docker
uci set dockerd.globals.data_root='/mnt/mmcblk0p7/docker'
uci commit dockerd
/etc/init.d/dockerd enable
/etc/init.d/dockerd restart
exit 0
EOF
chmod +x files/etc/uci-defaults/30-docker
echo ">>> [6] Docker 数据目录配置完成"

# =====================================================
# 7. QModem 自动启用
# =====================================================
cat > files/etc/uci-defaults/88-qmodem << 'EOF'
#!/bin/sh
/etc/init.d/qmodem enable >/dev/null 2>&1
/etc/init.d/qmodem start >/dev/null 2>&1
exit 0
EOF
chmod +x files/etc/uci-defaults/88-qmodem
echo ">>> [7] QModem 启用完成"

# =====================================================
# 8. 系统网络优化
# =====================================================
cat > files/etc/sysctl.conf << 'EOF'
net.core.default_qdisc=fq_codel
net.ipv4.tcp_congestion_control=bbr
EOF
echo ">>> [8] 系统优化完成"

# =====================================================
# 9. Banner
# =====================================================
cat > files/etc/banner << 'EOF'

 __        ___   _  _____  ___   ___   ___
 \ \      / / | | ||___ / / _ \ / _ \ / _ \
  \ \ /\ / /| |_| |  |_ \| | | | | | | | | |
   \ V  V / |  _  | ___) | |_| | |_| | |_| |
    \_/\_/  |_| |_||____/ \___/ \___/ \___/

      WH3000 Optimized Build

EOF
echo ">>> [9] Banner 完成"

echo "========================================"
echo " 所有优化完成"
echo " WiFi 2.4G : WH3000_2.4G / 12345678"
echo " WiFi 5G   : WH3000_5G   / 12345678"
echo " Docker    : /mnt/mmcblk0p7/docker"
echo "========================================"
