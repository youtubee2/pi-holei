#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Generates pihole_debug.log to be used for troubleshooting.
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.


# -e option instructs bash to immediately exit if any command [1] has a non-zero exit status
# -u a reference to any variable you haven't previously defined
# with the exceptions of $* and $@ - is an error, and causes the program to immediately exit
# -o pipefail prevents errors in a pipeline from being masked. If any command in a pipeline fails,
# that return code will be used as the return code of the whole pipeline. By default, the
# pipeline's return code is that of the last command - even if it succeeds
set -o pipefail
#IFS=$'\n\t'

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

# FAQ URLs
FAQ_UPDATE_PI_HOLE="https://discourse.pi-hole.net/t/how-do-i-update-pi-hole/249"
FAQ_CHECKOUT_COMMAND="https://discourse.pi-hole.net/t/the-pihole-command-with-examples/738#checkout"

# These provide the colors we need for making the log more readable
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

make_temporary_log() {
  # Create temporary file for log
  TEMPLOG=$(mktemp /tmp/pihole_temp.XXXXXX)
  # Open handle 3 for templog
  # https://stackoverflow.com/questions/18460186/writing-outputs-to-log-file-and-console
  exec 3>"$TEMPLOG"
  # Delete templog, but allow for addressing via file handle.
  rm "$TEMPLOG"
}

log_write() {
  # echo arguments to both the log and the console
  echo -e "${@}" | tee -a /proc/$$/fd/3
}

copy_to_debug_log() {
  # Copy the contents of file descriptor 3 into the debug log so it can be uploaded to tricorder
  cat /proc/$$/fd/3 >> "${DEBUG_LOG}"
}

echo_succes_or_fail() {
  # If the command was successful (a zero),
  if [[ $? -eq 0 ]]; then
    # Set the first argument passed to this function as a named variable for better readability
    local message="${1}"
    # show success
    log_write "${TICK} ${message}"
  else
    local message="${1}"
    # Otherwise, show a error
    log_write "${CROSS} ${message}"
  fi
}

initiate_debug() {
  # Clear the screen so the debug log is readable
  clear
  # Display that the debug process is beginning
  log_write "${COL_LIGHT_PURPLE}*** [ INITIALIZING ]${COL_NC}"
  # Timestamp the start of the log
  log_write "${INFO} $(date "+%Y-%m-%d:%H:%M:%S") debug log has been initiated."
}

