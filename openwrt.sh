#!/bin/ash

DEFAULT_SSID='<ssid>'
DEFAULT_KEY='<key>'
GUEST_SSID='<ssid>'
GUEST_KEY='<key>'

############################################################
# SYSTEM
############################################################
uci set system.@system[0].zonename="Europe/Stockholm"
uci set system.@system[0].timezone="CET-1CEST,M3.5.0,M10.5.0/3"

uci commit system
reload_config

############################################################
# ADMINISTRATION
############################################################
passwd
uci set uhttpd.main.redirect_https="1"

uci commit uhttpd
reload_config

############################################################
# SOFTWARE
############################################################
opkg update
opkg install python3-email python3-light python3-netifaces python3-urllib stubby

############################################################
# STARTUP
############################################################
service odhcpd disable

sed -i "/^exit 0$/i/root/multicast-relay.py --interfaces br-guest br-lan --noSonosDiscovery\n" /etc/rc.local
sed -i "/^exit 0$/i/root/openwrt_guest_cast_revert.sh\n" /etc/rc.local

############################################################
# SCHEDULED TASKS
############################################################
TEMP_FILE=$(mktemp)
cat << EOF > ${TEMP_FILE}
29 4 * * * sleep 70 && touch /etc/banner && reboot
EOF
crontab ${TEMP_FILE}

############################################################
# LED CONFIGURATION
############################################################
uci set system.led_lan.mode="link"
uci set system.led_wan.mode="link"

uci set system.led_wifi2g=led
uci set system.led_wifi2g.name="WIFI2G"
uci set system.led_wifi2g.sysfs="green:wifi2g"
uci set system.led_wifi2g.trigger="none"
uci set system.led_wifi2g.default="0"

uci set system.led_wifi5g=led
uci set system.led_wifi5g.name="WIFI5G"
uci set system.led_wifi5g.sysfs="green:wifi5g"
uci set system.led_wifi5g.trigger="none"
uci set system.led_wifi5g.default="0"

uci commit system
reload_config

############################################################
# INTERFACES
############################################################
uci delete network.lan.ip6assign

uci set network.@device[0].ipv6="0"
uci set network.wan6.disabled="1"

uci set network.guest_dev="device"
uci set network.guest_dev.name="br-guest"
uci set network.guest_dev.type="bridge"
uci set network.guest_dev.ipv6="0"

uci set network.guest="interface"
uci set network.guest.device="br-guest"
uci set network.guest.proto="static"
uci set network.guest.ipaddr="192.168.3.1"
uci set network.guest.netmask="255.255.255.0"

uci commit network
reload_config

############################################################
# WIRELESS
############################################################
uci set wireless.radio0.country="SE"
uci set wireless.radio1.country="SE"

uci set wireless.default_radio0.ssid="${DEFAULT_SSID}"
uci set wireless.default_radio0.encryption="sae-mixed"
uci set wireless.default_radio0.key="${DEFAULT_KEY}"
uci set wireless.default_radio0.wpa_disable_eapol_key_retries="1"
uci set wireless.default_radio0.disabled="1"

uci set wireless.default_radio1.ssid="${DEFAULT_SSID}"
uci set wireless.default_radio1.encryption="sae-mixed"
uci set wireless.default_radio1.key="${DEFAULT_KEY}"
uci set wireless.default_radio1.wpa_disable_eapol_key_retries="1"

uci set wireless.guest_radio0="wifi-iface"
uci set wireless.guest_radio0.device="radio0"
uci set wireless.guest_radio0.network="guest"
uci set wireless.guest_radio0.mode="ap"
uci set wireless.guest_radio0.ssid="${GUEST_SSID}"
uci set wireless.guest_radio0.encryption="sae-mixed"
uci set wireless.guest_radio0.key="${GUEST_KEY}"
uci set wireless.guest_radio0.wpa_disable_eapol_key_retries="1"
uci set wireless.guest_radio0.isolate="1"

