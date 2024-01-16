#!/usr/bin/env bash
# shellcheck disable=SC2268

# The files installed by the script conform to the Filesystem Hierarchy Standard:
# https://wiki.linuxfoundation.org/lsb/fhs

# You can set this variable whatever you want in shell session right before running this script by issuing:
# export DAT_PATH='/usr/local/share/trojan'
DAT_PATH=${DAT_PATH:-/usr/local/share/trojan}

# You can set this variable whatever you want in shell session right before running this script by issuing:
# export JSON_PATH='/usr/local/etc/trojan'
JSON_PATH=${JSON_PATH:-/usr/local/etc/trojan}

# Set this variable only if you are starting trojan with multiple configuration files:
# export JSONS_PATH='/usr/local/etc/trojan'

# Set this variable only if you want this script to check all the systemd unit file:
# export check_all_service_files='yes'

curl() {
  $(type -P curl) -L -q --retry 5 --retry-delay 10 --retry-max-time 60 "$@"
}

systemd_cat_config() {
  if systemd-analyze --help | grep -qw 'cat-config'; then
    systemd-analyze --no-pager cat-config "$@"
    echo
  else
    echo "${aoi}~~~~~~~~~~~~~~~~"
    cat "$@" "$1".d/*
    echo "${aoi}~~~~~~~~~~~~~~~~"
    echo "${red}warning: ${green}The systemd version on the current operating system is too low."
    echo "${red}warning: ${green}Please consider to upgrade the systemd or the operating system.${reset}"
    echo
  fi
}

check_if_running_as_root() {
  # If you want to run as another user, please modify $UID to be owned by this user
  if [[ "$UID" -ne '0' ]]; then
    echo "WARNING: The user currently executing this script is not root. You may encounter the insufficient privilege error."
    read -r -p "Are you sure you want to continue? [y/n] " cont_without_been_root
    if [[ x"${cont_without_been_root:0:1}" = x'y' ]]; then
      echo "Continuing the installation with current user..."
    else
      echo "Not running with root, exiting..."
      exit 1
    fi
  fi
}

identify_the_operating_system_and_architecture() {
  if [[ "$(uname)" == 'Linux' ]]; then
    case "$(uname -m)" in
      'i386' | 'i686')
        MACHINE='386'
        ;;
      'amd64' | 'x86_64')
        MACHINE='amd64'
        ;;
      'armv5tel')
        MACHINE='armv5'
        ;;
      'armv6l')
        MACHINE='armv6'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='armv5'
        ;;
      'armv7' | 'armv7l')
        MACHINE='armv7'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='armv5'
        ;;
      'armv8' | 'aarch64')
        MACHINE='armv8'
        ;;
      'mips')
        MACHINE='mips32'
        ;;
      'mipsle')
        MACHINE='mips32le'
        ;;
      'mips64')
        MACHINE='mips64'
        ;;
      'mips64le')
        MACHINE='mips64le'
        ;;
      'ppc64')
        MACHINE='ppc64'
        ;;
      'ppc64le')
        MACHINE='ppc64le'
        ;;
      'riscv64')
        MACHINE='riscv64'
        ;;
      's390x')
        MACHINE='s390x'
        ;;
      *)
        echo "error: The architecture is not supported."
        exit 1
        ;;
    esac
    if [[ ! -f '/etc/os-release' ]]; then
      echo "error: Don't use outdated Linux distributions."
      exit 1
    fi
    # Do not combine this judgment condition with the following judgment condition.
    ## Be aware of Linux distribution like Gentoo, which kernel supports switch between Systemd and OpenRC.
    if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc' /proc/1/cgroup && [[ "$(type -P systemctl)" ]]; then
      true
    elif [[ -d /run/systemd/system ]] || grep -q systemd <(ls -l /sbin/init); then
      true
    else
      echo "error: Only Linux distributions using systemd are supported."
      exit 1
    fi
    if [[ "$(type -P apt)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='apt -y --no-install-recommends install'
      PACKAGE_MANAGEMENT_REMOVE='apt purge'
      package_provide_tput='ncurses-bin'
    elif [[ "$(type -P dnf)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='dnf -y install'
      PACKAGE_MANAGEMENT_REMOVE='dnf remove'
      package_provide_tput='ncurses'
    elif [[ "$(type -P yum)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='yum -y install'
      PACKAGE_MANAGEMENT_REMOVE='yum remove'
      package_provide_tput='ncurses'
    elif [[ "$(type -P zypper)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='zypper install -y --no-recommends'
      PACKAGE_MANAGEMENT_REMOVE='zypper remove'
      package_provide_tput='ncurses-utils'
    elif [[ "$(type -P pacman)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='pacman -Syu --noconfirm'
      PACKAGE_MANAGEMENT_REMOVE='pacman -Rsn'
      package_provide_tput='ncurses'
    else
      echo "error: The script does not support the package manager in this operating system."
      exit 1
    fi
  else
    echo "error: This operating system is not supported."
    exit 1
  fi
}

## Demo function for processing parameters
judgment_parameters() {
  while [[ "$#" -gt '0' ]]; do
    case "$1" in
      '--remove')
        if [[ "$#" -gt '1' ]]; then
          echo 'error: Please enter the correct parameters.'
          exit 1
        fi
        REMOVE='1'
        ;;
      '--version')
        VERSION="${2:?error: Please specify the correct version.}"
        break
        ;;
      '-c' | '--check')
        CHECK='1'
        break
        ;;
      '-f' | '--force')
        FORCE='1'
        break
        ;;
      '-h' | '--help')
        HELP='1'
        break
        ;;
      '-l' | '--local')
        LOCAL_INSTALL='1'
        LOCAL_FILE="${2:?error: Please specify the correct local file.}"
        break
        ;;
      '-p' | '--proxy')
        if [[ -z "${2:?error: Please specify the proxy server address.}" ]]; then
          exit 1
        fi
        PROXY="$2"
        shift
        ;;
      *)
        echo "$0: unknown option -- -"
        exit 1
        ;;
    esac
    shift
  done
}

install_software() {
  package_name="$1"
  file_to_detect="$2"
  type -P "$file_to_detect" > /dev/null 2>&1 && return
  if ${PACKAGE_MANAGEMENT_INSTALL} "$package_name"; then
    echo "info: $package_name is installed."
  else
    echo "error: Installation of $package_name failed, please check your network."
    exit 1
  fi
}

get_current_version() {
  VERSION="$(/usr/local/bin/trojan-go -version | head -n 1 | awk '{print $2}' | awk -Fv '{print $2}')"
  CURRENT_VERSION="v${VERSION#v}"
}

get_version() {
  # 0: Install or update Trojan.
  # 1: Installed or no new version of Trojan.
  # 2: Install the specified version of Trojan.
  if [[ -n "$VERSION" ]]; then
    RELEASE_VERSION="v${VERSION#v}"
    return 2
  fi
  # Determine the version number for Trojan-go installed from a local file
  if [[ -f '/usr/local/bin/trojan-go' ]]; then
    get_current_version
    if [[ "$LOCAL_INSTALL" -eq '1' ]]; then
      RELEASE_VERSION="$CURRENT_VERSION"
      return
    fi
  fi
  # Get Trojan-go release version number
  TMP_FILE="$(mktemp)"
  if ! curl -x "${PROXY}" -sS -i -H "Accept: application/vnd.github.v3+json" -o "$TMP_FILE" 'https://api.github.com/repos/p4gefau1t/trojan-go/releases/latest'; then
    "rm" "$TMP_FILE"
    echo 'error: Failed to get release list, please check your network.'
    exit 1
  fi
  HTTP_STATUS_CODE=$(awk 'NR==1 {print $2}' "$TMP_FILE")
  if [[ $HTTP_STATUS_CODE -lt 200 ]] || [[ $HTTP_STATUS_CODE -gt 299 ]]; then
    "rm" "$TMP_FILE"
    echo "error: Failed to get release list, GitHub API response code: $HTTP_STATUS_CODE"
    exit 1
  fi
  RELEASE_LATEST="$(sed 'y/,/\n/' "$TMP_FILE" | grep 'tag_name' | awk -F '"' '{print $4}')"
  "rm" "$TMP_FILE"
  RELEASE_VERSION="v${RELEASE_LATEST#v}"

  # Compare Trojan-go version numbers
  if [[ "$RELEASE_VERSION" != "$CURRENT_VERSION" ]]; then
    RELEASE_VERSIONSION_NUMBER="${RELEASE_VERSION#v}"
    RELEASE_MAJOR_VERSION_NUMBER="${RELEASE_VERSIONSION_NUMBER%%.*}"
    RELEASE_MINOR_VERSION_NUMBER="$(echo "$RELEASE_VERSIONSION_NUMBER" | awk -F '.' '{print $2}')"
    RELEASE_MINIMUM_VERSION_NUMBER="${RELEASE_VERSIONSION_NUMBER##*.}"
    # shellcheck disable=SC2001
    CURRENT_VERSION_NUMBER="$(echo "${CURRENT_VERSION#v}" | sed 's/-.*//')"
    CURRENT_MAJOR_VERSION_NUMBER="${CURRENT_VERSION_NUMBER%%.*}"
    CURRENT_MINOR_VERSION_NUMBER="$(echo "$CURRENT_VERSION_NUMBER" | awk -F '.' '{print $2}')"
    CURRENT_MINIMUM_VERSION_NUMBER="${CURRENT_VERSION_NUMBER##*.}"
    if [[ "$RELEASE_MAJOR_VERSION_NUMBER" -gt "$CURRENT_MAJOR_VERSION_NUMBER" ]]; then
      return 0
    elif [[ "$RELEASE_MAJOR_VERSION_NUMBER" -eq "$CURRENT_MAJOR_VERSION_NUMBER" ]]; then
      if [[ "$RELEASE_MINOR_VERSION_NUMBER" -gt "$CURRENT_MINOR_VERSION_NUMBER" ]]; then
        return 0
      elif [[ "$RELEASE_MINOR_VERSION_NUMBER" -eq "$CURRENT_MINOR_VERSION_NUMBER" ]]; then
        if [[ "$RELEASE_MINIMUM_VERSION_NUMBER" -gt "$CURRENT_MINIMUM_VERSION_NUMBER" ]]; then
          return 0
        else
          return 1
        fi
      else
        return 1
      fi
    else
      return 1
    fi
  elif [[ "$RELEASE_VERSION" == "$CURRENT_VERSION" ]]; then
    return 1
  fi
}

