#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# shows version numbers
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Variables
DEFAULT="-1"
PHGITDIR="/etc/.pihole/"
WEBGITDIR="/var/www/html/admin/"

getLocalVersion() {
  # Get the tagged version of the local repository
  local directory="${1}"
  local version

  cd "${directory}" || { echo "${DEFAULT}"; return 1; }
  version=$(git describe --tags --always || \
            echo "${DEFAULT}")
  if [[ "${version}" =~ ^v ]]; then
    echo "${version}"
  elif [[ "${version}" == "${DEFAULT}" ]]; then
    echo "ERROR"
    return 1
  else
    echo "Untagged"
  fi
  return 0
}

getLocalHash() {
  # Get the short hash of the local repository
  local directory="${1}"
  local hash

  cd "${directory}" || { echo "${DEFAULT}"; return 1; }
  hash=$(git rev-parse --short HEAD || \
         echo "${DEFAULT}")
  if [[ "${hash}" == "${DEFAULT}" ]]; then
    echo "ERROR"
    return 1
  else
    echo "${hash}"
  fi
  return 0
}

getRemoteVersion(){
  # Get the version from the remote origin
  local daemon="${1}"
  local version

  version=$(curl --silent --fail https://api.github.com/repos/pi-hole/${daemon}/releases/latest | \
            awk -F: '$1 ~/tag_name/ { print $2 }' | \
            tr -cd '[[:alnum:]]._-')
  if [[ "${version}" =~ ^v ]]; then
    echo "${version}"
  else
    echo "ERROR"
    return 1
  fi
  return 0
}

#PHHASHLATEST=$(curl -s https://api.github.com/repos/pi-hole/pi-hole/commits/master | \
#                   grep sha | \
#                   head -n1 | \
#                   awk -F ' ' '{ print $2 }' | \
#                   tr -cd '[[:alnum:]]._-')

#WEBHASHLATEST=$(curl -s https://api.github.com/repos/pi-hole/AdminLTE/commits/master | \
#                   grep sha | \
#                   head -n1 | \
#                   awk -F ' ' '{ print $2 }' | \
#                   tr -cd '[[:alnum:]]._-')


normalOutput() {
	echo "::: Pi-hole version is $(getLocalVersion "${PHGITDIR}") (Latest version is $(getRemoteVersion pi-hole))"
	if [ -d "${WEBGITDIR}" ]; then
		echo "::: Web-Admin version is $(getLocalVersion "${WEBGITDIR}") (Latest version is $(getRemoteVersion AdminLTE))"
	fi
}

webOutput() {
  if [ -d "${WEBGITDIR}" ]; then
    case "${1}" in
      "-l" | "--latest"    ) echo $(getRemoteVersion AdminLTE);;
      "-c" | "--current"   ) echo $(getLocalVersion "${WEBGITDIR}");;
      "-h" | "--hash"      ) echo $(getLocalHash "${WEBGITDIR}");;
      *                    ) echo "::: Invalid Option!"; exit 1;
    esac
  else
    echo "::: Web interface not installed!"; exit 1;
  fi
}

coreOutput() {
  case "${1}" in
    "-l" | "--latest"    ) echo $(getRemoteVersion pi-hole);;
    "-c" | "--current"   ) echo $(getLocalVersion "${PHGITDIR}");;
    "-h" | "--hash"      ) echo $(getLocalHash "${PHGITDIR}");;
    *                    ) echo "::: Invalid Option!"; exit 1;
  esac
}

helpFunc() {
	cat << EOM
:::
::: Show Pi-hole/Web Admin versions
:::
::: Usage: pihole -v [ -a | -p ] [ -l | -c ]
:::
::: Options:
:::  -a, --admin          Show both current and latest versions of web admin
:::  -p, --pihole         Show both current and latest versions of Pi-hole core files
:::  -l, --latest         (Only after -a | -p) Return only latest version
:::  -c, --current        (Only after -a | -p) Return only current version
:::  -h, --help           Show this help dialog
:::
EOM
	exit 0
}

if [[ $# = 0 ]]; then
	normalOutput
fi

case "${1}" in
  "-a" | "--admin"     ) shift; webOutput "$@";;
  "-p" | "--pihole"    ) shift; coreOutput "$@" ;;
  "-h" | "--help"      ) helpFunc;;
esac
