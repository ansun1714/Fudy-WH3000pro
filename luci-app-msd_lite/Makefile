include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-msd_lite
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0

LUCI_TITLE:=IPTV RTP/UDP/RTSP Server (MSD Lite + rtp2httpd)
LUCI_DEPENDS:=+msd_lite +rtp2httpd

LUCI_PKGARCH:=all

define Package/luci-app-msd_lite/install
	$(call Package/luci-app-msd_lite/install/default,$(1))
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/msd_lite $(1)/etc/config/msd_lite
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/msd_lite $(1)/etc/init.d/msd_lite
endef

include $(TOPDIR)/feeds/luci/luci.mk

$(eval $(call BuildPackage,luci-app-msd_lite))
