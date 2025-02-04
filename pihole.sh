#!/bin/bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Controller for all pihole scripts and functions.
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# Must be root to use this tool
if [[ $EUID -eq 0 ]];then
	echo "::: You are root."
else
	echo "::: Sudo will be used for this tool."
  # Check if it is actually installed
  # If it isn't, exit because the unnstall cannot complete
  if [[ $(dpkg-query -s sudo) ]];then
		export SUDO="sudo"
  else
    echo "::: Please install sudo or run this as root."
    exit 1
  fi
fi

function whitelistFunc {
	shift
	$SUDO /opt/pihole/whitelist.sh "$@"
	exit 1
}

function blacklistFunc {
	shift
	$SUDO /opt/pihole/blacklist.sh "$@"
	exit 1
}

function debugFunc {
	$SUDO /opt/pihole/piholeDebug.sh
	exit 1
}

function flushFunc {
	$SUDO /opt/pihole/piholeLogFlush.sh
	exit 1
}

function updateDashboardFunc {
	$SUDO /opt/pihole/updateDashboard.sh
	exit 1
}

function setupLCDFunction {
	$SUDO /opt/pihole/setupLCD.sh
	exit 1
}

function chronometerFunc {
	$SUDO /opt/pihole/chronometer.sh
	exit 1
}

function helpFunc {
    echo "::: Control all PiHole specific functions!"
    echo ":::"
    echo "::: Usage: pihole.sh [options]"
    printf ":::\tAdd -h after -w, -b, or -c  for more information on usage\n"
    echo ":::"
    echo "::: Options:"
    printf ":::  -w, --whitelist\t\tWhitelist domains\n"
    printf ":::  -b, --blacklist\t\tBlacklist domains\n"
    printf ":::  -d, --debug\t\tStart a debugging session if having trouble\n"
    printf ":::  -f, --flush\t\tFlush the pihole.log file\n"
    printf ":::  -u, --updateDashboard\t\tUpdate the web dashboard manually\n"
   	printf ":::  -s, --setupLCD\t\tAutomatically configures the Pi to use the 2.8 LCD screen to display stats on it\n"
	printf ":::  -c, --chronometer\t\tCalculates stats and displays to an LCD\n"
	printf ":::  -h, --help\t\tShow this help dialog\n"
    exit 1
}

if [[ $# = 0 ]]; then
	helpFunc
fi

# Handle redirecting to specific functions based on arguments
case "$1" in
"-w" | "--whitelist"		) whitelistFunc "$@";;
"-b" | "--blacklist"		) blacklistFunc "$@";;
"-d" | "--debug"			) debugFunc;;
"-f" | "--flush"			) flushFunc;;
"-u" | "--updateDashboard"	) updateDashboardFunc;;
"-s" | "--setupLCD"			) setupLCDFunction;;
"-c" | "--chronometer"		) chronometerFunc;;
"-h" | "--help"				) helpFunc;;
*                    		) helpFunc;;
esac
