#!/bin/bash
# Address to send ads to (the RPi)
piholeIP="127.0.0.1"
# Config file to hold URL rules
eventHorizion="/etc/dnsmasq.d/adList.conf"

# Download the original URL to a text file for easier parsing
echo "Getting yoyo ad list..."
curl -o /tmp/yoyo.txt -s http://pgl.yoyo.org/adservers/serverlist.php?hostformat=unixhosts&mimetype=plaintext
sleep 10
if [ -f /tmp/yoyo.txt ];then
	cat /tmp/yoyo.txt | grep -v "<" | sed '/^$/d' | sed 's/\ /\\ /g' | sort > /tmp/matter.txt
else
	echo "Unable to get yoyo ad list"
fi

# Download and append other ad URLs from different sources
echo "Getting winhelp2002 ad list..."
curl -s http://winhelp2002.mvps.org/hosts.txt | grep -v "#" | grep -v "127.0.0.1" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' | sort >> /tmp/matter.txt
echo "Getting adaway ad list..."
curl -s https://adaway.org/hosts.txt | grep -v "#" | grep -v "::1" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' | sort >> /tmp/matter.txt
echo "Getting hosts-file ad list..."
curl -s http://hosts-file.net/.%5Cad_servers.txt | grep -v "#" | grep -v "::1" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' | sort >> /tmp/matter.txt
echo "Getting malwaredomainlist ad list..."
curl -s http://www.malwaredomainlist.com/hostslist/hosts.txt | grep -v "#" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' | sort >> /tmp/matter.txt
echo "Getting adblock.gjtech ad list..."
curl -s http://adblock.gjtech.net/?format=unix-hosts | grep -v "#" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' | sort >> /tmp/matter.txt
echo "Getting someone who cares ad list..."
curl -s http://someonewhocares.org/hosts/hosts | grep -v "#" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' >> /tmp/matter.txt

# Sort the aggregated results and remove any duplicates
#<<<<<<< Updated upstream
echo "removing duplicates and formatting to address=/<ad domain>/"$piholeIP
cat /tmp/matter.txt | sort | uniq | sed '/^$/d' | awk -v "IP=$piholeIP" '{sub(/\r$/,""); print "address=/"$0"/"IP}' > /tmp/andLight.txt
mv /tmp/andLight.txt $eventHorizion
=======
echo "Sorting and removing duplicates..."
cat /tmp/matter.txt | sort | uniq | sed '/^$/d' > /tmp/andLight.txt

# Read the file, prepend "address=/", and append the IP of the Raspberry Pi
# This creates a correctly-formatted config file
while read fermion
do
	boson=$(echo "$fermion" | tr -d '\r')
	# WHITELSISTING
	case $boson in
		# Change these domains below to whitelist a site (will show ads)
		jacobsalmela.com) echo "--------WHITELISTED $boson";;
		lifehacker.com) echo "--------WHITELISTED $boson";;
		*) echo "address=/$boson/$piholeIP" >> $eventHorizion;
			echo "Added $boson...";;
	esac	
done </tmp/andLight.txt
>>>>>>> Stashed changes

# Restart DNS
service dnsmasq restart