# This is a function for visually displaying the curent test that is being run.
# Accepts one variable: the name of what is being diagnosed
# Colors do not show in the dasboard, but the icons do: [i], [✓], and [✗]
echo_current_diagnostic() {
  # Colors are used for visually distinguishing each test in the output
  # These colors do not show in the GUI, but the formatting will
  log_write "\n${COL_LIGHT_PURPLE}*** [ DIAGNOSING ]:${COL_NC} ${1}"
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

# Checks the core version of the Pi-hole codebase
check_core_version() {
  echo_current_diagnostic "Pi-hole versions"
  # Store the error message in a variable in case we want to change and/or reuse it
  local error_msg="git status failed"
  # If the pihole git directory exists,
  if_directory_exists "${PIHOLEGITDIR}" && \
    # move into it
    cd "${PIHOLEGITDIR}" || \
    # if not, report an error
    log_write "pihole repo does not exist"
    # If the git status command completes successfully,
    # we can assume we can get the information we want
    if git status &> /dev/null; then
      # The current version the user is on
      PI_HOLE_VERSION=$(git describe --tags --abbrev=0);
      # What branch they are on
      PI_HOLE_BRANCH=$(git rev-parse --abbrev-ref HEAD);
      # The commit they are on
      PI_HOLE_COMMIT=$(git describe --long --dirty --tags --always)
      # echo this information out to the user in a nice format
      # If the current version matches what pihole -v produces, the user is up-to-date
      if [[ "${PI_HOLE_VERSION}" == "$(pihole -v | awk '/Pi-hole/ {print $6}' | cut -d ')' -f1)" ]]; then
        log_write "${TICK} Core: ${COL_LIGHT_GREEN}${PI_HOLE_VERSION}${COL_NC}"
      # If not,
      else
        # echo the current version in yellow, signifying it's something to take a look at, but not a critical error
        # Also add a URL to an FAQ
        log_write "${INFO} Core: ${COL_YELLOW}${PI_HOLE_VERSION:-Untagged}${COL_NC} (${COL_CYAN}${FAQ_UPDATE_PI_HOLE}${COL_NC})"
      fi

      # If the repo is on the master branch, they are on the stable codebase
      if [[ "${PI_HOLE_BRANCH}" == "master" ]]; then
        # so the color of the text is green
        log_write "${INFO} Branch: ${COL_LIGHT_GREEN}${PI_HOLE_BRANCH}${COL_NC}"
      # If it is any other branch, they are in a developement branch
      else
        # So show that in yellow, signifying it's something to take a look at, but not a critical error
        log_write "${INFO} Branch: ${COL_YELLOW}${PI_HOLE_BRANCH:-Detached}${COL_NC} (${COL_CYAN}${FAQ_CHECKOUT_COMMAND}${COL_NC})"
      fi
        # echo the current commit
        log_write "${INFO} Commit: ${PI_HOLE_COMMIT}\n"
    # If git status failed,
    else
      # Return an error message
      log_write "${error_msg}"
      # and exit with a non zero code
      return 1
    fi
}

check_web_version() {
  # Local variable for the error message
  local error_msg="git status failed"
  # If the directory exists,
  if_directory_exists "${ADMINGITDIR}" && \
    # move into it
    cd "${ADMINGITDIR}" || \
    # if not, give an error message
    log_write "repo does not exist"
    # If the git status command completes successfully,
    # we can assume we can get the information we want
    if git status &> /dev/null; then
      # The current version the user is on
      WEB_VERSION=$(git describe --tags --abbrev=0);
      # What branch they are on
      WEB_BRANCH=$(git rev-parse --abbrev-ref HEAD);
      # The commit they are on
      WEB_COMMIT=$(git describe --long --dirty --tags --always)
      # If the Web version reported by pihole -v matches the current version
      if [[ "${WEB_VERSION}" == "$(pihole -v | awk '/AdminLTE/ {print $6}' | cut -d ')' -f1)" ]]; then
        # echo it in green
        log_write "${TICK} Web: ${COL_LIGHT_GREEN}${WEB_VERSION}${COL_NC}"
      # Otherwise,
      else
        # Show it in yellow with a link to update Pi-hole
        log_write "${INFO} Web: ${COL_YELLOW}${WEB_VERSION:-Untagged}${COL_NC} (${COL_CYAN}${FAQ_UPDATE_PI_HOLE}${COL_NC})"
      fi


      # If the repo is on the master branch, they are on the stable codebase
      if [[ "${WEB_BRANCH}" == "master" ]]; then
        # so the color of the text is green
        log_write "${TICK} Branch: ${COL_LIGHT_GREEN}${WEB_BRANCH}${COL_NC}"
      else
        # If it is any other branch, they are in a developement branch
        # So show that in yellow, signifying it's something to take a look at, but not a critical error
        log_write "${INFO} Branch: ${COL_YELLOW}${WEB_BRANCH:-Detached}${COL_NC} (${COL_CYAN}${FAQ_CHECKOUT_COMMAND}${COL_NC})"
      fi
        # echo the current commit
        log_write "${INFO} Commit: ${WEB_COMMIT}\n"
    # If git status failed,
    else
      # Return an error message
      log_write "${error_msg}"
      # and exit with a non zero code
      return 1
    fi
}

check_ftl_version() {
  # Use the built in command to check FTL's version
  FTL_VERSION=$(pihole-FTL version)
  # Compare the current FTL version to the remote version
  if [[ "${FTL_VERSION}" == "$(pihole -v | awk '/FTL/ {print $6}' | cut -d ')' -f1)" ]]; then
    # If they are the same, FTL is up-to-date
    log_write "${TICK} FTL: ${COL_LIGHT_GREEN}${FTL_VERSION}${COL_NC}"
  else
    # If not, show it in yellow, signifying there is an update
    log_write "${TICK} FTL: ${COL_YELLOW}${FTL_VERSION}${COL_NC}"
  fi
}

# Check the current version of the Web server
check_web_server_version() {
  # Store the name in a variable in case we ever want to change it
  WEB_SERVER="lighttpd"
  # Parse out just the version number
  WEB_SERVER_VERSON="$(lighttpd -v |& head -n1 | cut -d '/' -f2 | cut -d ' ' -f1)"
  # If the Web server does not have a version (the variable is empty)
  if [[ -z "${WEB_SERVER_VERSON}" ]]; then
    # Display and error
    log_write "${CROSS} ${COL_LIGHT_RED}${WEB_SERVER} version could not be detected.${COL_NC}"
  else
    # Otherwise, display the version
    log_write "${TICK} ${WEB_SERVER}: ${WEB_SERVER_VERSON}"
  fi
}

# Check the current version of the DNS server
check_resolver_server_version() {
  # Store the name in a variable in case we ever want to change it
  RESOLVER="dnsmasq"
  # Parse out just the version number
  RESOVLER_VERSON="$(dnsmasq -v |& head -n1 | awk '{print $3}')"
  # If the DNS server does not have a version (the variable is empty)
  if [[ -z "${RESOVLER_VERSON}" ]]; then
    # Display and error
    log_write "${CROSS} ${COL_LIGHT_RED}${RESOLVER} version could not be detected.${COL_NC}"
  else
    # Otherwise, display the version
    log_write "${TICK} ${RESOLVER}: ${RESOVLER_VERSON}"
  fi
}

check_php_version() {
  # Parse out just the version number
  PHP_VERSION=$(php -v |& head -n1 | cut -d '-' -f1 | cut -d ' ' -f2)
  # If no version is detected,
  if [[ -z "${PHP_VERSION}" ]]; then
    # show an error
    log_write "${CROSS} ${COL_LIGHT_RED}PHP version could not be detected.${COL_NC}"
  else
    # Otherwise, show the version
    log_write "${TICK} PHP: ${PHP_VERSION}"
  fi
}

# These are the most critical dependencies of Pi-hole, so we check for them
# and their versions, using the functions above.
check_critical_dependencies() {
  echo_current_diagnostic "Versions of critical dependencies"
  # Use the function created earlier and bundle them into one function that checks all the version numbers
  check_web_server_version
  check_resolver_server_version
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
    # store the key in a variable
    local pretty_name_key=$(echo "${distro_attribute}" | grep "PRETTY_NAME" | cut -d '=' -f1)
    # we need just the OS PRETTY_NAME,
    if [[ "${pretty_name_key}" == "PRETTY_NAME" ]]; then
      # so print it when we find it
      PRETTY_NAME_VALUE=$(echo "${distro_attribute}" | grep "PRETTY_NAME" | cut -d '=' -f2- | tr -d '"')
      # and then echoed out to the screen
      log_write "${INFO} ${PRETTY_NAME_VALUE}"
    else
      # Since we only need the pretty name, we can just skip over anything that is not a match
      :
    fi
  done
  # Set the IFS back to what it was
  IFS="$OLD_IFS"
}

diagnose_operating_system() {
  # local variable for system requirements
  FAQ_HARDWARE_REQUIREMENTS="https://discourse.pi-hole.net/t/hardware-software-requirements/273"
  # error message in a variable so we can easily modify it later (or re-use it)
  local error_msg="Distribution unknown -- most likely you are on an unsupported platform and may run into issues."
  # Display the current test that is running
  echo_current_diagnostic "Operating system"

  # If there is a /etc/*release file, it's probably a supported operating system, so we can
  file_exists /etc/*release && \
    # display the attributes to the user from the function made earlier
    get_distro_attributes || \
    # If it doesn't exist, it's not a system we currently support and link to FAQ
    log_write "${CROSS} ${COL_LIGHT_RED}${error_msg}${COL_NC} (${COL_CYAN}${FAQ_HARDWARE_REQUIREMENTS}${COL_NC})"
}

processor_check() {
  echo_current_diagnostic "Processor"
  # Store the processor type in a variable
  PROCESSOR=$(uname -m)
  # If it does not contain a value,
  if [[ -z "${PROCESSOR}" ]]; then
    # we couldn't detect it, so show an error
    log_write "${CROSS} ${COL_LIGHT_RED}Processor could not be identified.${COL_NC}"
  else
    # Otherwise, show the processor type
    log_write "${INFO} ${PROCESSOR}"
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
    # Display the protocol and interface
    log_write "${TICK} IPv${protocol} on ${PIHOLE_INTERFACE}"
    # Since there may be more than one IP address, store them in an array
    for i in "${!ip_addr_list[@]}"; do
      # For each one in the list, print it out
      log_write "${ip_addr_list[$i]}"
    done
    log_write ""
  else
    # If there are no IPs detected, explain that the protocol is not configured
    log_write "${CROSS} ${COL_LIGHT_RED}No IPv${protocol} found on ${PIHOLE_INTERFACE}${COL_NC}\n"
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
  else
    # Otherwise, just use ping
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
    log_write "* Trying three pings on IPv${protocol} gateway at ${gateway}..."
    # Try to quietly ping the gateway 3 times, with a timeout of 3 seconds, using numeric output only,
    # on the pihole interface, and tail the last three lines of the output
    # If pinging the gateway is not successful,
    if ! ping_cmd="$(${cmd} -q -c 3 -W 3 -n ${gateway} -I ${PIHOLE_INTERFACE} | tail -n 3)"; then
      # let the user know
      log_write "${CROSS} ${COL_LIGHT_RED}Gateway did not respond.${COL_NC}\n"
      # and return an error code
      return 1
    # Otherwise,
    else
      # show a success
      log_write "${TICK} ${COL_LIGHT_GREEN}Gateway responded.${COL_NC}\n"
      # and return a success code
      return 0
    fi
  fi
}

ping_internet() {
  # Give the first argument a readable name (a 4 or a six should be the argument)
  local protocol="${1}"
  # If the protocol is 6,
  if [[ ${protocol} == "6" ]]; then
    # use ping6
    local cmd="ping6"
    # and Google's public IPv6 address
    local public_address="2001:4860:4860::8888"
  else
    # Otherwise, just use ping
    local cmd="ping"
    # and Google's public IPv4 address
    local public_address="8.8.8.8"
  fi
  echo -n "${INFO} Trying three pings on IPv${protocol} to reach the Internet..."
  # Try to ping the address 3 times
  if ! ping_inet="$(${cmd} -q -W 3 -c 3 -n ${public_address} -I ${PIHOLE_INTERFACE} | tail -n 3)"; then
    # if it's unsuccessful, show an error
    log_write "${CROSS} ${COL_LIGHT_RED}Cannot reach the Internet.${COL_NC}\n"
    return 1
  else
    # Otherwise, show success
    log_write "${TICK} ${COL_LIGHT_GREEN}Query responded.${COL_NC}\n"
    return 0
  fi
}

check_required_ports() {
  # Since Pi-hole needs 53, 80, and 4711, check what they are being used by
  # so we can detect any issues
  log_write "${INFO} Ports in use:"
  # Create an array for these ports in use
  ports_in_use=()
  # Sort the addresses and remove duplicates
  while IFS= read -r line; do
      ports_in_use+=( "$line" )
  done < <( lsof -i -P -n | awk -F' ' '/LISTEN/ {print $9, $1}' | sort -n | uniq | cut -d':' -f2 )

  # Now that we have the values stored,
  for i in ${!ports_in_use[@]}; do
    # loop through them and assign some local variables
    local port_number="$(echo "${ports_in_use[$i]}" | awk '{print $1}')"
    local service_name=$(echo "${ports_in_use[$i]}" | awk '{print $2}')
    # Use a case statement to determine if the right services are using the right ports
    case "${port_number}" in
      53) if [[ "${service_name}" == "dnsmasq" ]]; then
            # if port 53 is dnsmasq, show it in green as it's standard
            log_write "[${COL_LIGHT_GREEN}${port_number}${COL_NC}] is in use by ${COL_LIGHT_GREEN}${service_name}${COL_NC}"
          # Otherwise,
          else
            # Show the service name in red since it's non-standard
            log_write "[${COL_LIGHT_RED}${port_number}${COL_NC}] is in use by ${COL_LIGHT_RED}${service_name}${COL_NC}
                Please see: ${COL_CYAN}https://discourse.pi-hole.net/t/hardware-software-requirements/273#ports${COL_NC}"
          fi
          ;;
      80) if [[ "${service_name}" == "lighttpd" ]]; then
            # if port 53 is dnsmasq, show it in green as it's standard
            log_write "[${COL_LIGHT_GREEN}${port_number}${COL_NC}] is in use by ${COL_LIGHT_GREEN}${service_name}${COL_NC}"
          # Otherwise,
          else
            # Show the service name in red since it's non-standard
            log_write "[${COL_LIGHT_RED}${port_number}${COL_NC}] is in use by ${COL_LIGHT_RED}${service_name}${COL_NC}
                Please see: ${COL_CYAN}https://discourse.pi-hole.net/t/hardware-software-requirements/273#ports${COL_NC}"
          fi
          ;;
      4711) if [[ "${service_name}" == "pihole-FT" ]]; then
            # if port 4711 is pihole-FTL, show it in green as it's standard
            log_write "[${COL_LIGHT_GREEN}${port_number}${COL_NC}] is in use by ${COL_LIGHT_GREEN}${service_name}${COL_NC}"
          # Otherwise,
          else
            # Show the service name in yellow since it's non-standard, but should still work
            log_write "[${COL_YELLOW}${port_number}${COL_NC}] is in use by ${COL_YELLOW}${service_name}${COL_NC}
                Please see: ${COL_CYAN}https://discourse.pi-hole.net/t/hardware-software-requirements/273#ports${COL_NC}"
          fi
          ;;
      *) log_write "[${port_number}] is in use by ${service_name}";
    esac
  done
}

check_networking() {
  # Runs through several of the functions made earlier; we just clump them
  # together since they are all related to the networking aspect of things
  echo_current_diagnostic "Networking"
  detect_ip_addresses "4"
  ping_gateway "4"
  detect_ip_addresses "6"
  ping_gateway "6"
  check_required_ports
}

check_x_headers() {
  # The X-Headers allow us to determine from the command line if the Web
  # server is operating correctly
  echo_current_diagnostic "Dashboard and block page"
  # Use curl -I to get the header and parse out just the X-Pi-hole one
  local block_page=$(curl -Is localhost | awk '/X-Pi-hole/' | tr -d '\r')
  # Do it for the dashboard as well, as the header is different than above
  local dashboard=$(curl -Is localhost/admin/ | awk '/X-Pi-hole/' | tr -d '\r')
  # Store what the X-Header shoud be in variables for comparision later
  local block_page_working="X-Pi-hole: A black hole for Internet advertisements."
  local dashboard_working="X-Pi-hole: The Pi-hole Web interface is working!"
  # If the X-header found by curl matches what is should be,
  if [[ $block_page == $block_page_working ]]; then
    # display a success message
    log_write "$TICK ${COL_LIGHT_GREEN}${block_page}${COL_NC}"
  else
    # Otherwise, show an error
    log_write "$CROSS ${COL_LIGHT_RED}X-Header does not match or could not be retrieved.${COL_NC}"
  fi

  # Same logic applies to the dashbord as above, if the X-Header matches what a working system shoud have,
  if [[ $dashboard == $dashboard_working ]]; then
    # then we can show a success
    log_write "$TICK ${COL_LIGHT_GREEN}${dashboard}${COL_NC}"
  else
    # Othewise, it's a failure since the X-Headers either don't exist or have been modified in some way
    log_write "$CROSS ${COL_LIGHT_RED}X-Header does not match or could not be retrieved.${COL_NC}"
  fi
}

dig_at() {
  # We need to test if Pi-hole can properly resolve domain names
  # as it is an essential piece of the software

  # Store the arguments as variables with names
  local protocol="${1}"
  local IP="${2}"
  echo_current_diagnostic "Domain name resolution (IPv${protocol}) using a random blocked domain"
  # Set more local variables
  local url
  local local_dig
  local pihole_dig
  local remote_dig
  # Use a static domain that we know has IPv4 and IPv6 to avoid false positives
  # Sometimes the randomly chosen domains don't use IPv6, or something else is wrong with them
  local remote_url="doubleclick.com"

  # If the protocol (4 or 6) is 6,
  if [[ ${protocol} == "6" ]]; then
    # Set the IPv6 variables and record type
    local local_address="::1"
    local pihole_address="${IPV6_ADDRESS%/*}"
    local remote_address="2001:4860:4860::8888"
    local record_type="AAAA"
  # Othwerwise, it should be 4
  else
    # so use the IPv4 values
    local local_address="127.0.0.1"
    local pihole_address="${IPV4_ADDRESS%/*}"
    local remote_address="8.8.8.8"
    local record_type="A"
  fi

  # Find a random blocked url that has not been whitelisted.
  # This helps emulate queries to different domains that a user might query
  # It will also give extra assurance that Pi-hole is correctly resolving and blocking domains
  local random_url=$(shuf -n 1 "${GRAVITYFILE}" | awk -F ' ' '{ print $2 }')

  # First, do a dig on localhost to see if Pi-hole can use itself to block a domain
  if local_dig=$(dig +tries=1 +time=2 -"${protocol}" "${random_url}" @${local_address} +short "${record_type}"); then
    # If it can, show sucess
    log_write "${TICK} ${random_url} ${COL_LIGHT_GREEN}is ${local_dig}${COL_NC} via localhost (${local_address})"
  else
    # Otherwise, show a failure
    log_write "${CROSS} ${COL_LIGHT_RED}Failed to resolve${COL_NC} ${random_url} ${COL_LIGHT_RED}via localhost${COL_NC} (${local_address})"
  fi

  # Next we need to check if Pi-hole can resolve a domain when the query is sent to it's IP address
  # This better emulates how clients will interact with Pi-hole as opposed to above where Pi-hole is
  # just asing itself locally
  # The default timeouts and tries are reduced in case the DNS server isn't working, so the user isn't waiting for too long

  # If Pi-hole can dig itself from it's IP (not the loopback address)
  if pihole_dig=$(dig +tries=1 +time=2 -"${protocol}" "${random_url}" @${pihole_address} +short "${record_type}"); then
    # show a success
    log_write "${TICK} ${random_url} ${COL_LIGHT_GREEN}is ${pihole_dig}${COL_NC} via Pi-hole (${pihole_address})"
  else
    # Othewise, show a failure
    log_write "${CROSS} ${COL_LIGHT_RED}Failed to resolve${COL_NC} ${random_url} ${COL_LIGHT_RED}via Pi-hole${COL_NC} (${pihole_address})"
  fi

  # Finally, we need to make sure legitimate queries can out to the Internet using an external, public DNS server
  # We are using the static remote_url here instead of a random one because we know it works with IPv4 and IPv6
  if remote_dig=$(dig +tries=1 +time=2 -"${protocol}" "${remote_url}" @${remote_address} +short "${record_type}" | head -n1); then
    # If successful, the real IP of the domain will be returned instead of Pi-hole's IP
    log_write "${TICK} ${remote_url} ${COL_LIGHT_GREEN}is ${remote_dig}${COL_NC} via a remote, public DNS server (${remote_address})"
  else
    # Otherwise, show an error
    log_write "${CROSS} ${COL_LIGHT_RED}Failed to resolve${COL_NC} ${remote_url} ${COL_LIGHT_RED}via a remote, public DNS server${COL_NC} (${remote_address})"
  fi
}

process_status(){
  # Check to make sure Pi-hole's services are running and active
  echo_current_diagnostic "Pi-hole processes"
  # Store them in an array for easy use
  PROCESSES=( dnsmasq lighttpd pihole-FTL )
  # Local iterator
  local i
  # For each process,
  for i in "${PROCESSES[@]}"; do
    # get its status
    local status_of_process=$(systemctl is-active "${i}")
    # and print it out to the user
    if [[ "${status_of_process}" == "active" ]]; then
      # If it's active, show it in green
      log_write "${TICK} ${COL_LIGHT_GREEN}${i}${COL_NC} daemon is ${COL_LIGHT_GREEN}${status_of_process}${COL_NC}"
    else
      # If it's not, show it in red
      log_write "${CROSS} ${COL_LIGHT_RED}${i}${COL_NC} daemon is ${COL_LIGHT_RED}${status_of_process}${COL_NC}"
    fi
  done
}

make_array_from_file() {
  local filename="${1}"
  if [[ -d "${filename}" ]]; then
    :
  else
    while IFS= read -r line;do
      file_content+=("${line}")
    done < "${filename}"
  fi
}

parse_file() {
  # Set the first argument passed to this function as a named variable for better readability
  local filename="${1}"
  # Put the current Internal Field Separator into another variable so it can be restored later
  OLD_IFS="$IFS"
  # Get the lines that are in the file(s) and store them in an array for parsing later
  IFS=$'\r\n' command eval 'file_info=( $(cat "${filename}") )'

  # Set a named variable for better readability
  local file_lines
  # For each line in the file,
  for file_lines in "${file_info[@]}"; do
      # Display the file's content
      log_write "    ${file_lines}" | grep -v "#" | sed '/^$/d'
  done
  # Set the IFS back to what it was
  IFS="$OLD_IFS"
}

diagnose_setup_variables() {
  # Display the current test that is running
  echo_current_diagnostic "Setup variables"

  # If the variable file exists,
  file_exists "${VARSFILE}" && \
    log_write "* Sourcing ${VARSFILE}...";
    # source it
    source ${VARSFILE};
    # and display a green check mark with ${DONE}
    echo_succes_or_fail "${COL_LIGHT_GREEN}${VARSFILE}${COL_NC} is readable and ${COL_LIGHT_GREEN}has been sourced.${COL_NC}" || \
    # Othwerwise, error out
    echo_succes_or_fail "${VARSFILE} ${COL_LIGHT_RED}is not readable.${COL_NC}
         ${INFO} $(ls -l ${VARSFILE} 2>/dev/null)";
    parse_file "${VARSFILE}"
}

check_name_resolution() {
  # Check name resoltion from localhost, Pi-hole's IP, and Google's name severs
  # using the function we created earlier
  dig_at 4 "${IPV4_ADDRESS%/*}"
  # If IPv6 enabled,
  if [[ "${IPV6_ADDRESS}" ]]; then
    # check resolution
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
    # do nothing
    : || \
    # Otherwise, show an error
    echo_succes_or_fail "${COL_LIGHT_RED}directory does not exist.${COL_NC}"
  done
}

list_files_in_dir() {
  # Set the first argument passed to tihs function as a named variable for better readability
  local dir_to_parse="${1}"
  # Store the files found in an array
  files_found=( $(ls "${dir_to_parse}") )
  # For each file in the arry,
  for each_file in "${files_found[@]}"; do
    if [[ -d "${each_file}" ]]; then
      :
    else
      # display the information with the ${INFO} icon
      # Also print the permissions and the user/group
      log_write "\n${COL_LIGHT_GREEN}$(ls -ld ${dir_to_parse}/${each_file})${COL_NC}"
      # Otherwise, parse the file's content
      make_array_from_file "${dir_to_parse}/${each_file}"
      for each_line in "${file_content[@]}"; do
        log_write "   ${each_line}"
      done
    fi
  file_content=()
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
  echo_current_diagnostic "Gravity list"
  # It's helpful to know how big a user's gravity file is
  gravity_length=$(grep -c ^ "${GRAVITYFILE}") && \
    log_write "${INFO} ${GRAVITYFILE} is ${gravity_length} lines long." || \
    # If the previous command failed, something is wrong with the file
    log_write "${CROSS} ${COL_LIGHT_RED}${GRAVITYFILE} not found!${COL_NC}"
}

tricorder_use_nc_or_ssl() {
  # Users can submit their debug logs using nc (unencrypted) or openssl (enrypted) if available
  # Check for openssl first since encryption is a good thing
  if command -v openssl &> /dev/null; then
    # If the command exists,
    log_write "    * Using ${COL_LIGHT_GREEN}openssl${COL_NC} for transmission."
    # encrypt and transmit the log and store the token returned in a variable
    tricorder_token=$(cat ${DEBUG_LOG} | openssl s_client -quiet -connect tricorder.pi-hole.net:9998 2> /dev/null)
  # Otherwise,
  else
    # use net cat
    log_write "${INFO} Using ${COL_YELLOW}netcat${COL_NC} for transmission."
    tricorder_token=$(cat ${DEBUG_LOG} | nc tricorder.pi-hole.net 9999)
  fi
}


upload_to_tricorder() {
  # Set the permissions and owner
  chmod 644 ${DEBUG_LOG}
  chown "$USER":pihole ${DEBUG_LOG}

  # Let the user know debugging is complete
  echo ""
	log_write "${TICK} ${COL_LIGHT_GREEN}** Finished debugging! **${COL_NC}\n"

  # Provide information on what they should do with their token
	log_write "    * The debug log can be uploaded to tricorder.pi-hole.net for sharing with developers only."
  log_write "    * For more information, see: ${COL_CYAN}https://pi-hole.net/2016/11/07/crack-our-medical-tricorder-win-a-raspberry-pi-3/${COL_NC}"
  log_write "    * If available, we'll use openssl to upload the log, otherwise it will fall back to netcat."
  # If pihole -d is running automatically (usually throught the dashboard)
	if [[ "${AUTOMATED}" ]]; then
    # let the user know
    log_write "${INFO} Debug script running in automated mode"
    # and then decide again which tool to use to submit it
    if command -v openssl &> /dev/null; then
      log_write "${INFO} Using ${COL_LIGHT_GREEN}openssl${COL_NC} for transmission."
      tricorder_token=$(openssl s_client -quiet -connect tricorder.pi-hole.net:9998 2> /dev/null < /dev/stdin)
    else
      log_write "${INFO} Using ${COL_YELLOW}netcat${COL_NC} for transmission."
      tricorder_token=$(nc tricorder.pi-hole.net 9999 < /dev/stdin)
    fi
	else
    echo ""
    # Give the user a choice of uploading it or not
    # Users can review the log file locally and try to self-diagnose their problem
	  read -r -p "[?] Would you like to upload the log? [y/N] " response
	  case ${response} in
      # If they say yes, run our function for uploading the log
		  [yY][eE][sS]|[yY]) tricorder_use_nc_or_ssl;;
      # If they choose no, just exit out of the script
		  *) log_write "    * Log will ${COL_LIGHT_GREEN}NOT${COL_NC} be uploaded to tricorder.";exit;
	  esac
  fi
	# Check if tricorder.pi-hole.net is reachable and provide token
  # along with some additional useful information
	if [[ -n "${tricorder_token}" ]]; then
    echo ""
    log_write "${COL_LIGHT_PURPLE}***********************************${COL_NC}"
		log_write "${TICK} Your debug token is: ${COL_LIGHT_GREEN}${tricorder_token}${COL_NC}"
    log_write "${COL_LIGHT_PURPLE}***********************************${COL_NC}"

		log_write "    * Provide this token to the Pi-hole team for assistance:"
		log_write "    * ${COL_CYAN}https://discourse.pi-hole.net${COL_NC}"
    log_write "    * Your log will self-destruct after ${COL_LIGHT_RED}48 hours${COL_NC}."
	else
		log_write "${CROSS}  ${COL_LIGHT_RED}There was an error uploading your debug log.${COL_NC}"
		log_write "    * Please try again or contact the Pi-hole team for assistance."
	fi
		log_write "    * A local copy of the debug log can be found at : ${COL_CYAN}${DEBUG_LOG}${COL_NC}\n"
}

# Run through all the functions we made
make_temporary_log
initiate_debug
check_core_version
check_web_version
check_ftl_version
# setupVars.conf needs to be sourced before the networking so the values are
# available to the check_networking function
diagnose_setup_variables
diagnose_operating_system
processor_check
check_networking
check_name_resolution
process_status
check_x_headers
check_critical_dependencies
analyze_gravity_list
check_dnsmasq_d
check_lighttpd_d
check_http_directory
check_cron_d
copy_to_debug_log
upload_to_tricorder
