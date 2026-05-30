#!/bin/bash
# DIY 脚本第一部分：添加自定义软件源

# Lucky
echo "src-git lucky https://github.com/gdy666/luci-app-lucky.git" >> feeds.conf.default

# Qmodem
echo "src-git qmodem https://github.com/FUjr/modem_feeds.git;main" >> feeds.conf.default

# rtp2httpd
echo "src-git rtp2httpd https://github.com/stackia/rtp2httpd.git" >> feeds.conf.default

# msd_lite 主程序（只要二进制，不要它的 init.d）
git clone --depth=1 https://github.com/ximiTech/msd_lite package/msd_lite
# 删除官方自带的 init.d，避免和我们的双后端脚本冲突
rm -f package/msd_lite/files/etc/init.d/msd_lite 2>/dev/null || true

# luci-app-msd_lite 使用仓库里的魔改版（2合1界面）
cp -r ../luci-app-msd_lite package/luci-app-msd_lite

echo "✅ 软件源添加完成"
cat feeds.conf.default
