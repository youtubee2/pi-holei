#!/bin/bash
# Address to send ads to (the RPi)
piholeIP="192.168.1.101"
# Config file to hold URL rules
eventHorizion="/etc/dnsmasq.d/adList.conf"

# Download the original URL to a text file for easier parsing
curl -o /tmp/yoyo.txt -s http://pgl.yoyo.org/adservers/serverlist.php?hostformat=unixhosts&mimetype=plaintext
cat /tmp/yoyo.txt | grep -v "<" | sed '/^$/d' | sed 's/\ /\\ /g' | sort > /tmp/matter.txt

# Download and append other ad URLs from different sources
curl -s http://winhelp2002.mvps.org/hosts.txt | grep -v "#" | grep -v "127.0.0.1" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' | sort >> /tmp/matter.txt
curl -s https://adaway.org/hosts.txt | grep -v "#" | grep -v "::1" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' | sort >> /tmp/matter.txt
curl -s http://hosts-file.net/.%5Cad_servers.txt | grep -v "#" | grep -v "::1" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' | sort >> /tmp/matter.txt
curl -s http://www.malwaredomainlist.com/hostslist/hosts.txt | grep -v "#" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' | sort >> /tmp/matter.txt
curl -s http://adblock.gjtech.net/?format=unix-hosts | grep -v "#" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' | sort >> /tmp/matter.txt

# Sort the aggregated results and remove any duplicates
cat /tmp/matter.txt | sort | uniq | sed '/^$/d' > /tmp/andLight.txt

# Read the file and prepend "address=/" and append the IP of the Raspberry Pi
while read fermion
do
	 boson=$(echo "$fermion" | tr -d '\r')
	 echo "address=/$boson/$piholeIP" >> $eventHorizion
done </tmp/andLight.txt

# Restart DNS
service dnsmasq restart
