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
if [[ $EUID -eq 0 ]];then
	echo "::: You are root."
else
	echo "::: sudo will be used."
  # Check if it is actually installed
  # If it isn't, exit because the install cannot complete
  if [[ $(dpkg-query -s sudo) ]];then
		export SUDO="sudo"
  else
		echo "::: Please install sudo or run this script as root."
    exit 1
  fi
fi

piholeIPfile=/tmp/piholeIP
piholeIPv6file=/etc/pihole/.useIPv6

if [[ -f $piholeIPfile ]];then
    # If the file exists, it means it was exported from the installation script and we should use that value instead of detecting it in this script
    piholeIP=$(cat $piholeIPfile)
    rm $piholeIPfile
else
    # Otherwise, the IP address can be taken directly from the machine, which will happen when the script is run by the user and not the installation script
    IPv4dev=$(ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++)if($i~/dev/)print $(i+1)}')
    piholeIPCIDR=$(ip -o -f inet addr show dev $IPv4dev | awk '{print $4}' | awk 'END {print}')
    piholeIP=${piholeIPCIDR%/*}
fi

if [[ -f $piholeIPv6file ]];then
    # If the file exists, then the user previously chose to use IPv6 in the automated installer
    piholeIPv6=$(ip -6 route get 2001:4860:4860::8888 | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "src") print $(i+1) }')
fi

# Ad-list sources--one per line in single quotes
# The mahakala source is commented out due to many users having issues with it blocking legitimate domains.
# Uncomment at your own risk
sources=('https://adaway.org/hosts.txt'
'http://adblock.gjtech.net/?format=unix-hosts'
#'http://adblock.mahakala.is/'
'http://hosts-file.net/ad_servers.txt'
'http://www.malwaredomainlist.com/hostslist/hosts.txt'
'http://pgl.yoyo.org/adservers/serverlist.php?'
'http://someonewhocares.org/hosts/hosts'
'http://winhelp2002.mvps.org/hosts.txt')

# Variables for various stages of downloading and formatting the list
basename=pihole
piholeDir=/etc/$basename
adList=$piholeDir/gravity.list
blacklist=$piholeDir/blacklist.txt
whitelist=$piholeDir/whitelist.txt
latentWhitelist=$piholeDir/latentWhitelist.txt
justDomainsExtension=domains
matterandlight=$basename.0.matterandlight.txt
supernova=$basename.1.supernova.txt
eventHorizon=$basename.2.eventHorizon.txt
accretionDisc=$basename.3.accretionDisc.txt
eyeOfTheNeedle=$basename.4.wormhole.txt

# After setting defaults, check if there's local overrides
if [[ -r $piholeDir/pihole.conf ]];then
    echo "::: Local calibration requested..."
        . $piholeDir/pihole.conf
fi


spinner(){
        local pid=$1
        local delay=0.001
        local spinstr='/-\|'

        spin='-\|/'
        i=0
        while kill -0 $pid 2>/dev/null
        do
                i=$(( (i+1) %4 ))
                printf "\b${spin:$i:1}"
                sleep .1
        done
        printf "\b"
}
###########################
# collapse - begin formation of pihole
function gravity_collapse() {
	echo -n "::: Neutrino emissions detected..."

	# Create the pihole resource directory if it doesn't exist.  Future files will be stored here
	if [[ -d $piholeDir ]];then
        # Temporary hack to allow non-root access to pihole directory
        # Will update later, needed for existing installs, new installs should
        # create this directory as non-root
        $SUDO chmod 777 $piholeDir
        find "$piholeDir" -type f -exec $SUDO chmod 666 {} \; & spinner $!
        echo "."
	else
        echo -n "::: Creating pihole directory..."
        mkdir $piholeDir & spinner $!
        echo " done!"
	fi
}

# patternCheck - check to see if curl downloaded any new files.
function gravity_patternCheck() {
	patternBuffer=$1
	# check if the patternbuffer is a non-zero length file
	if [[ -s "$patternBuffer" ]];then
		# Some of the blocklists are copyright, they need to be downloaded
		# and stored as is. They can be processed for content after they
		# have been saved.
		cp $patternBuffer $saveLocation
		echo " List updated, transport successful!"
	else
		# curl didn't download any host files, probably because of the date check
		echo " No changes detected, transport skipped!"
	fi
}

# transport - curl the specified url with any needed command extentions
function gravity_transport() {
	url=$1
	cmd_ext=$2
	agent=$3

	# tmp file, so we don't have to store the (long!) lists in RAM
	patternBuffer=$(mktemp)
	heisenbergCompensator=""
	if [[ -r $saveLocation ]]; then
		# if domain has been saved, add file for date check to only download newer
		heisenbergCompensator="-z $saveLocation"
	fi

	# Silently curl url
	curl -s $cmd_ext $heisenbergCompensator -A "$agent" $url > $patternBuffer 
	# Check for list updates
	gravity_patternCheck $patternBuffer 

	# Cleanup
	rm -f $patternBuffer
}

# spinup - main gravity function
function gravity_spinup() {
  echo "::: "
	# Loop through domain list.  Download each one and remove commented lines (lines beginning with '# 'or '/') and	 		# blank lines
	for ((i = 0; i < "${#sources[@]}"; i++))
	do
        url=${sources[$i]}
        # Get just the domain from the URL
        domain=$(echo "$url" | cut -d'/' -f3)

        # Save the file as list.#.domain
        saveLocation=$piholeDir/list.$i.$domain.$justDomainsExtension
        activeDomains[$i]=$saveLocation

        agent="Mozilla/10.0"

        echo -n "::: Getting $domain list..."

        # Use a case statement to download lists that need special cURL commands
        # to complete properly and reset the user agent when required
        case "$domain" in
                "adblock.mahakala.is")
                        agent='Mozilla/5.0 (X11; Linux x86_64; rv:30.0) Gecko/20100101 Firefox/30.0'
                        cmd_ext="-e http://forum.xda-developers.com/"
                        ;;

                "pgl.yoyo.org")
                        cmd_ext="-d mimetype=plaintext -d hostformat=hosts"
                        ;;

                # Default is a simple request
                *) cmd_ext=""
        esac
        gravity_transport $url $cmd_ext $agent
	done
}

# Schwarzchild - aggregate domains to one list and add blacklisted domains
function gravity_Schwarzchild() {
  echo "::: "
	# Find all active domains and compile them into one file and remove CRs
	echo -n "::: Aggregating list of domains..."
	truncate -s 0 $piholeDir/$matterandlight & spinner $! 
	for i in "${activeDomains[@]}"
	do
   		cat $i |tr -d '\r' >> $piholeDir/$matterandlight
	done
	echo " done!"
	
}


function gravity_Blacklist(){
	# Append blacklist entries if they exist
	echo -n "::: Running blacklist script to update HOSTS file...."
	blacklist.sh -f -nr -q > /dev/null & spinner $!
	
	numBlacklisted=$(wc -l < "/etc/pihole/blacklist.txt")
	plural=; [[ "$numBlacklisted" != "1" ]] && plural=s
  echo " $numBlacklisted domain${plural} blacklisted!"
  
	
}


function gravity_Whitelist() {
  echo ":::"
	# Prevent our sources from being pulled into the hole
	plural=; [[ "${sources[@]}" != "1" ]] && plural=s
	echo -n "::: Adding ${#sources[@]} ad list source${plural} to the whitelist..."
	
	urls=()
	for url in ${sources[@]}
	do
        tmp=$(echo "$url" | awk -F '/' '{print $3}')
        urls=("${urls[@]}" $tmp)
	done & spinner $!
	echo " done!"
	
	echo -n "::: Running whitelist script to update HOSTS file...."
	whitelist.sh -f -nr -q ${urls[@]} > /dev/null & spinner $!
		
	numWhitelisted=$(wc -l < "/etc/pihole/whitelist.txt")
	plural=; [[ "$numWhitelisted" != "1" ]] && plural=s
  echo " $numWhitelisted domain${plural} whitelisted!"
  
  
		
}

function gravity_unique() {
	# Sort and remove duplicates
	echo -n "::: Removing duplicate domains...."
	sort -u  $piholeDir/$supernova > $piholeDir/$eventHorizon  & spinner $!
	echo " done!"
	numberOf=$(wc -l < $piholeDir/$eventHorizon)
	echo "::: $numberOf unique domains trapped in the event horizon."
}

function gravity_hostFormat() {
  # Format domain list as "192.168.x.x domain.com"
	echo "::: Formatting domains into a HOSTS file..."
  # If there is a value in the $piholeIPv6, then IPv6 will be used, so the awk command modified to create a line for both protocols
  if [[ -n $piholeIPv6 ]];then
    cat $piholeDir/$eventHorizon | awk -v ipv4addr="$piholeIP" -v ipv6addr="$piholeIPv6" '{sub(/\r$/,""); print ipv4addr" "$0"\n"ipv6addr" "$0}' > $piholeDir/$accretionDisc
  else
    # Otherwise, just create gravity.list as normal using IPv4
    cat $piholeDir/$eventHorizon | awk -v ipv4addr="$piholeIP" '{sub(/\r$/,""); print ipv4addr" "$0}' > $piholeDir/$accretionDisc
  fi
	# Copy the file over as /etc/pihole/gravity.list so dnsmasq can use it
	cp $piholeDir/$accretionDisc $adList
}

# blackbody - remove any remnant files from script processes
function gravity_blackbody() {
	# Loop through list files
	for file in $piholeDir/*.$justDomainsExtension
	do
		# If list is in active array then leave it (noop) else rm the list
		if [[ " ${activeDomains[@]} " =~ " ${file} " ]]; then
			:
		else
			rm -f $file
		fi
	done
}

function gravity_advanced() {


	# Remove comments and print only the domain name
	# Most of the lists downloaded are already in hosts file format but the spacing/formating is not contigious
	# This helps with that and makes it easier to read
	# It also helps with debugging so each stage of the script can be researched more in depth
	echo -n "::: Formatting list of domains to remove comments...."
	awk '($1 !~ /^#/) { if (NF>1) {print $2} else {print $1}}' $piholeDir/$matterandlight | sed -nr -e 's/\.{2,}/./g' -e '/\./p' >  $piholeDir/$supernova & spinner $!
  echo " done!"
  
	numberOf=$(wc -l < $piholeDir/$supernova)
	echo "::: $numberOf domains being pulled in by gravity..."
    
	gravity_unique
  
}

function gravity_reload() {
	# Reload hosts file
	echo ":::"
	echo -n "::: Refresh lists in dnsmasq..."
	dnsmasqPid=$(pidof dnsmasq)

	if [[ $dnsmasqPid ]]; then
		# service already running - reload config
		$SUDO kill -HUP $dnsmasqPid & spinner $!
	else
		# service not running, start it up
		$SUDO service dnsmasq start & spinner $!
	fi
	echo " done!"
}


gravity_collapse
gravity_spinup
gravity_Schwarzchild
gravity_advanced
gravity_hostFormat
gravity_blackbody
gravity_Whitelist
gravity_Blacklist
gravity_reload
