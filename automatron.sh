#!/bin/bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INTERNET_IFACE="eth0"
AP_IFACE="wlan0"
AP_ESSID="FREE_WIFI"
AP_CHANELL="1"
AP_IP="192.168.100.1"
AP_MASK="24"
DHCP_FIRST="192.168.100.10"
DHCP_LAST="192.168.100.250"
DHCP_MASK="255.255.255.0"
RESOLVE_SERVER_1="1.1.1.1"
RESOLVE_SERVER_2="1.0.0.1"

# Kill interrupt process
/etc/init.d/network-manager stop 2>/dev/null
killall wpa_supplicant 2>/dev/null

# Interface settings
while true
do
	if ip link show | grep "${INTERNET_IFACE}" >/dev/null 2>&1; then
		echo "Interface ${INTERNET_IFACE} is up.";
		break
	else
		echo "Interface ${INTERNET_IFACE} is down, wait..."
		sleep 5
fi
done

while true
do
	dhclient ${INTERNET_IFACE}
        if ifconfig ${INTERNET_IFACE} | grep "inet " >/dev/null 2>&1; then
                echo "Interface ${INTERNET_IFACE} is configured.";
                break
        else
                echo "Interface ${INTERNET_IFACE} is not configured, wait..."
                sleep 30
fi
done

ifconfig ${AP_IFACE} down
ifconfig ${AP_IFACE} ${AP_IP}/${AP_MASK}
ifconfig ${AP_IFACE} up

# IP forward
iptables -t nat -F
iptables -F
iptables -t nat -A POSTROUTING -o ${INTERNET_IFACE} -j MASQUERADE
iptables -A FORWARD -i ${AP_IFACE} -o ${INTERNET_IFACE} -j ACCEPT
echo '1' > /proc/sys/net/ipv4/ip_forward

# Apache2 fish settings
if [ -f ${CURRENT_DIR}/hosts.txt ]; then
	rm -f ${CURRENT_DIR}/hosts.txt
fi

python ${CURRENT_DIR}/Apache2-fish/apache2_setup_proxy.py -E

while read -r site
do
	if ! [ -z "$site" ]; then
		python ${CURRENT_DIR}/Apache2-fish/apache2_setup_proxy.py -q -u ${site}
		host="${site//https:\/\//}"
		host="${host//http:\/\//}"
		echo -e "${AP_IP}\t${host}" >> ${CURRENT_DIR}/hosts.txt
	fi
done < ${CURRENT_DIR}/sites.txt
/etc/init.d/apache2 restart

# Hostapd settings
cat >${CURRENT_DIR}/hostapd.conf <<EOH
interface=${AP_IFACE}
driver=nl80211
ssid=${AP_ESSID}
channel=${AP_CHANELL}
EOH

kill -9 $(pgrep hostapd) 2>/dev/null
/usr/sbin/hostapd ${CURRENT_DIR}/hostapd.conf -B -f /var/log/hostapd.log

# Dnsmasq settings
cat >${CURRENT_DIR}/dnsmasq.conf <<EOD
server=${RESOLVE_SERVER_1}
server=${RESOLVE_SERVER_2}
interface=${AP_IFACE}
dhcp-range=${DHCP_FIRST},${DHCP_LAST},${DHCP_MASK},12h
dhcp-option=3,${AP_IP}
dhcp-option=6,${AP_IP}
log-queries
log-facility=/var/log/dnsmasq.log
EOD

kill -9 $(pgrep dnsmasq) 2>/dev/null
/usr/sbin/dnsmasq -C ${CURRENT_DIR}/dnsmasq.conf -H ${CURRENT_DIR}/hosts.txt -d >/var/log/dnsmasq_debug.log 2>&1 &
