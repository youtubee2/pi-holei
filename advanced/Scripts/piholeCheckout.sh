#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Checkout other branches than master
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

readonly PI_HOLE_FILES_DIR="/etc/.pihole"
PH_TEST="true" source "${PI_HOLE_FILES_DIR}/automated install/basic-install.sh"

# webInterfaceGitUrl set in basic-install.sh
# webInterfaceDir set in basic-install.sh
# piholeGitURL set in basic-install.sh
# is_repo() sourced from basic-install.sh
# setupVars set in basic-install.sh

source "${setupVars}"

update=false

fully_fetch_repo() {
  # Add upstream branches to shallow clone
  local directory="${1}"

  cd "${directory}" || return 1
  if is_repo "${directory}"; then
    git remote set-branches origin '*' || return 1
    git fetch --quiet || return 1
  else
    return 1
  fi
  return 0
}

get_available_branches(){
  # Return available branches
  local directory="${1}"

  cd "${directory}" || return 1
  # Get reachable remote branches
  git remote show origin | grep 'tracked' | sed 's/tracked//;s/ //g'
  return
}


fetch_checkout_pull_branch() {
  # Check out specified branch
  local directory="${1}"
  local branch="${2}"

  # Set the reference for the requested branch, fetch, check it put and pull it
  git remote set-branches origin "${branch}" || return 1
  git fetch --quiet || return 1
  checkout_pull_branch "${directory}" "${branch}" || return 1
}

checkout_pull_branch() {
  # Check out specified branch
  local directory="${1}"
  local branch="${2}"

  cd "${directory}" || return 1
  if [ "$(git diff "${branch}" | grep -c "^")" -gt "0" ]; then
    update=true
  fi

  git checkout "${branch}" || return 1
  git pull || return 1
  return 0
}

warning1() {
  echo "::: Note that changing the branch is a severe change of your Pi-hole system."
  echo "::: This is not supported unless one of the developers explicitly asks you to do this!"
  read -r -p "::: Have you read and understood this? [y/N] " response
  case ${response} in
  [yY][eE][sS]|[yY])
    echo "::: Continuing."
    return 0
    ;;
  *)
    echo "::: Aborting."
    return 1
    ;;
  esac
}

checkout()
{
  local corebranches
  local webbranches

  # Avoid globbing
  set -f

  #This is unlikely
  if ! is_repo "${PI_HOLE_FILES_DIR}" ; then
    echo "::: Critical Error: Core Pi-Hole repo is missing from system!"
    echo "::: Please re-run install script from https://github.com/pi-hole/pi-hole"
    exit 1;
  fi
  if [[ ${INSTALL_WEB} ]]; then
    if ! is_repo "${webInterfaceDir}" ; then
      echo "::: Critical Error: Web Admin repo is missing from system!"
      echo "::: Please re-run install script from https://github.com/pi-hole/pi-hole"
      exit 1;
    fi
  fi

  if [[ -z "${1}" ]]; then
    echo "::: No option detected. Please use 'pihole checkout <master|dev>'."
    echo "::: Or enter the repository and branch you would like to check out:"
    echo "::: 'pihole checkout <web|core> <branchname>'"
    exit 1
  fi

  if ! warning1 ; then
    exit 1
  fi

  if [[ "${1}" == "dev" ]] ; then
    # Shortcut to check out development branches
    echo "::: Shortcut \"dev\" detected - checking out development / devel branches ..."
    echo "::: Pi-hole core"
    fetch_checkout_pull_branch "${PI_HOLE_FILES_DIR}" "development" || { echo "Unable to pull Core developement branch"; exit 1; }
    if [[ ${INSTALL_WEB} ]]; then
      echo "::: Web interface"
      fetch_checkout_pull_branch "${webInterfaceDir}" "devel" || { echo "Unable to pull Web development branch"; exit 1; }
    fi
    echo "::: done!"
  elif [[ "${1}" == "master" ]] ; then
    # Shortcut to check out master branches
    echo "::: Shortcut \"master\" detected - checking out master branches ..."
    echo "::: Pi-hole core"
    fetch_checkout_pull_branch "${PI_HOLE_FILES_DIR}" "master" || { echo "Unable to pull Core master branch"; exit 1; }
    if [[ ${INSTALL_WEB} ]]; then
      echo "::: Web interface"
      fetch_checkout_pull_branch "${webInterfaceDir}" "master" || { echo "Unable to pull web master branch"; exit 1; }
    fi
    echo "::: done!"
  elif [[ "${1}" == "core" ]] ; then
    echo -n "::: Fetching remote branches for Pi-hole core from ${piholeGitUrl} ... "
    if ! fully_fetch_repo "${PI_HOLE_FILES_DIR}" ; then
      echo "::: Fetching all branches for Pi-hole core repo failed!"
      exit 1
    fi
    corebranches=($(get_available_branches "${PI_HOLE_FILES_DIR}"))
    echo " done!"
    echo "::: ${#corebranches[@]} branches available"
    echo ":::"
    # Have to user chosing the branch he wants
    if ! (for e in "${corebranches[@]}"; do [[ "$e" == "${2}" ]] && exit 0; done); then
      echo "::: Requested branch \"${2}\" is not available!"
      echo "::: Available branches for core are:"
      for e in "${corebranches[@]}"; do echo ":::   $e"; done
      exit 1
    fi
    checkout_pull_branch "${PI_HOLE_FILES_DIR}" "${2}"
  elif [[ "${1}" == "web" && ${INSTALL_WEB} ]] ; then
    echo -n "::: Fetching remote branches for the web interface from ${webInterfaceGitUrl} ... "
    if ! fully_fetch_repo "${webInterfaceDir}" ; then
      echo "::: Fetching all branches for Pi-hole web interface repo failed!"
      exit 1
    fi
    webbranches=($(get_available_branches "${webInterfaceDir}"))
    echo " done!"
    echo "::: ${#webbranches[@]} branches available"
    echo ":::"
    # Have to user chosing the branch he wants
    if ! (for e in "${webbranches[@]}"; do [[ "$e" == "${2}" ]] && exit 0; done); then
      echo "::: Requested branch \"${2}\" is not available!"
      echo "::: Available branches for web are:"
      for e in "${webbranches[@]}"; do echo ":::   $e"; done
      exit 1
    fi
    checkout_pull_branch "${webInterfaceDir}" "${2}"
  else
    echo "::: Requested option \"${1}\" is not available!"
    exit 1
  fi

  # Force updating everything
  if [[ ! "${1}" == "web" && ${update} ]]; then
    echo "::: Running installer to upgrade your installation"
    if "${PI_HOLE_FILES_DIR}/automated install/basic-install.sh" --unattended; then
     exit 0
    else
     echo "Unable to complete update, contact Pi-hole"
     exit 1
    fi
  fi
}

