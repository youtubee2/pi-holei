#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Compiles a list of ad-serving domains by downloading them from multiple sources
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# Run this script as root or under sudo
echo ":::"

helpFunc()
{
	echo "::: Pull in domains from adlists"
	echo ":::"
	echo "::: Usage: pihole -g"
	echo ":::"
	echo "::: Options:"
	echo ":::  -f, --force				Force lists to be downloaded, even if they don't need updating."
	echo ":::  -h, --help				Show this help dialog"
	exit 1
}


adListFile=/etc/pihole/adlists.list
adListDefault=/etc/pihole/adlists.default
whitelistScript=/opt/pihole/whitelist.sh
blacklistScript=/opt/pihole/blacklist.sh

#Source the setupVars from install script for the IP
setupVars=/etc/pihole/setupVars.conf
if [[ -f ${setupVars} ]];then
    . /etc/pihole/setupVars.conf
else
    echo "::: WARNING: /etc/pihole/setupVars.conf missing. Possible installation failure."
    echo ":::          Please run 'pihole -r', and choose the 'reconfigure' option to reconfigure."
    exit 1
fi

#Remove the /* from the end of the IPv4addr.
IPv4_address=${IPv4_address%/*}

# Variables for various stages of downloading and formatting the list
basename=pihole
piholeDir=/etc/${basename}
adList=${piholeDir}/gravity.list
justDomainsExtension=domains
matterAndLight=${basename}.0.matterandlight.txt
supernova=${basename}.1.supernova.txt
eventHorizon=${basename}.2.eventHorizon.txt
accretionDisc=${basename}.3.accretionDisc.txt

# Warn users still using pihole.conf that it no longer has any effect (I imagine about 2 people use it)
if [[ -r ${piholeDir}/pihole.conf ]];then
    echo "::: pihole.conf file no longer supported. Over-rides in this file are ignored."
fi

###########################
# collapse - begin formation of pihole
gravity_collapse() {
	echo "::: Neutrino emissions detected..."
	echo ":::"
	#Decide if we're using a custom ad block list, or defaults.
	if [ -f ${adListFile} ]; then
		#custom file found, use this instead of default
		echo -n "::: Custom adList file detected. Reading..."
		sources=()
		while read -r line; do
			#Do not read commented out or blank lines
			if [[ ${line} = \#* ]] || [[ ! ${line} ]]; then
				echo "" > /dev/null
			else
				sources+=(${line})
			fi
		done < ${adListFile}
		echo " done!"
	else
		#no custom file found, use defaults!
		echo -n "::: No custom adlist file detected, reading from default file..."
		sources=()
		while read -r line; do
			#Do not read commented out or blank lines
			if [[ ${line} = \#* ]] || [[ ! ${line} ]]; then
				echo "" > /dev/null
			else
				sources+=(${line})
			fi
		done < ${adListDefault}
		echo " done!"
	fi

	# Create the pihole resource directory if it doesn't exist.  Future files will be stored here
	if [[ -d ${piholeDir} ]];then
        # Temporary hack to allow non-root access to pihole directory
        # Will update later, needed for existing installs, new installs should
        # create this directory as non-root
        chmod 777 ${piholeDir}
        echo ":::"
        echo "::: Existing pihole directory found"
	else
        echo "::: Creating pihole directory..."
        mkdir ${piholeDir}
        chmod 777 ${piholeDir}
	fi
}

# patternCheck - check to see if curl downloaded any new files.
gravity_patternCheck() {
	patternBuffer=$1
	# check if the patternbuffer is a non-zero length file
	if [[ -s "$patternBuffer" ]];then
		# Some of the blocklists are copyright, they need to be downloaded
		# and stored as is. They can be processed for content after they
		# have been saved.
		cp "$patternBuffer" "$saveLocation"
		echo " List updated, transport successful!"
	else
		# curl didn't download any host files, probably because of the date check
		echo " No changes detected, transport skipped!"
	fi
}

# transport - curl the specified url with any needed command extentions
gravity_transport() {
	url=$1
	cmd_ext=$2
	agent=$3

	# tmp file, so we don't have to store the (long!) lists in RAM
	patternBuffer=$(mktemp)
	heisenbergCompensator=""
	if [[ -r ${saveLocation} ]]; then
		# if domain has been saved, add file for date check to only download newer
		heisenbergCompensator="-z $saveLocation"
	fi

	# Silently curl url
	curl -s -L ${cmd_ext} ${heisenbergCompensator} -A "$agent" ${url} > ${patternBuffer}
	# Check for list updates
	gravity_patternCheck "$patternBuffer"
	# Cleanup
	rm -f "$patternBuffer"
}

# spinup - main gravity function
gravity_spinup() {
	echo ":::"
	# Loop through domain list.  Download each one and remove commented lines (lines beginning with '# 'or '/') and	 		# blank lines
	for ((i = 0; i < "${#sources[@]}"; i++))
	do
        url=${sources[$i]}
        # Get just the domain from the URL
        domain=$(echo "$url" | cut -d'/' -f3)

        # Save the file as list.#.domain
        saveLocation=${piholeDir}/list.${i}.${domain}.${justDomainsExtension}
        activeDomains[$i]=${saveLocation}

        agent="Mozilla/10.0"

        echo -n "::: Getting $domain list..."

        # Use a case statement to download lists that need special cURL commands
        # to complete properly and reset the user agent when required
        case "$domain" in
            "adblock.mahakala.is")
                agent='Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2228.0 Safari/537.36'
                cmd_ext="-e http://forum.xda-developers.com/"
            ;;

            "pgl.yoyo.org")
                cmd_ext="-d mimetype=plaintext -d hostformat=hosts"
            ;;

            # Default is a simple request
            *) cmd_ext=""
        esac
        gravity_transport "$url" "$cmd_ext" "$agent"
	done
}

# Schwarzchild - aggregate domains to one list and add blacklisted domains
gravity_Schwarzchild() {
	echo "::: "
	# Find all active domains and compile them into one file and remove CRs
	echo -n "::: Aggregating list of domains..."
	truncate -s 0 ${piholeDir}/${matterAndLight}
	for i in "${activeDomains[@]}"
	do
		cat "$i" | tr -d '\r' >> ${piholeDir}/${matterAndLight}
	done
	echo " done!"
}

gravity_Blacklist(){
	# Append blacklist entries if they exist
	echo -n "::: Running blacklist script to update HOSTS file...."
	${blacklistScript} -f -nr -q > /dev/null

	numBlacklisted=$(wc -l < "/etc/pihole/blacklist.txt")
	plural=; [[ "$numBlacklisted" != "1" ]] && plural=s
	echo " $numBlacklisted domain${plural} blacklisted!"
}

gravity_Whitelist() {
	echo ":::"
	# Prevent our sources from being pulled into the hole
	plural=; [[ "${sources[@]}" != "1" ]] && plural=s
	echo -n "::: Adding ${#sources[@]} adlist source${plural} to the whitelist..."

	urls=()
	for url in "${sources[@]}"
	do
        tmp=$(echo "$url" | awk -F '/' '{print $3}')
        urls=("${urls[@]}" ${tmp})
	done
	echo " done!"

	echo -n "::: Running whitelist script to update HOSTS file...."
	${whitelistScript} -f -nr -q "${urls[@]}" > /dev/null
	numWhitelisted=$(wc -l < "/etc/pihole/whitelist.txt")
	plural=; [[ "$numWhitelisted" != "1" ]] && plural=s
	echo " $numWhitelisted domain${plural} whitelisted!"
}

gravity_unique() {
	# Sort and remove duplicates
	echo -n "::: Removing duplicate domains...."
	sort -u  ${piholeDir}/${supernova} > ${piholeDir}/${eventHorizon}
	echo " done!"
	numberOf=$(wc -l < ${piholeDir}/${eventHorizon})
	echo "::: $numberOf unique domains trapped in the event horizon."
}

gravity_hostFormat() {
	# Format domain list as "192.168.x.x domain.com"
	echo "::: Formatting domains into a HOSTS file..."
	if [[ -f /etc/hostname ]]; then
		hostname=$(</etc/hostname)
	elif [ -x "$(command -v hostname)" ]; then
		hostname=$(hostname -f)
	else
		echo "::: Error: Unable to determine fully qualified domain name of host"
	fi

    # Check vars from setupVars.conf to see if we're using IPv4, IPv6, Or both.
    if [[ -n "${IPv4_address}" && -n "${IPv6_address}" ]];then

        # Both IPv4 and IPv6
        echo -e "$IPv4_address $hostname\n$IPv6_address $hostname\n$IPv4_address pi.hole\n$IPv6_address pi.hole" > ${piholeDir}/${accretionDisc}
        cat ${piholeDir}/${eventHorizon} | awk -v ipv4addr="$IPv4_address" -v ipv6addr="$IPv6_address" '{sub(/\r$/,""); print ipv4addr" "$0"\n"ipv6addr" "$0}' >> ${piholeDir}/${accretionDisc}

    elif [[ -n "${IPv4_address}" && -z "${IPv6_address}" ]];then

        # Only IPv4
        echo -e "$IPv4_address $hostname\n$IPv4_address pi.hole" > ${piholeDir}/${accretionDisc}
        cat ${piholeDir}/${eventHorizon} | awk -v ipv4addr="$IPv4_address" '{sub(/\r$/,""); print ipv4addr" "$0}' >> ${piholeDir}/${accretionDisc}

    elif [[ -z "${IPv4_address}" && -n "${IPv6_address}" ]];then

        # Only IPv6
        echo -e "$IPv6_address $hostname\n$IPv6_address pi.hole" > ${piholeDir}/${accretionDisc}
        cat ${piholeDir}/${eventHorizon} | awk -v ipv6addr="$IPv6_address" '{sub(/\r$/,""); print ipv6addr" "$0}' >> ${piholeDir}/${accretionDisc}

    elif [[ -z "${IPv4_address}" && -z "${IPv6_address}" ]];then
        echo "::: No IP Values found! Please run 'pihole -r' and choose reconfigure to restore values"
        exit 1
    fi

	# Copy the file over as /etc/pihole/gravity.list so dnsmasq can use it
	cp ${piholeDir}/${accretionDisc} ${adList}
}

# blackbody - remove any remnant files from script processes
gravity_blackbody() {
	# Loop through list files
	for file in ${piholeDir}/*.${justDomainsExtension}
	do
		# If list is in active array then leave it (noop) else rm the list
		if [[ " ${activeDomains[@]} " =~ ${file} ]]; then
			:
		else
			rm -f "$file"
		fi
	done
}

gravity_advanced() {
	# Remove comments and print only the domain name
	# Most of the lists downloaded are already in hosts file format but the spacing/formating is not contigious
	# This helps with that and makes it easier to read
	# It also helps with debugging so each stage of the script can be researched more in depth
	echo -n "::: Formatting list of domains to remove comments...."
	#awk '($1 !~ /^#/) { if (NF>1) {print $2} else {print $1}}' ${piholeDir}/${matterAndLight} | sed -nr -e 's/\.{2,}/./g' -e '/\./p' >  ${piholeDir}/${supernova}
	#Above line does not correctly grab domains where comment is on the same line (e.g 'addomain.com #comment')
	#Add additional awk command to read all lines up to a '#', and then continue as we were
	cat ${piholeDir}/${matterAndLight} | awk -F'#' '{print $1}' | awk '($1 !~ /^#/) { if (NF>1) {print $2} else {print $1}}' | sed -nr -e 's/\.{2,}/./g' -e '/\./p' >  ${piholeDir}/${supernova}
	echo " done!"

	numberOf=$(wc -l < ${piholeDir}/${supernova})
	echo "::: $numberOf domains being pulled in by gravity..."

	gravity_unique
}

gravity_reload() {
	#Clear no longer needed files...
	echo ":::"
	echo -n "::: Cleaning up un-needed files..."
	rm ${piholeDir}/pihole.*.txt
	echo " done!"

	# Reload hosts file
	echo ":::"
	echo -n "::: Refresh lists in dnsmasq..."
	
	#ensure /etc/dnsmasq.d/01-pihole.conf is pointing at the correct list!
	#First escape forward slashes in the path:
	adList=${adList//\//\\\/}
	#Now replace the line in dnsmasq file
	sed -i "s/^addn-hosts.*/addn-hosts=$adList/" /etc/dnsmasq.d/01-pihole.conf
	find "$piholeDir" -type f -exec chmod 666 {} \;

    dnsmasqPid=$(pidof dnsmasq)

	if [[ ${dnsmasqPid} ]]; then
	    # service already running - reload config
	    if [ -x "$(command -v systemctl)" ]; then
            systemctl restart dnsmasq
        else
            service dnsmasq restart
        fi
	else
	    # service not running, start it up
	    if [ -x "$(command -v systemctl)" ]; then
            systemctl start dnsmasq
        else
            service dnsmasq start
        fi
	fi
}


for var in "$@"
do
  case "$var" in
    "-f" | "--force"     ) forceGrav=true;;
    "-h" | "--help"      ) helpFunc;;
  esac
done

if [[ ${forceGrav} == true ]]; then
	echo -n "::: Deleting exising list cache..."
	rm /etc/pihole/list.*
	echo " done!"
fi

#Overwrite adlists.default from /etc/.pihole in case any changes have been made. Changes should be saved in /etc/adlists.list
cp /etc/.pihole/adlists.default /etc/pihole/adlists.default
gravity_collapse
gravity_spinup
gravity_Schwarzchild
gravity_advanced
gravity_hostFormat
gravity_blackbody
gravity_Whitelist
gravity_Blacklist
gravity_reload