uci set wireless.guest_radio1="wifi-iface"
uci set wireless.guest_radio1.device="radio1"
uci set wireless.guest_radio1.network="guest"
uci set wireless.guest_radio1.mode="ap"
uci set wireless.guest_radio1.ssid="${GUEST_SSID}"
uci set wireless.guest_radio1.encryption="sae-mixed"
uci set wireless.guest_radio1.key="${GUEST_KEY}"
uci set wireless.guest_radio1.wpa_disable_eapol_key_retries="1"
uci set wireless.guest_radio1.isolate="1"

uci commit wireless
reload_config

############################################################
# DHCP AND DNS
############################################################
uci delete dhcp.lan.dhcpv6
uci delete dhcp.lan.ra
uci delete dhcp.lan.ra_slaac
uci delete dhcp.lan.ra_flags

uci set dhcp.guest="dhcp"
uci set dhcp.guest.interface="guest"
uci set dhcp.guest.start="100"
uci set dhcp.guest.limit="150"
uci set dhcp.guest.leasetime="12h"
uci set dhcp.guest.dhcpv4="server"

service dnsmasq stop

uci set dhcp.@dnsmasq[0].localuse="0"
uci set dhcp.@dnsmasq[0].noresolv="1"

uci -q get stubby.global.listen_address \
| sed -e "s/\s/\n/g;s/@/#/g" \
| while read -r STUBBY_SERV
do uci add_list dhcp.@dnsmasq[0].server="${STUBBY_SERV}"
done

uci commit dhcp
reload_config

service dnsmasq start

############################################################
# FIREWALL
############################################################
uci show firewall \
| sed -ne "s/\(.*\)=rule$/\1/p" \
| while read -r RULE_KEY
do ( [ -z "$(uci -q get ${RULE_KEY}.family)" ] && uci set ${RULE_KEY}.family="ipv4" ) \
|| ( [ "$(uci -q get ${RULE_KEY}.family)" == "ipv6" ] && uci set ${RULE_KEY}.enabled="0" )
done

uci set firewall.guest="zone"
uci set firewall.guest.name="guest"
uci set firewall.guest.network="guest"
uci set firewall.guest.input="REJECT"
uci set firewall.guest.output="ACCEPT"
uci set firewall.guest.forward="REJECT"

uci set firewall.guest_wan="forwarding"
uci set firewall.guest_wan.src="guest"
uci set firewall.guest_wan.dest="wan"

uci set firewall.guest_dns="rule"
uci set firewall.guest_dns.name="Allow-DNS-Guest"
uci set firewall.guest_dns.src="guest"
uci set firewall.guest_dns.dest_port="53"
uci set firewall.guest_dns.proto="tcp udp"
uci set firewall.guest_dns.family="ipv4"
uci set firewall.guest_dns.target="ACCEPT"

uci set firewall.guest_dhcp="rule"
uci set firewall.guest_dhcp.name="Allow-DHCP-Guest"
uci set firewall.guest_dhcp.src="guest"
uci set firewall.guest_dhcp.dest_port="67"
uci set firewall.guest_dhcp.proto="udp"
uci set firewall.guest_dhcp.family="ipv4"
uci set firewall.guest_dhcp.target="ACCEPT"

uci commit firewall
reload_config

############################################################
# EXTRA
############################################################
wget -P /root https://raw.githubusercontent.com/alsmith/multicast-relay/master/multicast-relay.py
chmod a-w,+x /root/multicast-relay.py

cat << EOF > /root/openwrt_guest_cast_add.sh
#!/bin/ash

LEASE_FILE="/tmp/dhcp.leases"

while read LEASE
do
COUNT=\$((\${COUNT:-0} + 1))
echo "\${COUNT}: \${LEASE}"
done < "\${LEASE_FILE}"

read -p "Select sender: " SENDER