download_trojan() {
  DOWNLOAD_LINK="https://github.com/p4gefau1t/trojan-go/releases/download/$RELEASE_VERSION/trojan-go-linux-$MACHINE.zip"
  echo "Downloading Trojan archive: $DOWNLOAD_LINK"
  if ! curl -x "${PROXY}" -R -H 'Cache-Control: no-cache' -o "$ZIP_FILE" "$DOWNLOAD_LINK"; then
    echo 'error: Download failed! Please check your network or try again.'
    return 1
  fi
}

decompression() {
  if ! unzip -q "$1" -d "$TMP_DIRECTORY"; then
    echo 'error: Trojan decompression failed.'
    "rm" -r "$TMP_DIRECTORY"
    echo "removed: $TMP_DIRECTORY"
    exit 1
  fi
  echo "info: Extract the Trojan package to $TMP_DIRECTORY and prepare it for installation."
}

install_file() {
  NAME="$1"
  if [[ "$NAME" == 'trojan-go' ]] || [[ "$NAME" == 'trojan' ]]; then
    install -m 755 "${TMP_DIRECTORY}/$NAME" "/usr/local/bin/$NAME"
  elif [[ "$NAME" == 'geoip.dat' ]] || [[ "$NAME" == 'geosite.dat' ]]; then
    install -m 644 "${TMP_DIRECTORY}/$NAME" "${DAT_PATH}/$NAME"
  fi
}

