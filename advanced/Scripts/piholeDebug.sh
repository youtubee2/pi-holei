#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Generates pihole_debug.log to be used for troubleshooting.
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.


# causes a pipeline to produce a failure return code if any command errors.
# Normally, pipelines only return a failure if the last command errors.
# In combination with set -e, this will make your script exit if any command in a pipeline errors.
set -o pipefail

######## GLOBAL VARS ########
VARSFILE="/etc/pihole/setupVars.conf"
DEBUG_LOG="/var/log/pihole_debug.log"
DNSMASQFILE="/etc/dnsmasq.conf"
DNSMASQCONFDIR="/etc/dnsmasq.d/*"
LIGHTTPDFILE="/etc/lighttpd/lighttpd.conf"
LIGHTTPDERRFILE="/var/log/lighttpd/error.log"
GRAVITYFILE="/etc/pihole/gravity.list"
WHITELISTFILE="/etc/pihole/whitelist.txt"
BLACKLISTFILE="/etc/pihole/blacklist.txt"
ADLISTFILE="/etc/pihole/adlists.list"
PIHOLELOG="/var/log/pihole.log"
PIHOLEGITDIR="/etc/.pihole/"
ADMINGITDIR="/var/www/html/admin/"
WHITELISTMATCHES="/tmp/whitelistmatches.list"
readonly FTLLOG="/var/log/pihole-FTL.log"
coltable=/opt/pihole/COL_TABLE

if [[ -f ${coltable} ]]; then
  source ${coltable}
else
  COL_NC='\e[0m' # No Color
  COL_YELLOW='\e[1;33m'
  COL_LIGHT_PURPLE='\e[1;35m'
  COL_CYAN='\e[0;36m'
  TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
  CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
  INFO="[i]"
  DONE="${COL_LIGHT_GREEN} done!${COL_NC}"
  OVER="\r\033[K"
fi

echo_succes_or_fail() {
  # Set the first argument passed to tihs function as a named variable for better readability
  local message="${1}"
  # If the command was successful (a zero),
  if [ $? -eq 0 ]; then
    # show success
    echo -e "    ${TICK} ${message}"
  else
    # Otherwise, show a error
    echo -e "    ${CROSS} ${message}"
  fi
}

initiate_debug() {
  # Clear the screen so the debug log is readable
  clear
  echo -e "${COL_LIGHT_PURPLE}*** [ INITIALIZING ]${COL_NC}"
  # Timestamp the start of the log
  echo -e "    ${INFO} $(date "+%Y-%m-%d:%H:%M:%S") debug log has been initiated."
}

# This is a function for visually displaying the curent test that is being run.
# Accepts one variable: the name of what is being diagnosed
# Colors do not show in the dasboard, but the icons do: [i], [✓], and [✗]
echo_current_diagnostic() {
  # Colors are used for visually distinguishing each test in the output
  echo -e "\n${COL_LIGHT_PURPLE}*** [ DIAGNOSING ]:${COL_NC} ${1}"
}

file_exists() {
  # Set the first argument passed to tihs function as a named variable for better readability
  local file_to_test="${1}"
  # If the file is readable
  if [[ -r "${file_to_test}" ]]; then
    # Return success
    return 0
  else
    # Otherwise, return a failure
    return 1
  fi
}

if_directory_exists() {
  # Set the first argument passed to tihs function as a named variable for better readability
  local directory_to_test="${1}"
  # If the file is readable
  if [[ -d "${directory_to_test}" ]]; then
    # Return success
    return 0
  else
    # Otherwise, return a failure
    return 1
  fi
}

check_core_version() {
  echo_current_diagnostic "Pi-hole Versions"
  local error_msg="git status failed"
  if_directory_exists "${PIHOLEGITDIR}" && \
    cd "${PIHOLEGITDIR}" || \
    echo "pihole repo does not exist"
    if git status &> /dev/null; then
      PI_HOLE_VERSION=$(git describe --tags --abbrev=0);
      PI_HOLE_BRANCH=$(git rev-parse --abbrev-ref HEAD);
      PI_HOLE_COMMIT=$(git describe --long --dirty --tags --always)
      echo -e "    ${INFO} Core: ${PI_HOLE_VERSION}
        ${INFO} Branch: ${PI_HOLE_BRANCH}
        ${INFO} Commit: ${PI_HOLE_COMMIT}"
    else
      echo "${error_msg}"
      return 1
    fi
}

