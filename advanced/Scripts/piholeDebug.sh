#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Generates pihole_debug.log to be used for troubleshooting.
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

set -o pipefail

######## GLOBAL VARS ########
DEBUG_LOG="/var/log/pihole_debug.log"
DNSMASQFILE="/etc/dnsmasq.conf"
PIHOLECONFFILE="/etc/dnsmasq.d/01-pihole.conf"
LIGHTTPDFILE="/etc/lighttpd/lighttpd.conf"
LIGHTTPDERRFILE="/var/log/lighttpd/error.log"
GRAVITYFILE="/etc/pihole/gravity.list"
HOSTSFILE="/etc/hosts"
WHITELISTFILE="/etc/pihole/whitelist.txt"
BLACKLISTFILE="/etc/pihole/blacklist.txt"
ADLISTSFILE="/etc/pihole/adlists.list"
PIHOLELOG="/var/log/pihole.log"
WHITELISTMATCHES="/tmp/whitelistmatches.list"

# Default to no IPv6, will check and enable if needed.
IPV6_ENABLED=false

# Header info and introduction
cat << EOM
::: Beginning Pi-hole debug at $(date)!
:::
::: This debugging process will collect information from your Pi-hole,
::: and optionally upload the generated log to a unique and random directory on
::: tricorder.pi-hole.net. NOTE: All log files auto-delete after 24 hours and only
::: the Pi-hole developers can access your data via the generated token. We have taken
::: these extra steps to secure your data and we will work to further reduce any
::: personal information gathered.
:::
::: Please read and note any issues, and follow any directions advised during this process.
:::
EOM

# Ensure the file exists, create if not, clear if exists.
if [ ! -f "${DEBUG_LOG}" ]; then
	touch ${DEBUG_LOG}
	chmod 644 ${DEBUG_LOG}
	chown "$USER":root ${DEBUG_LOG}
else
	truncate -s 0 ${DEBUG_LOG}
fi

### Private functions exist here ###
log_write() {
    echo "${1}" >> "${DEBUG_LOG}"
}

header_write() {
  echo "" >> "${DEBUG_LOG}"
  echo "::: ${1}" >> "${DEBUG_LOG}"
  echo "" >> "${DEBUG_LOG}"
}

log_echo() {
  case ${1} in
    -n)
      echo -n ":::       ${2}"
      log_write "${2}"
      ;;
    -l)
      echo "${2}"
      log_write "${2}"
      ;;
     *)
      echo ":::       ${1}"
      log_write "${1}"
  esac
}