install_trojan() {
  # Install binary to /usr/local/bin/ and $DAT_PATH
  install_file trojan-go
  install -d "$DAT_PATH"
  # If the file exists, geoip.dat and geosite.dat will not be installed or updated
  if [[ ! -f "${DAT_PATH}/.undat" ]]; then
    install_file geoip.dat
    install_file geosite.dat
  fi

  # Install configuration file to $JSON_PATH
  # shellcheck disable=SC2153
  if [[ -z "$JSONS_PATH" ]] && [[ ! -d "$JSON_PATH" ]]; then
    install -d "$JSON_PATH"
    echo "" > "${JSON_PATH}/server.yaml"
    CONFIG_NEW='1'
  fi
}

install_startup_service_file() {
  get_current_version
  START_COMMAND="/usr/local/bin/trojan-go"
  install -m 644 "${TMP_DIRECTORY}/example/trojan-go.service" /etc/systemd/system/trojan.service
  install -m 644 "${TMP_DIRECTORY}/example/trojan-go@.service" /etc/systemd/system/trojan@.service
  mkdir -p '/etc/systemd/system/trojan.service.d'
  mkdir -p '/etc/systemd/system/trojan@.service.d/'
  if [[ -n "$JSONS_PATH" ]]; then
    "rm" -f '/etc/systemd/system/trojan.service.d/10-donot_touch_single_conf.conf' \
      '/etc/systemd/system/trojan@.service.d/10-donot_touch_single_conf.conf'
    echo "# In case you have a good reason to do so, duplicate this file in the same directory and make your customizes there.
# Or all changes you made will be lost!  # Refer: https://www.freedesktop.org/software/systemd/man/systemd.unit.html
[Service]
ExecStart=
ExecStart=${START_COMMAND} -config $JSONS_PATH" |
      tee '/etc/systemd/system/trojan.service.d/10-donot_touch_multi_conf.conf' > '/etc/systemd/system/trojan@.service.d/10-donot_touch_multi_conf.conf'
  else
    "rm" -f '/etc/systemd/system/trojan.service.d/10-donot_touch_multi_conf.conf' \
      '/etc/systemd/system/trojan@.service.d/10-donot_touch_multi_conf.conf'
    echo "# In case you have a good reason to do so, duplicate this file in the same directory and make your customizes there.
# Or all changes you made will be lost!  # Refer: https://www.freedesktop.org/software/systemd/man/systemd.unit.html
[Service]
ExecStart=
ExecStart=${START_COMMAND} -config ${JSON_PATH}/server.yaml" > '/etc/systemd/system/trojan.service.d/10-donot_touch_single_conf.conf'
    echo "# In case you have a good reason to do so, duplicate this file in the same directory and make your customizes there.
# Or all changes you made will be lost!  # Refer: https://www.freedesktop.org/software/systemd/man/systemd.unit.html
[Service]
ExecStart=
ExecStart=${START_COMMAND} -config ${JSON_PATH}/%i.yaml" > '/etc/systemd/system/trojan@.service.d/10-donot_touch_single_conf.conf'
  fi
  echo "info: Systemd service files have been installed successfully!"
  echo "${red}warning: ${green}The following are the actual parameters for the trojan service startup."
  echo "${red}warning: ${green}Please make sure the configuration file path is correctly set.${reset}"
  systemd_cat_config /etc/systemd/system/trojan.service
  # shellcheck disable=SC2154
  if [[ x"${check_all_service_files:0:1}" = x'y' ]]; then
    echo
    echo
    systemd_cat_config /etc/systemd/system/trojan@.service
  fi
  systemctl daemon-reload
  SYSTEMD='1'
}

