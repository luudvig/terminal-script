#!/bin/ash

DEFAULT_RADIO1_SSID='<ssid>'
DEFAULT_RADIO1_KEY='<key>'

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
# SCHEDULED TASKS
############################################################
TEMP_FILE=$(mktemp)
cat << EOF > $TEMP_FILE
# Reboot at 4:30am every day
# Note: To avoid infinite reboot loop, wait 70 seconds
# and touch a file in /etc so clock will be set
# properly to 4:31 on reboot before cron starts.
30 4 * * * sleep 70 && touch /etc/banner && reboot
EOF
crontab $TEMP_FILE

############################################################
# WIRELESS
############################################################
uci set wireless.default_radio1.ssid="$DEFAULT_RADIO1_SSID"
uci set wireless.default_radio1.encryption="sae-mixed"
uci set wireless.default_radio1.key="$DEFAULT_RADIO1_KEY"
uci set wireless.default_radio1.wpa_disable_eapol_key_retries="1"

uci commit wireless
reload_config

############################################################
# SOFTWARE
############################################################
opkg update
opkg install luci-app-https-dns-proxy
