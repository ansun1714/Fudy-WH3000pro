local sys = require "luci.sys"

m = Map("msd_lite", "RTP/UDP/RTSP IPTV Server", translate("Multi Stream daemon (msd) / rtp2httpd for IPTV streaming on the network via HTTP"))

m:section(SimpleSection).template = "msd_lite/msdlite_status"

s = m:section(TypedSection, "msd_lite")
s.addremove = false
s.anonymous = true

enable=s:option(Flag, "enable", translate("Enabled"))
enable.rmempty = false

type=s:option(ListValue, "type", translate("Program Select"))
type:value("0", translate("MSD Lite"))
type:value("1", translate("rtp2httpd"))
type.default = "0"

port=s:option(Value, "port", translate("Port"))
port.datatype = "port"
port.default = "7088"
port.rmempty = false

source=s:option(Value, "source", translate("Source Interface VLAN"))
source.datatype = "network"
source.default = "eth0.85"
source.rmempty = false
for _, e in ipairs(sys.net.devices()) do
	if e ~= "lo" then source:value(e) end
end

threads=s:option(Value, "threads", translate("Max CPU threads"))
threads.default = "0"
threads.rmempty = false
threads:value("0", translate("Auto Threads"))
threads:value("1")
threads:value("2")
threads:value("3")
threads:value("4")
threads.description = translate("0 = auto")

buffer=s:option(Value, "buffer", translate("Buffer Size"))
buffer.default = "16384"
buffer.rmempty = false

rejointime=s:option(Value, "rejointime", translate("IGMP Rejoin Time"))
rejointime.default = "0"
rejointime.rmempty = true
rejointime.datatype = "uinteger"
rejointime.description = translate("0 = off")

return m
