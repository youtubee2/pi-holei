#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Web interface settings
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.


readonly setupVars="/etc/pihole/setupVars.conf"
readonly dnsmasqconfig="/etc/dnsmasq.d/01-pihole.conf"
readonly dhcpconfig="/etc/dnsmasq.d/02-pihole-dhcp.conf"
# 03 -> wildcards
readonly dhcpstaticconfig="/etc/dnsmasq.d/04-pihole-static-dhcp.conf"

helpFunc() {
	cat << EOM
::: Set admin options for the web interface of pihole
:::
::: Usage: pihole -a [options]
:::
::: Options:
:::  -p, password		Set web interface password, an empty input will remove any previously set password
:::  -c, celsius		Set Celsius temperature unit
:::  -f, fahrenheit		Set Fahrenheit temperature unit
:::  -k, kelvin			Set Kelvin temperature unit
:::  -h, --help			Show this help dialog
:::  -i, interface		Setup interface listening behavior of dnsmasq
:::               		pihole -a -i local  : Listen on all interfaces, but allow only queries from
:::               		                      devices that are at most one hop away (local devices)
:::               		pihole -a -i single : Listen only on one interface (see PIHOLE_INTERFACE)
:::               		pihole -a -i all    : Listen on all interfaces, permit all origins
EOM
	exit 0
}

add_setting() {
	echo "${1}=${2}" >> "${setupVars}"
}

delete_setting() {
	sed -i "/${1}/d" "${setupVars}"
}

change_setting() {
	delete_setting "${1}"
	add_setting "${1}" "${2}"
}

add_dnsmasq_setting() {
	if [[ "${2}" != "" ]]; then
		echo "${1}=${2}" >> "${dnsmasqconfig}"
	else
		echo "${1}" >> "${dnsmasqconfig}"
	fi
}

delete_dnsmasq_setting() {
	sed -i "/${1}/d" "${dnsmasqconfig}"
}

SetTemperatureUnit(){

	change_setting "TEMPERATUREUNIT" "${unit}"

}