CAST_SEND=\$(sed -e "\${SENDER}q;d" "\${LEASE_FILE}" | cut -d " " -f 3 -s)
CAST_RECV=\$(grep -m 1 "\sChromecast\s" "\${LEASE_FILE}" | cut -d " " -f 3 -s)

uci del_list firewall.guest_mdns.src_ip="\${CAST_SEND}"
uci add_list firewall.guest_mdns.src_ip="\${CAST_SEND}"
uci -q delete firewall.guest_mdns.enabled

uci del_list firewall.guest_ssdp.src_ip="\${CAST_SEND}"
uci add_list firewall.guest_ssdp.src_ip="\${CAST_SEND}"
uci -q delete firewall.guest_ssdp.enabled

uci del_list firewall.guest_cast_from.src_ip="\${CAST_SEND}"
uci add_list firewall.guest_cast_from.src_ip="\${CAST_SEND}"
uci del_list firewall.guest_cast_from.dest_ip="\${CAST_RECV}"
uci add_list firewall.guest_cast_from.dest_ip="\${CAST_RECV}"
uci -q delete firewall.guest_cast_from.enabled

uci del_list firewall.guest_cast_to.src_ip="\${CAST_RECV}"
uci add_list firewall.guest_cast_to.src_ip="\${CAST_RECV}"
uci del_list firewall.guest_cast_to.dest_ip="\${CAST_SEND}"
uci add_list firewall.guest_cast_to.dest_ip="\${CAST_SEND}"
uci -q delete firewall.guest_cast_to.enabled

uci commit firewall
reload_config
EOF
chmod a-w,+x /root/openwrt_guest_cast_add.sh

cat << EOF > /root/openwrt_guest_cast_revert.sh
#!/bin/ash

uci -q delete firewall.guest_mdns
uci set firewall.guest_mdns="rule"
uci set firewall.guest_mdns.name="Allow-mDNS-Guest"
uci set firewall.guest_mdns.src="guest"
uci set firewall.guest_mdns.dest_ip="224.0.0.251"
uci set firewall.guest_mdns.dest_port="5353"
uci set firewall.guest_mdns.proto="udp"
uci set firewall.guest_mdns.family="ipv4"
uci set firewall.guest_mdns.target="ACCEPT"
uci set firewall.guest_mdns.enabled="0"

uci -q delete firewall.guest_ssdp
uci set firewall.guest_ssdp="rule"
uci set firewall.guest_ssdp.name="Allow-SSDP-Guest"
uci set firewall.guest_ssdp.src="guest"
uci set firewall.guest_ssdp.dest_ip="239.255.255.250"
uci set firewall.guest_ssdp.dest_port="1900"
uci set firewall.guest_ssdp.proto="udp"
uci set firewall.guest_ssdp.family="ipv4"
uci set firewall.guest_ssdp.target="ACCEPT"
uci set firewall.guest_ssdp.enabled="0"

uci -q delete firewall.guest_cast_from
uci set firewall.guest_cast_from="rule"
uci set firewall.guest_cast_from.name="Allow-Cast-From-Guest"
uci set firewall.guest_cast_from.src="guest"
uci set firewall.guest_cast_from.dest="lan"
uci set firewall.guest_cast_from.family="ipv4"
uci set firewall.guest_cast_from.target="ACCEPT"
uci set firewall.guest_cast_from.enabled="0"

uci -q delete firewall.guest_cast_to
uci set firewall.guest_cast_to="rule"
uci set firewall.guest_cast_to.name="Allow-Cast-To-Guest"
uci set firewall.guest_cast_to.src="lan"
uci set firewall.guest_cast_to.dest="guest"
uci set firewall.guest_cast_to.family="ipv4"
uci set firewall.guest_cast_to.target="ACCEPT"
uci set firewall.guest_cast_to.enabled="0"

uci commit firewall
reload_config
EOF
chmod a-w,+x /root/openwrt_guest_cast_revert.sh

############################################################
# REBOOT
############################################################
reboot