start_trojan() {
  if [[ -f '/etc/systemd/system/trojan.service' ]]; then
    if systemctl start "${TROJAN_CUSTOMIZE:-trojan}"; then
      echo 'info: Start the Trojan service.'
    else
      echo 'error: Failed to start Trojan service.'
      exit 1
    fi
  fi
}

stop_trojan() {
  TROJAN_CUSTOMIZE="$(systemctl list-units | grep 'trojan@' | awk -F ' ' '{print $1}')"
  if [[ -z "$TROJAN_CUSTOMIZE" ]]; then
    local trojan_daemon_to_stop='trojan.service'
  else
    local trojan_daemon_to_stop="$TROJAN_CUSTOMIZE"
  fi
  if ! systemctl stop "$trojan_daemon_to_stop"; then
    echo 'error: Stopping the Trojan service failed.'
    exit 1
  fi
  echo 'info: Stop the Trojan service.'
}

check_update() {
  if [[ -f '/etc/systemd/system/trojan.service' ]]; then
    get_version
    local get_ver_exit_code=$?
    if [[ "$get_ver_exit_code" -eq '0' ]]; then
      echo "info: Found the latest release of Trojan $RELEASE_VERSION . (Current release: $CURRENT_VERSION)"
    elif [[ "$get_ver_exit_code" -eq '1' ]]; then
      echo "info: No new version. The current version of Trojan is $CURRENT_VERSION ."
    fi
    exit 0
  else
    echo 'error: Trojan is not installed.'
    exit 1
  fi
}

remove_trojan() {
  if systemctl list-unit-files | grep -qw 'trojan'; then
    if [[ -n "$(pidof trojan)" ]]; then
      stop_trojan
    fi
    if ! ("rm" -r '/usr/local/bin/trojan-go' \
      "$DAT_PATH" \
      '/etc/systemd/system/trojan.service' \
      '/etc/systemd/system/trojan@.service' \
      '/etc/systemd/system/trojan.service.d' \
      '/etc/systemd/system/trojan@.service.d'); then
      echo 'error: Failed to remove Trojan.'
      exit 1
    else
      echo 'removed: /usr/local/bin/trojan-go'
      echo "removed: $DAT_PATH"
      echo 'removed: /etc/systemd/system/trojan.service'
      echo 'removed: /etc/systemd/system/trojan@.service'
      echo 'removed: /etc/systemd/system/trojan.service.d'
      echo 'removed: /etc/systemd/system/trojan@.service.d'
      echo 'Please execute the command: systemctl disable trojan'
      echo "You may need to execute a command to remove dependent software: $PACKAGE_MANAGEMENT_REMOVE curl unzip"
      echo 'info: Trojan has been removed.'
      echo 'info: If necessary, manually delete the configuration and log files.'
      if [[ -n "$JSONS_PATH" ]]; then
        echo "info: e.g., $JSONS_PATH and /var/log/trojan/ ..."
      else
        echo "info: e.g., $JSON_PATH and /var/log/trojan/ ..."
      fi
      exit 0
    fi
  else
    echo 'error: Trojan is not installed.'
    exit 1
  fi
}

