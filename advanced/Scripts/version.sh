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
COREGITDIR="/etc/.pihole/"
WEBGITDIR="/var/www/html/admin/"

getLocalVersion() {
  # FTL requires a different method
  if [ "$1" == "FTL" ]; then
    pihole-FTL version
    return 0
  fi

  # Get the tagged version of the local repository
  local directory="${1}"
  local version

  cd "${directory}" || { echo "${DEFAULT}"; return 1; }
  version=$(git describe --tags --always || echo "$DEFAULT")
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
  # FTL hash is not applicable
  if [ "$1" == "FTL" ]; then
    echo "N/A"
    return 0
  fi
  
  # Get the short hash of the local repository
  local directory="${1}"
  local hash

  cd "${directory}" || { echo "${DEFAULT}"; return 1; }
  hash=$(git rev-parse --short HEAD || echo "$DEFAULT")
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

  version=$(curl --silent --fail "https://api.github.com/repos/pi-hole/${daemon}/releases/latest" | \
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

versionOutput() {
  [ "$1" == "pi-hole" ] && GITDIR=$COREGITDIR
  [ "$1" == "AdminLTE" ] && GITDIR=$WEBGITDIR
  [ "$1" == "FTL" ] && GITDIR="FTL"
  
  [ "$2" == "-c" ] || [ "$2" == "--current" ] || [ -z "$2" ] && current=$(getLocalVersion $GITDIR)
  [ "$2" == "-l" ] || [ "$2" == "--latest" ] || [ -z "$2" ] && latest=$(getRemoteVersion "$1")
  [ "$2" == "-h" ] || [ "$2" == "--hash" ] && hash=$(getLocalHash "$GITDIR")

  if [ -n "$current" ] && [ -n "$latest" ]; then
    output="${1^} version is $current (Latest: $latest)"
  elif [ -n "$current" ] && [ -z "$latest" ]; then
    output="Current ${1^} version is $current"
  elif [ -z "$current" ] && [ -n "$latest" ]; then
    output="Latest ${1^} version is $latest"
  elif [ "$hash" == "N/A" ]; then
    output=""
  elif [ -n "$hash" ]; then
    output="Current ${1^} hash is $hash"
  else
	  errorOutput
  fi

  [ -n "$output" ] && echo "  $output"
}

errorOutput() {
  echo "  Invalid Option! Try 'pihole -v --help' for more information."
  exit 1
}
  
defaultOutput() {
  versionOutput "pi-hole" "$@"
  versionOutput "AdminLTE" "$@"
  versionOutput "FTL" "$@"
}

helpFunc() {
  echo "Usage: pihole -v [REPO | OPTION] [OPTION]
Show Pi-hole, Web Admin & FTL versions

Repositories:
  -p, --pihole         Only retrieve info regarding Pi-hole repository
  -a, --admin          Only retrieve info regarding AdminLTE repository
  -f, --ftl            Only retrieve info regarding FTL repository
  
Options:
  -c, --current        Return the current version
  -l, --latest         Return the latest version
  -h, --hash           Return the Github hash from your local repositories
  --help               Show this help dialog
"
	exit 0
}

case "${1}" in
  "-p" | "--pihole"    ) shift; versionOutput "pi-hole" "$@";;
  "-a" | "--admin"     ) shift; versionOutput "AdminLTE" "$@";;
  "-f" | "--ftl"       ) shift; versionOutput "FTL" "$@";;
  "--help"             ) helpFunc;;
  *                    ) defaultOutput "$@";;
esac
