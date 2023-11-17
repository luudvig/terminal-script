#!/bin/ash

DEFAULT_RADIO1_SSID='<ssid>'
DEFAULT_RADIO1_KEY='<key>'
GUEST_SSID='<ssid>'
GUEST_KEY='<key>'

############################################################
# SYSTEM
############################################################
uci set system.@system[0].zonename="Europe/Stockholm"

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
opkg install stubby

############################################################
# SCHEDULED TASKS
############################################################
TEMP_FILE=$(mktemp)
cat << EOF > ${TEMP_FILE}
# Reboot at 4:30am every day
# Note: To avoid infinite reboot loop, wait 70 seconds
# and touch a file in /etc so clock will be set
# properly to 4:31 on reboot before cron starts.
30 4 * * * sleep 70 && touch /etc/banner && reboot
EOF
crontab ${TEMP_FILE}

############################################################
# INTERFACES
############################################################
uci set network.guest_dev="device"
uci set network.guest_dev.type="bridge"
uci set network.guest_dev.name="br-guest"

uci set network.guest="interface"
uci set network.guest.proto="static"
uci set network.guest.device="br-guest"
uci set network.guest.ipaddr="192.168.3.1"
uci set network.guest.netmask="255.255.255.0"

uci commit network
reload_config

############################################################
# WIRELESS
############################################################
uci set wireless.default_radio1.ssid="${DEFAULT_RADIO1_SSID}"
uci set wireless.default_radio1.encryption="sae-mixed"
uci set wireless.default_radio1.key="${DEFAULT_RADIO1_KEY}"
uci set wireless.default_radio1.wpa_disable_eapol_key_retries="1"

uci set wireless.guest="wifi-iface"
uci set wireless.guest.device="radio1"
uci set wireless.guest.mode="ap"
uci set wireless.guest.network="guest"
uci set wireless.guest.ssid="${GUEST_SSID}"
uci set wireless.guest.encryption="sae-mixed"
uci set wireless.guest.key="${GUEST_KEY}"
uci set wireless.guest.wpa_disable_eapol_key_retries="1"
uci set wireless.guest.isolate="1"

uci commit wireless
reload_config

############################################################
# DHCP AND DNS
############################################################
uci set dhcp.guest="dhcp"
uci set dhcp.guest.interface="guest"
uci set dhcp.guest.start="100"
uci set dhcp.guest.limit="150"
uci set dhcp.guest.leasetime="12h"

service dnsmasq stop

uci set dhcp.@dnsmasq[0].noresolv="1"
uci set dhcp.@dnsmasq[0].localuse="1"

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
# REBOOT
############################################################
reboot