# Explanation of parameters in the script
show_help() {
  echo "usage: $0 [--remove | --version number | -c | -f | -h | -l | -p]"
  echo '  [-p address] [--version number | -c | -f]'
  echo '  --remove        Remove Trojan'
  echo '  --version       Install the specified version of Trojan, e.g., --version v0.10.6'
  echo '  -c, --check     Check if Trojan can be updated'
  echo '  -f, --force     Force installation of the latest version of Trojan'
  echo '  -h, --help      Show help'
  echo '  -l, --local     Install Trojan from a local file'
  echo '  -p, --proxy     Download through a proxy server, e.g., -p socks5://127.0.0.1:1080'
  exit 0
}

main() {
  check_if_running_as_root
  identify_the_operating_system_and_architecture
  judgment_parameters "$@"

  install_software "$package_provide_tput" 'tput'

  red=$(tput setaf 1)
  green=$(tput setaf 2)
  aoi=$(tput setaf 6)
  reset=$(tput sgr0)

  # Parameter information
  [[ "$HELP" -eq '1' ]] && show_help
  [[ "$CHECK" -eq '1' ]] && check_update
  [[ "$REMOVE" -eq '1' ]] && remove_trojan

  # Two very important variables
  TMP_DIRECTORY="$(mktemp -d)"
  ZIP_FILE="${TMP_DIRECTORY}/trojan-linux-$MACHINE.zip"

  # Install Trojan from a local file, but still need to make sure the network is available
  if [[ "$LOCAL_INSTALL" -eq '1' ]]; then
    echo 'warn: Install Trojan from a local file, but still need to make sure the network is available.'
    echo -n 'warn: Please make sure the file is valid because we cannot confirm it. (Press any key) ...'
    read -r
    install_software 'unzip' 'unzip'
    decompression "$LOCAL_FILE"
  else
    # Normal way
    install_software 'curl' 'curl'
    get_version
    NUMBER="$?"
    if [[ "$NUMBER" -eq '0' ]] || [[ "$FORCE" -eq '1' ]] || [[ "$NUMBER" -eq 2 ]]; then
      echo "info: Installing Trojan $RELEASE_VERSION for $(uname -m)"
      download_trojan
      if [[ "$?" -eq '1' ]]; then
        "rm" -r "$TMP_DIRECTORY"
        echo "removed: $TMP_DIRECTORY"
        exit 1
      fi
      install_software 'unzip' 'unzip'
      decompression "$ZIP_FILE"
    elif [[ "$NUMBER" -eq '1' ]]; then
      echo "info: No new version. The current version of Trojan is $CURRENT_VERSION ."
      exit 0
    fi
  fi

  # Determine if Trojan is running
  if systemctl list-unit-files | grep -qw 'trojan'; then
    if [[ -n "$(pidof trojan)" ]]; then
      stop_trojan
      TROJAN_RUNNING='1'
    fi
  fi

  install_trojan
  install_startup_service_file
  echo 'installed: /usr/local/bin/trojan-go'
  # If the file exists, the content output of installing or updating geoip.dat and geosite.dat will not be displayed
  if [[ ! -f "${DAT_PATH}/.undat" ]]; then
    echo "installed: ${DAT_PATH}/geoip.dat"
    echo "installed: ${DAT_PATH}/geosite.dat"
  fi
  if [[ "$CONFIG_NEW" -eq '1' ]]; then
    echo "installed: ${JSON_PATH}/server.yaml"
  fi
  if [[ "$SYSTEMD" -eq '1' ]]; then
    echo 'installed: /etc/systemd/system/trojan.service'
    echo 'installed: /etc/systemd/system/trojan@.service'
  fi
  "rm" -r "$TMP_DIRECTORY"
  echo "removed: $TMP_DIRECTORY"
  if [[ "$LOCAL_INSTALL" -eq '1' ]]; then
    get_version
  fi
  echo "info: Trojan $RELEASE_VERSION is installed."
  echo "You may need to execute a command to remove dependent software: $PACKAGE_MANAGEMENT_REMOVE curl unzip"
  if [[ "$TROJAN_RUNNING" -eq '1' ]]; then
    start_trojan
  else
    echo 'Please execute the command: systemctl enable trojan; systemctl start trojan'
  fi
}

main "$@"