check_web_version() {
  local error_msg="git status failed"
  if_directory_exists "${ADMINGITDIR}" && \
    cd "${ADMINGITDIR}" || \
    echo "repo does not exist"
    if git status &> /dev/null; then
      WEB_VERSION=$(git describe --tags --abbrev=0);
      WEB_BRANCH=$(git rev-parse --abbrev-ref HEAD);
      WEB_COMMIT=$(git describe --long --dirty --tags --always)
      echo -e "    ${INFO} Web: ${WEB_VERSION}
        ${INFO} Branch: ${WEB_BRANCH}
        ${INFO} Commit: ${WEB_COMMIT}"
    else
      echo "${error_msg}"
      return 1
    fi
}

check_ftl_version() {
  FTL_VERSION=$(pihole-FTL version)
  echo -e "    ${INFO} FTL: ${FTL_VERSION}"
}

check_web_server_version() {
  WEB_SERVER="lighttpd"
  WEB_SERVER_VERSON="$(lighttpd -v |& head -n1 | cut -d '/' -f2 | cut -d ' ' -f1)"
  echo -e "    ${INFO} ${WEB_SERVER}"
  if [[ -z "${WEB_SERVER_VERSON}" ]]; then
    echo -e "       ${CROSS} ${WEB_SERVER} version could not be detected."
  else
    echo -e "       ${TICK} ${WEB_SERVER_VERSON}"
  fi
}

check_resolver_version() {
  RESOLVER="dnsmasq"
  RESOVLER_VERSON="$(dnsmasq -v |& head -n1 | awk '{print $3}')"
  echo -e "    ${INFO} ${RESOLVER}"
  if [[ -z "${RESOVLER_VERSON}" ]]; then
    echo -e "       ${CROSS} ${RESOLVER} version could not be detected."
  else
    echo -e "       ${TICK} ${RESOVLER_VERSON}"
  fi
}

check_php_version() {
  PHP_VERSION=$(php -v |& head -n1 | cut -d '-' -f1 | cut -d ' ' -f2)
  echo -e "    ${INFO} PHP"
  if [[ -z "${PHP_VERSION}" ]]; then
    echo -e "       ${CROSS} PHP version could not be detected."
  else
    echo -e "       ${TICK} ${PHP_VERSION}"
  fi

}

check_critical_dependencies() {
  echo_current_diagnostic "Versions of critical dependencies"
  check_web_server_version
  check_web_server_version
  check_php_version
}

get_distro_attributes() {
  # Put the current Internal Field Separator into another variable so it can be restored later
  OLD_IFS="$IFS"
  # Store the distro info in an array and make it global since the OS won't change,
  # but we'll keep it within the function for better unit testing
  IFS=$'\r\n' command eval 'distro_info=( $(cat /etc/*release) )'

  # Set a named variable for better readability
  local distro_attribute
  # For each line found in an /etc/*release file,
  for distro_attribute in "${distro_info[@]}"; do
    # display the information with the ${INFO} icon
    pretty_name_key=$(echo "${distro_attribute}" | grep "PRETTY_NAME" | cut -d '=' -f1)
    # we need just the OS PRETTY_NAME, so print it when we find it
    if [[ "${pretty_name_key}" == "PRETTY_NAME" ]]; then
      PRETTY_NAME=$(echo "${distro_attribute}" | grep "PRETTY_NAME" | cut -d '=' -f2- | tr -d '"')
      echo "    ${INFO} ${PRETTY_NAME}"
      # Otherwise, do nothing
    else
      :
    fi
  done
  # Set the IFS back to what it was
  IFS="$OLD_IFS"
}

