module("luci.controller.msd_lite", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/msd_lite") then
		return
	end
	entry({"admin", "services", "msd_lite"}, alias("admin", "services", "msd_lite", "general"), _("IPTV RTP/UDP/RTSP"), 80)
	entry({"admin", "services", "msd_lite", "general"}, cbi("msd_lite/settings"), _("Base Setting"), 1)
	entry({"admin", "services", "msd_lite", "status"}, call("status")).leaf = true
end

function status()
	local sys  = require "luci.sys"
	local uci  = require "luci.model.uci".cursor()
	local port = tonumber(uci:get_first("msd_lite", "config", "port"))
	local e = {}
	e.running = luci.sys.call("busybox ps -w | grep msd_lite.conf | grep -v grep >/dev/null") == 0
	e.rtp = luci.sys.call("busybox ps -w | grep rtp2httpd | grep -v grep >/dev/null") == 0
	e.port = (port or 7088)
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end