file_parse() {
    while read -r line; do
		  if [ ! -z "${line}" ]; then
			  [[ "${line}" =~ ^#.*$ ]] && continue
				log_write "${line}"
			fi
		done < "${1}"
}

block_parse() {
  log_write "${1}"
}

lsof_parse() {
  local user
  local process
  local match

  user=$(echo ${1} | cut -f 3 -d ' ' | cut -c 2-)
  process=$(echo ${1} | cut -f 2 -d ' ' | cut -c 2-)
  if [[ ${2} -eq ${process} ]]; then
    match="as required."
  else
    match="incorrectly."
  fi
  log_echo -l "by ${user} for ${process} ${match}"
}


version_check() {
  header_write "Installed Package Versions"

  local error_found
  error_found=0

	echo ":::     Detecting Pi-hole installed versions."

	local pi_hole_ver="$(cd /etc/.pihole/ && git describe --tags --abbrev=0)" \
	&& log_echo "Pi-hole: $pi_hole_ver" || (log_echo "Pi-hole git repository not detected." && error_found=1)
	local admin_ver="$(cd /var/www/html/admin && git describe --tags --abbrev=0)" \
	&& log_echo "WebUI: $admin_ver" || (log_echo "Pi-hole Admin Pages git repository not detected." && error_found=1)
	local light_ver="$(lighttpd -v |& head -n1 | cut -d " " -f1)" \
	&& log_echo "${light_ver}" || (log_echo "lighttpd not installed." && error_found=1)
	local php_ver="$(php -v |& head -n1)" \
	&& log_echo "${php_ver}" || (log_echo "PHP not installed." && error_found=1)
	echo ":::"
	return "${error_found}"
}

files_check() {
  header_write "File Check"

  #Check non-zero length existence of ${1}
  log_echo -n "Detecting existence of ${1}:"
  local search_file="${1}"
  if [[ -s ${search_file} ]]; then
    echo " exists"
     file_parse "${search_file}"
     return 0
	else
    log_echo "${1} not found!"
    return 1
  fi
  echo ":::"
}

source_file() {
  local file_found=$(files_check "${1}") \
   && (source "${1}" &> /dev/null && log_echo -l "${file_found} and was successfully sourced") \
   || log_echo -l "${file_found} and could not be sourced"
}

distro_check() {
  header_write "Installed OS Distribution"

	echo ":::     Checking installed OS Distribution release."
	local distro="$(cat /etc/*release)" && block_parse "${distro}" || log_echo "Distribution details not found."
	echo ":::"
}

ipv6_check() {
  # Check if system is IPv6 enabled, for use in other functions
  if [[ -a /proc/net/if_inet6 ]]; then
    IPV6_ENABLED=true
    return 0
  else
    return 1
  fi
}

ip_check() {
	header_write "IP Address Information"
	# Get the current interface for Internet traffic

	# Check if IPv6 enabled
	local IPv6_interface
	ipv6_check &&	IPv6_interface=${piholeInterface:-$(ip -6 r | grep default | cut -d ' ' -f 5)}
	# If declared in setupVars.conf use it, otherwise defer to default
	# http://stackoverflow.com/questions/2013547/assigning-default-values-to-shell-variables-with-a-single-command-in-bash

	echo ":::     Collecting local IP info."
	local IPv4_addr_list="$(ip a | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "inet") print $(i+1) }')" \
	&& (block_parse "${IPv4_addr_list}" && echo ":::       IPv4 addresses located")\
	|| log_echo "No IPv4 addresses found."

	local IPv4_def_gateway=$(ip r | grep default | cut -d ' ' -f 3)
	if [[ $? = 0 ]]; then
		echo -n ":::     Pinging default IPv4 gateway: "
		local IPv4_def_gateway_check="$(ping -q -w 3 -c 3 -n "${IPv4_def_gateway}" | tail -n3)" \
		&& echo "Gateway responded." \
		|| echo "Gateway did not respond."
		block_parse "${IPv4_def_gateway_check}"

		echo -n ":::     Pinging Internet via IPv4: "
		local IPv4_inet_check="$(ping -q -w 5 -c 3 -n 8.8.8.8 | tail -n3)" \
		&& echo "Query responded." \
		|| echo "Query did not respond."
		block_parse "${IPv4_inet_check}"
	fi

  if [[ IPV6_ENABLED ]]; then
    local IPv6_addr_list="$(ip a | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "inet6") print $(i+1) }')" \
	  && (log_write "${IPv6_addr_list}" && echo ":::       IPv6 addresses located") \
	  || log_echo "No IPv6 addresses found."

    local IPv6_def_gateway=$(ip -6 r | grep default | cut -d ' ' -f 3)
    if [[ $? = 0 ]] && [[ -n ${IPv6_def_gateway} ]]; then
      echo -n ":::     Pinging default IPv6 gateway: "
      local IPv6_def_gateway_check="$(ping6 -q -W 3 -c 3 -n "${IPv6_def_gateway}" -I "${IPv6_interface}"| tail -n3)" \
      && echo "Gateway Responded." \
      || echo "Gateway did not respond."
      block_parse "${IPv6_def_gateway_check}"

      echo -n ":::     Pinging Internet via IPv6: "
      local IPv6_inet_check=$(ping6 -q -W 3 -c 3 -n 2001:4860:4860::8888 -I "${IPv6_interface}"| tail -n3) \
      && echo "Query responded." \
      || echo "Query did not respond."
      block_parse "${IPv6_inet_check}"
    else
      log_echo="No IPv6 Gateway Detected"
    fi
    echo ":::"
  fi
}

hostnameCheck() {
	header_write "Hostname Information"

	echo ":::     Writing locally configured hostnames to logfile"
	# Write the hostname output to compare against entries in /etc/hosts, which is logged next
	log_write "This Pi-hole is: $(hostname)"

	echo ":::     Writing hosts file to debug log..."
	log_write ":::       Hosts File Contents"

	if [[ -e "${HOSTSFILE}" ]]; then
		file_parse "${HOSTSFILE}"
		else
		log_echo "No hosts file found!"
	fi

	echo ":::"
}


daemon_check() {
  # Check for daemon ${1} on port ${2}
	header_write "Daemon Process Information"

	echo ":::     Checking port ${2} for ${1} listener."
  local found_daemon=false
	local lsof_value

	if [[ ${IPV6_ENABLED} ]]; then
	  lsof_value=$(lsof -i 6:${2} -FcL | tr '\n' ' ') \
	  && (log_echo -n "IPv6 Port ${2} is in use " && lsof_parse "${lsof_value}" "${1}") \
	  || (log_echo "Port ${2} is not in use on IPv6.")
	fi

	lsof_value=$(lsof -i 4:${2} -FcL | tr '\n' ' ') \
	  && (log_echo -n "IPv4 Port ${2} is in use " && lsof_parse "${lsof_value}" "${1}") \
	  || (log_echo "Port ${2} is not in use on IPv4.")

  echo "${1}file"

	echo ":::"
}

testResolver() {
	header_write "Resolver Functions Check"

	# Find a blocked url that has not been whitelisted.
	TESTURL="doubleclick.com"
	if [ -s "${WHITELISTMATCHES}" ]; then
		while read -r line; do
			CUTURL=${line#*" "}
			if [ "${CUTURL}" != "Pi-Hole.IsWorking.OK" ]; then
				while read -r line2; do
					CUTURL2=${line2#*" "}
					if [ "${CUTURL}" != "${CUTURL2}" ]; then
						TESTURL="${CUTURL}"
						break 2
					fi
				done < "${WHITELISTMATCHES}"
			fi
		done < "${GRAVITYFILE}"
	fi

	log_write "Resolution of ${TESTURL} from Pi-hole:"
	LOCALDIG=$(dig "${TESTURL}" @127.0.0.1)
	if [[ $? = 0 ]]; then
		log_write "${LOCALDIG}"
	else
		log_write "Failed to resolve ${TESTURL} on Pi-hole"
	fi
	log_write ""


	log_write "Resolution of ${TESTURL} from 8.8.8.8:"
	REMOTEDIG=$(dig "${TESTURL}" @8.8.8.8)
	if [[ $? = 0 ]]; then
		log_write "${REMOTEDIG}"
	else
		log_write "Failed to resolve ${TESTURL} on 8.8.8.8"
	fi
	log_write ""

	log_write "Pi-hole dnsmasq specific records lookups"
	log_write "Cache Size:"
	dig +short chaos txt cachesize.bind >> ${DEBUG_LOG}
	log_write "Misses count:"
	dig +short chaos txt misses.bind >> ${DEBUG_LOG}
	log_write "Hits count:"
	dig +short chaos txt hits.bind >> ${DEBUG_LOG}
	log_write "Upstream Servers:"
	dig +short chaos txt servers.bind >> ${DEBUG_LOG}
	log_write ""
}

checkProcesses() {
	header_write "Processes Check"

	echo ":::     Logging status of lighttpd and dnsmasq..."
	PROCESSES=( lighttpd dnsmasq )
	for i in "${PROCESSES[@]}"; do
		log_write ""
		log_write -n "${i}"
		log_write " processes status:"
		systemctl -l status "${i}" >> "${DEBUG_LOG}"
	done
	log_write ""
}

debugLighttpd() {
  echo ":::     Checking for necessary lighttpd files."
  files_check "${LIGHTTPDFILE}"
  files_check "${LIGHTTPDERRFILE}"
  echo ":::"
}

### END FUNCTIONS ###

# Gather version of required packages / repositories
version_check || echo "REQUIRED FILES MISSING"

source_file "/etc/pihole/setupVars.conf"
distro_check
ip_check
#hostnameCheck


daemon_check lighttpd http
daemon_check dnsmasq domain
checkProcesses
testResolver
debugLighttpd

echo "::: Writing dnsmasq.conf to debug log..."
header_write "Dnsmasq configuration"
if [ -e "${DNSMASQFILE}" ]; then
	while read -r line; do
		if [ ! -z "${line}" ]; then
			[[ "${line}" =~ ^#.*$ ]] && continue
			log_write "${line}"
		fi
	done < "${DNSMASQFILE}"
	log_write ""
else
	log_write "No dnsmasq.conf file found!"
	printf ":::\tNo dnsmasq.conf file found!\n"
fi

echo "::: Writing 01-pihole.conf to debug log..."
header_write "01-pihole.conf"

if [ -e "${PIHOLECONFFILE}" ]; then
	while read -r line; do
		if [ ! -z "${line}" ]; then
			[[ "${line}" =~ ^#.*$ ]] && continue
			log_write "${line}"
		fi
	done < "${PIHOLECONFFILE}"
	log_write
else
	log_write "No 01-pihole.conf file found!"
	printf ":::\tNo 01-pihole.conf file found\n"
fi

echo "::: Writing size of gravity.list to debug log..."
header_write "gravity.list"

if [ -e "${GRAVITYFILE}" ]; then
	wc -l "${GRAVITYFILE}" >> ${DEBUG_LOG}
	log_write ""
else
	log_write "No gravity.list file found!"
	printf ":::\tNo gravity.list file found\n"
fi


### Pi-hole application specific logging ###
echo "::: Writing whitelist to debug log..."
header_write "Whitelist"
if [ -e "${WHITELISTFILE}" ]; then
	cat "${WHITELISTFILE}" >> ${DEBUG_LOG}
	log_write
else
	log_write "No whitelist.txt file found!"
	printf ":::\tNo whitelist.txt file found!\n"
fi

echo "::: Writing blacklist to debug log..."
header_write "Blacklist"
if [ -e "${BLACKLISTFILE}" ]; then
	cat "${BLACKLISTFILE}" >> ${DEBUG_LOG}
	log_write
else
	log_write "No blacklist.txt file found!"
	printf ":::\tNo blacklist.txt file found!\n"
fi

echo "::: Writing adlists.list to debug log..."
header_write "adlists.list"
if [ -e "${ADLISTSFILE}" ]; then
	while read -r line; do
		if [ ! -z "${line}" ]; then
			[[ "${line}" =~ ^#.*$ ]] && continue
			log_write "${line}"
		fi
	done < "${ADLISTSFILE}"
	log_write
else
	log_write "No adlists.list file found... using adlists.default!"
	printf ":::\tNo adlists.list file found... using adlists.default!\n"
fi
echo

# Continuously append the pihole.log file to the pihole_debug.log file
dumpPiHoleLog() {
	trap '{ echo -e "\n::: Finishing debug write from interrupt... Quitting!" ; exit 1; }' INT
	echo -e "::: Writing current Pi-hole traffic to debug log...\n:::\tTry loading any/all sites that you are having trouble with now... \n:::\t(Press ctrl+C to finish)"
	header_write "pihole.log"
	if [ -e "${PIHOLELOG}" ]; then
		while true; do
			tail -f "${PIHOLELOG}" >> ${DEBUG_LOG}
			log_write ""
		done
	else
		log_write "No pihole.log file found!"
		printf ":::\tNo pihole.log file found!\n"
	fi
}

# Anything to be done after capturing of pihole.log terminates
finalWork() {
  local tricorder
	echo "::: Finshed debugging!"
	echo "::: The debug log can be uploaded to tricorder.pi-hole.net for sharing with developers only."
	read -r -p "::: Would you like to upload the log? [y/N] " response
	case ${response} in
		[yY][eE][sS]|[yY])
			tricorder=$(cat /var/log/pihole_debug.log | nc tricorder.pi-hole.net 9999)
			;;
		*)
			echo "::: Log will NOT be uploaded to tricorder."
			;;
	esac

	# Check if tricorder.pi-hole.net is reachable and provide token.
	if [ -n "${tricorder}" ]; then
		echo "::: Your debug token is : ${tricorder}"
	fi
		echo "::: Debug log can be found at : /var/log/pihole_debug.log"
}

trap finalWork EXIT

### Method calls for additional logging ###
dumpPiHoleLog