SetWebPassword(){

	if [ "${SUDO_USER}" == "www-data" ]; then
		echo "Security measure: user www-data is not allowed to change webUI password!"
		echo "Exiting"
		exit 1
	fi

	if [ "${SUDO_USER}" == "lighttpd" ]; then
		echo "Security measure: user lighttpd is not allowed to change webUI password!"
		echo "Exiting"
		exit 1
	fi

	# Set password only if there is one to be set
	if (( ${#args[2]} > 0 )) ; then
		# Compute password hash twice to avoid rainbow table vulnerability
		hash=$(echo -n ${args[2]} | sha256sum | sed 's/\s.*$//')
		hash=$(echo -n ${hash} | sha256sum | sed 's/\s.*$//')
		# Save hash to file
		change_setting "WEBPASSWORD" "${hash}"
		echo "New password set"
	else
		change_setting "WEBPASSWORD" ""
		echo "Password removed"
	fi

}

ProcessDNSSettings() {
	source "${setupVars}"

	delete_dnsmasq_setting "server"

	COUNTER=1
	while [[ 1 ]]; do
		var=PIHOLE_DNS_${COUNTER}
		if [ -z "${!var}" ]; then
			break;
		fi
		add_dnsmasq_setting "server" "${!var}"
		let COUNTER=COUNTER+1
	done

	delete_dnsmasq_setting "domain-needed"

	if [[ "${DNS_FQDN_REQUIRED}" == true ]]; then
		add_dnsmasq_setting "domain-needed"
	fi

	delete_dnsmasq_setting "bogus-priv"

	if [[ "${DNS_BOGUS_PRIV}" == true ]]; then
		add_dnsmasq_setting "bogus-priv"
	fi

	delete_dnsmasq_setting "dnssec"
	delete_dnsmasq_setting "trust-anchor="

	if [[ "${DNSSEC}" == true ]]; then
		echo "dnssec
trust-anchor=.,19036,8,2,49AAC11D7B6F6446702E54A1607371607A1A41855200FD2CE1CDDE32F24E8FB5
" >> "${dnsmasqconfig}"
	fi

	delete_dnsmasq_setting "host-record"

	if [ ! -z "${HOSTRECORD+x}" ]; then
		add_dnsmasq_setting "host-record" "${HOSTRECORD}"
	fi

	# Setup interface listening behavior of dnsmasq
	delete_dnsmasq_setting "interface"
	delete_dnsmasq_setting "local-service"

	if [[ "${DNSMASQ_LISTENING}" == "all" ]]; then
		# Listen on all interfaces, permit all origins
		add_dnsmasq_setting "except-interface" "nonexisting"
	elif [[ "${DNSMASQ_LISTENING}" == "local" ]]; then
		# Listen only on all interfaces, but only local subnets
		add_dnsmasq_setting "local-service"
	else
		# Listen only on one interface
		add_dnsmasq_setting "interface" "${PIHOLE_INTERFACE}"
	fi

}

SetDNSServers(){

	# Save setting to file
	delete_setting "PIHOLE_DNS"
	IFS=',' read -r -a array <<< "${args[2]}"
	for index in "${!array[@]}"
	do
		add_setting "PIHOLE_DNS_$((index+1))" "${array[index]}"
	done

	if [[ "${args[3]}" == "domain-needed" ]]; then
		change_setting "DNS_FQDN_REQUIRED" "true"
	else
		change_setting "DNS_FQDN_REQUIRED" "false"
	fi

	if [[ "${args[4]}" == "bogus-priv" ]]; then
		change_setting "DNS_BOGUS_PRIV" "true"
	else
		change_setting "DNS_BOGUS_PRIV" "false"
	fi

	if [[ "${args[5]}" == "dnssec" ]]; then
		change_setting "DNSSEC" "true"
	else
		change_setting "DNSSEC" "false"
	fi

	ProcessDNSSettings

	# Restart dnsmasq to load new configuration
	RestartDNS

}

SetExcludeDomains(){

	change_setting "API_EXCLUDE_DOMAINS" "${args[2]}"

}

SetExcludeClients(){

	change_setting "API_EXCLUDE_CLIENTS" "${args[2]}"

}

Reboot(){

	nohup bash -c "sleep 5; reboot" &> /dev/null </dev/null &

}

RestartDNS(){

	if [ -x "$(command -v systemctl)" ]; then
		systemctl restart dnsmasq &> /dev/null
	else
		service dnsmasq restart &> /dev/null
	fi

}

SetQueryLogOptions(){

	change_setting "API_QUERY_LOG_SHOW" "${args[2]}"

}

ProcessDHCPSettings() {

	source "${setupVars}"

	if [[ "${DHCP_ACTIVE}" == "true" ]]; then

	interface=$(grep 'PIHOLE_INTERFACE=' /etc/pihole/setupVars.conf | sed "s/.*=//")

	# Use eth0 as fallback interface
	if [ -z ${interface} ]; then
		interface="eth0"
	fi

	if [[ "${PIHOLE_DOMAIN}" == "" ]]; then
		PIHOLE_DOMAIN="local"
		change_setting "PIHOLE_DOMAIN" "${PIHOLE_DOMAIN}"
	fi

	if [[ "${DHCP_LEASETIME}" == "0" ]]; then
		leasetime="infinite"
	elif [[ "${DHCP_LEASETIME}" == "" ]]; then
		leasetime="24h"
		change_setting "DHCP_LEASETIME" "${leasetime}"
	else
		leasetime="${DHCP_LEASETIME}h"
	fi

	# Write settings to file
	echo "###############################################################################
#  DHCP SERVER CONFIG FILE AUTOMATICALLY POPULATED BY PI-HOLE WEB INTERFACE.  #
#            ANY CHANGES MADE TO THIS FILE WILL BE LOST ON CHANGE             #
###############################################################################
dhcp-authoritative
dhcp-range=${DHCP_START},${DHCP_END},${leasetime}
dhcp-option=option:router,${DHCP_ROUTER}
dhcp-leasefile=/etc/pihole/dhcp.leases
#quiet-dhcp
" > "${dhcpconfig}"

if [[ "${PIHOLE_DOMAIN}" != "none" ]]; then
	echo "domain=${PIHOLE_DOMAIN}" >> "${dhcpconfig}"
fi

	if [[ "${DHCP_IPv6}" == "true" ]]; then
echo "#quiet-dhcp6
#enable-ra
dhcp-option=option6:dns-server,[::]
dhcp-range=::100,::1ff,constructor:${interface},ra-names,slaac,${leasetime}
ra-param=*,0,0
" >> "${dhcpconfig}"
	fi

	else
		rm "${dhcpconfig}" &> /dev/null
	fi
}

EnableDHCP(){

	change_setting "DHCP_ACTIVE" "true"
	change_setting "DHCP_START" "${args[2]}"
	change_setting "DHCP_END" "${args[3]}"
	change_setting "DHCP_ROUTER" "${args[4]}"
	change_setting "DHCP_LEASETIME" "${args[5]}"
	change_setting "PIHOLE_DOMAIN" "${args[6]}"
	change_setting "DHCP_IPv6" "${args[7]}"

	# Remove possible old setting from file
	delete_dnsmasq_setting "dhcp-"
	delete_dnsmasq_setting "quiet-dhcp"

	ProcessDHCPSettings

	RestartDNS
}

DisableDHCP(){

	change_setting "DHCP_ACTIVE" "false"

	# Remove possible old setting from file
	delete_dnsmasq_setting "dhcp-"
	delete_dnsmasq_setting "quiet-dhcp"

	ProcessDHCPSettings

	RestartDNS
}

SetWebUILayout(){

	change_setting "WEBUIBOXEDLAYOUT" "${args[2]}"

}

SetPrivacyMode(){

	if [[ "${args[2]}" == "true" ]] ; then
		change_setting "API_PRIVACY_MODE" "true"
	else
		change_setting "API_PRIVACY_MODE" "false"
	fi

}

ResolutionSettings() {

	typ="${args[2]}"
	state="${args[3]}"

	if [[ "${typ}" == "forward" ]]; then
		change_setting "API_GET_UPSTREAM_DNS_HOSTNAME" "${state}"
	elif [[ "${typ}" == "clients" ]]; then
		change_setting "API_GET_CLIENT_HOSTNAME" "${state}"
	fi

}

AddDHCPStaticAddress() {

	mac="${args[2]}"
	ip="${args[3]}"
	host="${args[4]}"

	if [[ "${ip}" == "noip" ]]; then
		# Static host name
		echo "dhcp-host=${mac},${host}" >> "${dhcpstaticconfig}"
	elif [[ "${host}" == "nohost" ]]; then
		# Static IP
		echo "dhcp-host=${mac},${ip}" >> "${dhcpstaticconfig}"
	else
		# Full info given
		echo "dhcp-host=${mac},${ip},${host}" >> "${dhcpstaticconfig}"
	fi

}

RemoveDHCPStaticAddress() {

	mac="${args[2]}"
	sed -i "/dhcp-host=${mac}.*/d" "${dhcpstaticconfig}"

}

SetHostRecord(){

	if [ -n "${args[3]}" ]; then
		change_setting "HOSTRECORD" "${args[2]},${args[3]}"
		echo "Setting host record for ${args[2]} -> ${args[3]}"
	else
		change_setting "HOSTRECORD" ""
		echo "Removing host record"
	fi

	ProcessDNSSettings

	# Restart dnsmasq to load new configuration
	RestartDNS

}

SetListeningMode(){

	source "${setupVars}"

	if [[ "${args[2]}" == "all" ]] ; then
		echo "Listening on all interfaces, permiting all origins, hope you have a firewall!"
		change_setting "DNSMASQ_LISTENING" "all"
	elif [[ "${args[2]}" == "local" ]] ; then
		echo "Listening on all interfaces, permitting only origins that are at most one hop away (local devices)"
		change_setting "DNSMASQ_LISTENING" "local"
	else
		echo "Listening only on interface ${PIHOLE_INTERFACE}"
		change_setting "DNSMASQ_LISTENING" "single"
	fi

	# Don't restart DNS server yet because other settings
	# will be applied afterwards if "-web" is set
	if [[ "${args[3]}" != "-web" ]]; then
		ProcessDNSSettings
		# Restart dnsmasq to load new configuration
		RestartDNS
	fi

}

main() {

	args=("$@")

	case "${args[1]}" in
		"-p" | "password"   ) SetWebPassword;;
		"-c" | "celsius"    ) unit="C"; SetTemperatureUnit;;
		"-f" | "fahrenheit" ) unit="F"; SetTemperatureUnit;;
		"-k" | "kelvin"     ) unit="K"; SetTemperatureUnit;;
		"setdns"            ) SetDNSServers;;
		"setexcludedomains" ) SetExcludeDomains;;
		"setexcludeclients" ) SetExcludeClients;;
		"reboot"            ) Reboot;;
		"restartdns"        ) RestartDNS;;
		"setquerylog"       ) SetQueryLogOptions;;
		"enabledhcp"        ) EnableDHCP;;
		"disabledhcp"       ) DisableDHCP;;
		"layout"            ) SetWebUILayout;;
		"-h" | "--help"     ) helpFunc;;
		"privacymode"       ) SetPrivacyMode;;
		"resolve"           ) ResolutionSettings;;
		"addstaticdhcp"     ) AddDHCPStaticAddress;;
		"removestaticdhcp"  ) RemoveDHCPStaticAddress;;
		"hostrecord"        ) SetHostRecord;;
		"-i" | "interface"  ) SetListeningMode;;
		*                   ) helpFunc;;
	esac

	shift

	if [[ $# = 0 ]]; then
		helpFunc
	fi

}
