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

if_file_exists() {
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
  if_file_exists /etc/*release && \
    # display the attributes to the user
    get_distro_attributes || \
    # If it doesn't exist, it's not a system we currently support and link to FAQ
    echo -e "    ${CROSS} ${COL_LIGHT_RED}${error_msg}${COL_NC}
         ${INFO} ${COL_LIGHT_RED}Please see${COL_NC}: ${COL_CYAN}${faq_url}${COL_NC}"
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
  if_file_exists "${VARSFILE}" && \
    # source it
    echo -e "    ${INFO} Sourcing ${VARSFILE}...";
    source ${VARSFILE};
    # and display a green check mark with ${DONE}
    echo_succes_or_fail "${VARSFILE} is readable and has been sourced." || \
    # Othwerwise, error out
    echo_succes_or_fail "${VARSFILE} is not readable.
         ${INFO} $(ls -l ${VARSFILE} 2>/dev/null)";
    parse_file "${VARSFILE}"
}

# This function can check a directory exists
# Pi-hole has files in several places, so we will reuse this function
dir_check() {
  # Set the first argument passed to tihs function as a named variable for better readability
  local directory="${1}"
  # Display the current test that is running
  echo_current_diagnostic "contents of ${directory}"
  # For each file in the directory,
  for filename in "${directory}"*; do
    # check if exists first; if it does,
    if_file_exists "${filename}" && \
    # show a success message
    echo_succes_or_fail "Files detected" || \
    # Otherwise, show an error
    echo_succes_or_fail "directory does not exist"
  done
}

list_files_in_dir() {
  # Set the first argument passed to tihs function as a named variable for better readability
  local dir_to_parse="${1}"
  # Set another local variable for better readability
  local filename
  # Store the files found in an array
  files_found=( $(ls "${dir_to_parse}") )
  # For each file in the arry,
  for each_file in "${files_found[@]}"; do
    # display the information with the ${INFO} icon
    echo "       ${INFO} ${each_file}"
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

initiate_debug
diagnose_operating_system
diagnose_setup_variables
check_dnsmasq_d