diagnose_operating_system() {
  local faq_url="https://discourse.pi-hole.net/t/hardware-software-requirements/273"
  local error_msg="Distribution unknown -- most likely you are on an unsupported platform and may run into issues."
  # Display the current test that is running
  echo_current_diagnostic "Operating system"

  # If there is a /etc/*release file, it's probably a supported operating system, so we can
  file_exists /etc/*release && \
    # display the attributes to the user
    get_distro_attributes || \
    # If it doesn't exist, it's not a system we currently support and link to FAQ
    echo -e "    ${CROSS} ${COL_LIGHT_RED}${error_msg}${COL_NC}
         ${INFO} ${COL_LIGHT_RED}Please see${COL_NC}: ${COL_CYAN}${faq_url}${COL_NC}"
}

processor_check() {
  echo_current_diagnostic "Processor"
  PROCESSOR=$(uname -m)
  if [[ -z "${PROCESSOR}" ]]; then
    echo -e "    ${CROSS} Processor could not be identified."
  else
    echo -e "    ${INFO} ${PROCESSOR}"
  fi
}

detect_ip_addresses() {
  # First argument should be a 4 or a 6
  local protocol=${1}
  # Use ip to show the addresses for the chosen protocol
  # Store the values in an arry so they can be looped through
  # Get the lines that are in the file(s) and store them in an array for parsing later
  declare -a ip_addr_list=( $(ip -${protocol} addr show dev ${PIHOLE_INTERFACE} | awk -F ' ' '{ for(i=1;i<=NF;i++) if ($i ~ '/^inet/') print $(i+1) }') )

  # If there is something in the IP address list,
  if [[ -n ${ip_addr_list} ]]; then
    # Local iterator
    local i
    echo -e "    ${TICK} IPv${protocol} on ${PIHOLE_INTERFACE}"
    for i in "${!ip_addr_list[@]}"; do
      echo -e "       [$i] ${ip_addr_list[$i]}"
    done
  # Othwerwise explain that the protocol is not configured
  else
    echo -e "    ${CROSS} No IPv${protocol} found on ${PIHOLE_INTERFACE}"
    return 1
  fi
}


ping_gateway() {
  # First argument should be a 4 or a 6
  local protocol="${1}"
  # If the protocol is 6,
  if [[ ${protocol} == "6" ]]; then
    # use ping6
    local cmd="ping6"
    # and Google's public IPv6 address
    local public_address="2001:4860:4860::8888"
  # Otherwise,
  else
    # use ping
    local cmd="ping"
    # and Google's public IPv4 address
    local public_address="8.8.8.8"
  fi

  # Find the default gateway using IPv4 or IPv6
  local gateway
  gateway="$(ip -${protocol} route | grep default | cut -d ' ' -f 3)"

  # If the gateway variable has a value (meaning a gateway was found),
  if [[ -n "${gateway}" ]]; then
    # Let the user know we will ping the gateway for a response
    echo -e "          ${INFO} Trying three pings on IPv${protocol} gateway at ${gateway}..."
    # Try to quietly ping the gateway 3 times, with a timeout of 3 seconds, using numeric output only,
    # on the pihole interface, and tail the last three lines of the output
    # If pinging the gateway is not successful,
    if ! ping_cmd="$(${cmd} -q -c 3 -W 3 -n ${gateway} -I ${PIHOLE_INTERFACE} | tail -n 3)"; then
      # let the user know
      echo -e "          ${CROSS} Gateway did not respond."
      # and return an error code
      return 1
    # Otherwise,
    else
      # show a success
      echo -e "          ${TICK} Gateway responded."
      # and return a success code
      return 0
    fi
  fi
}

ping_internet() {
  local protocol="${1}"
  # If the protocol is 6,
  if [[ ${protocol} == "6" ]]; then
    # use ping6
    local cmd="ping6"
    # and Google's public IPv6 address
    local public_address="2001:4860:4860::8888"
  # Otherwise,
  else
    # use ping
    local cmd="ping"
    # and Google's public IPv4 address
    local public_address="8.8.8.8"
  fi
  echo -n "     ${INFO} Trying three pings on IPv${protocol} to reach the Internet..."
  if ! ping_inet="$(${cmd} -q -W 3 -c 3 -n ${public_address} -I ${PIHOLE_INTERFACE} | tail -n 3)"; then
    echo -e "          ${CROSS} Cannot reach the Internet"
    return 1
  else
    echo -e "          ${TICK} Query responded."
    return 0
  fi
}

check_required_ports() {
  echo -e "    ${INFO} Ports in use:"
  ports_in_use=()
  while IFS= read -r line; do
      ports_in_use+=( "$line" )
  done < <( lsof -i -P -n | awk -F' ' '/LISTEN/ {print $9, $1}' | sort | uniq | cut -d':' -f2 )

  for i in ${!ports_in_use[@]}; do
    local port_number="$(echo "${ports_in_use[$i]}" | awk '{print $1}')"
    local service_name=$(echo "${ports_in_use[$i]}" | awk '{print $2}')
    echo -e "       [${port_number}] is in use by ${service_name}"
  done
}

check_networking() {
  echo_current_diagnostic "Networking"
  detect_ip_addresses "4"
  ping_gateway "4"
  detect_ip_addresses "6"
  ping_gateway "6"
  check_required_ports
}

check_x_headers() {
  echo_current_diagnostic "Dashboard and block page"
  local block_page=$(curl -Is localhost | awk '/X-Pi-hole/' | tr -d '\r')
  local dashboard=$(curl -Is localhost/admin/ | awk '/X-Pi-hole/' | tr -d '\r')
  local block_page_working="X-Pi-hole: A black hole for Internet advertisements."
  local dashboard_working="X-Pi-hole: The Pi-hole Web interface is working!"
  if [[ $block_page == $block_page_working ]]; then
    echo -e "     $TICK ${block_page}"
  else
    echo -e "     $CROSS X-Header does not match or could not be retrieved"
  fi

  if [[ $dashboard == $dashboard_working ]]; then
    echo -e "     $TICK ${dashboard}"
  else
    echo -e "     $CROSS X-Header does not match or could not be retrieved"
  fi
}

dig_at() {
  local protocol="${1}"
  local IP="${2}"
  echo_current_diagnostic "Domain name resolution (IPv${protocol}) using a random blocked domain"
  local url
  local local_dig
  local pihole_dig
  local remote_dig

  if [[ ${protocol} == "6" ]]; then
    local local_address="::1"
    local pihole_address="${IPV6_ADDRESS%/*}"
    local remote_address="2001:4860:4860::8888"
    local record_type="AAAA"
  else
    local local_address="127.0.0.1"
    local pihole_address="${IPV4_ADDRESS%/*}"
    local remote_address="8.8.8.8"
    local record_type="A"
  fi

  # Find a random blocked url that has not been whitelisted.
  local random_url=$(shuf -n 1 "${GRAVITYFILE}" | awk -F ' ' '{ print $2 }')

  local remote_url="doubleclick.com"

  if local_dig=$(dig -"${protocol}" "${random_url}" @${local_address} +short "${record_type}"); then
    echo -e "     ${TICK} ${random_url} is ${local_dig} via localhost (${local_address})"
  else
    echo -e "     ${CROSS} Failed to resolve ${random_url} via localhot (${local_address})"
  fi

  if pihole_dig=$(dig -"${protocol}" "${random_url}" @${pihole_address} +short "${record_type}"); then
    echo -e "     ${TICK} ${random_url} is ${pihole_dig} via Pi-hole (${pihole_address})"
  else
    echo -e "     ${CROSS} Failed to resolve ${random_url} via Pi-hole (${pihole_address})"
  fi

  if remote_dig=$(dig -"${protocol}" "${remote_url}" @${remote_address} +short "${record_type}" | head -n1); then
    echo -e "     ${TICK} ${random_url} is ${remote_dig} via a remote, public DNS server (${remote_address})"
  else
    echo -e "     ${CROSS} Failed to resolve ${remote_url} via a remote, public DNS server (${remote_address})"
  fi
}

process_status(){
  echo_current_diagnostic "Pi-hole processes"
  PROCESSES=( dnsmasq lighttpd pihole-FTL )
  local i
  for i in "${PROCESSES[@]}"; do
    local status_of_process=$(systemctl is-active "${i}")
    echo -e "    [i] ${i} daemon is ${status_of_process}"
  done
}

parse_file() {
  # Set the first argument passed to tihs function as a named variable for better readability
  local filename="${1}"
  # Put the current Internal Field Separator into another variable so it can be restored later
  OLD_IFS="$IFS"
  # Get the lines that are in the file(s) and store them in an array for parsing later
  IFS=$'\r\n' command eval 'file_info=( $(cat "${filename}") )'

  # Set a named variable for better readability
  local file_lines
  # For each lin in the file,
  for file_lines in "${file_info[@]}"; do
    # display the information with the ${INFO} icon
    echo "       ${INFO} ${file_lines}"
  done
  # Set the IFS back to what it was
  IFS="$OLD_IFS"
}

diagnose_setup_variables() {
  # Display the current test that is running
  echo_current_diagnostic "Setup variables"

  # If the variable file exists,
  file_exists "${VARSFILE}" && \
    # source it
    source ${VARSFILE};
    echo -e "    ${INFO} Sourcing ${VARSFILE}...";
    # and display a green check mark with ${DONE}
    echo_succes_or_fail "${VARSFILE} is readable and has been sourced." || \
    # Othwerwise, error out
    echo_succes_or_fail "${VARSFILE} is not readable.
         ${INFO} $(ls -l ${VARSFILE} 2>/dev/null)";
    parse_file "${VARSFILE}"
}

check_name_resolution() {
  # Check name resoltion from localhost, Pi-hole's IP, and Google's name severs
  dig_at 4 "${IPV4_ADDRESS%/*}"
  # If IPv6 enabled, check resolution
  if [[ "${IPV6_ADDRESS}" ]]; then
    dig_at 6 "${IPV6_ADDRESS%/*}"
  fi
}

# This function can check a directory exists
# Pi-hole has files in several places, so we will reuse this function
dir_check() {
  # Set the first argument passed to tihs function as a named variable for better readability
  local directory="${1}"
  # Display the current test that is running
  echo_current_diagnostic "contents of ${directory}"
  # For each file in the directory,
  for filename in "${directory}"; do
    # check if exists first; if it does,
    file_exists "${filename}" && \
    # show a success message
    echo_succes_or_fail "Files detected" || \
    # Otherwise, show an error
    echo_succes_or_fail "directory does not exist"
  done
}

list_files_in_dir() {
  # Set the first argument passed to tihs function as a named variable for better readability
  local dir_to_parse="${1}"
  # Store the files found in an array
  files_found=( $(ls "${dir_to_parse}") )
  # For each file in the arry,
  for each_file in "${files_found[@]}"; do
    # display the information with the ${INFO} icon
    # Also print the permissions and the user/group
    echo -e "       ${INFO} ${each_file} ( $(ls -ld ${dir_to_parse}/${each_file} | awk '{print $1, $3, $4}') )"
  done

}

check_dnsmasq_d() {
  # Set a local variable for better readability
  local directory=/etc/dnsmasq.d
  # Check if the directory exists
  dir_check "${directory}"
  # if it does, list the files in it
  list_files_in_dir "${directory}"
}

check_lighttpd_d() {
  # Set a local variable for better readability
  local directory=/etc/lighttpd
  # Check if the directory exists
  dir_check "${directory}"
  # if it does, list the files in it
  list_files_in_dir "${directory}"
}

check_cron_d() {
  # Set a local variable for better readability
  local directory=/etc/cron.d
  # Check if the directory exists
  dir_check "${directory}"
  # if it does, list the files in it
  list_files_in_dir "${directory}"
}

check_http_directory() {
  # Set a local variable for better readability
  local directory=/var/www/html
  # Check if the directory exists
  dir_check "${directory}"
  # if it does, list the files in it
  list_files_in_dir "${directory}"
}

analyze_gravity_list() {
  gravity_length=$(grep -c ^ "${GRAVITYFILE}") && \
    echo -e "   ${INFO} ${GRAVITYFILE} is ${gravity_length} lines long." || \
    echo -e "   ${CROSS} ${GRAVITYFILE} not found!"
}

upload_to_tricorder() {
  local tricorder
	echo "${TICK} Finshed debugging!"

  # Ensure the file exists, create if not, clear if exists.
  truncate --size=0 "${DEBUG_LOG}"
  # Set the permissions and owner
  chmod 644 ${DEBUG_LOG}
  chown "$USER":pihole ${DEBUG_LOG}
  # Copy working temp file to final log location
  cat /proc/$$/fd/3 >> "${DEBUG_LOG}"
  # Straight dump of tailing the logs, can sanitize later if needed.
  cat /proc/$$/fd/4 >> "${DEBUG_LOG}"

	echo "::: The debug log can be uploaded to tricorder.pi-hole.net for sharing with developers only."
	if [[ "${AUTOMATED}" ]]; then
	  echo "${INFO} Debug script running in automated mode; uploading log to tricorder..."
	  tricorder=$(cat /var/log/pihole_debug.log | nc tricorder.pi-hole.net 9999)
	else
	  read -r -p "\n\n[?] Would you like to upload the log? [y/N] " response
	  case ${response} in
		  [yY][eE][sS]|[yY]) tricorder=$(cat /var/log/pihole_debug.log | nc tricorder.pi-hole.net 9999);;
		  *) echo "${INFO} Log will NOT be uploaded to tricorder.";;
	  esac
  fi
	# Check if tricorder.pi-hole.net is reachable and provide token.
	if [[ -n "${tricorder}" ]]; then
		echo "::: ---=== Your debug token is : ${tricorder} Please make a note of it. ===---"
		echo "::: Contact the Pi-hole team with your token for assistance."
		echo "::: Thank you."
	else
		echo "::: There was an error uploading your debug log."
		echo "::: Please try again or contact the Pi-hole team for assistance."
	fi
		echo "::: A local copy of the Debug log can be found at : /var/log/pihole_debug.log"

}



initiate_debug
check_core_version
check_web_version
check_ftl_version
diagnose_setup_variables
diagnose_operating_system
processor_check
check_networking
check_name_resolution
process_status
check_x_headers
check_critical_dependencies
check_dnsmasq_d
check_lighttpd_d
check_http_directory
check_cron_d
upload_to_tricorder
