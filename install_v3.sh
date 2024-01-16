#!/usr/bin/env bash
set -e

cd "$(
  cd "$(dirname "$0")" || exit
  pwd
)" || exit

Green="\033[32m"
Red="\033[31m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"
OK="${Green}[OK]${Font}"
Error="${Red}[错误]${Font}"

ME=$(basename $0)
shell_dir="$(pwd)"
trojan_conf_dir=/etc/trojan
trojan_conf="${trojan_conf_dir}/server.yaml"
env_conf="${shell_dir}/.env"
install_lock_conf="${shell_dir}/.install.lock"
random_num=$((RANDOM % 12 + 4))
uuid=$(cat /proc/sys/kernel/random/uuid)
source '/etc/os-release'
VERSION=$(echo "${VERSION}" | awk -F "[()]" '{print $2}')

# Load environment variables
if ! [ -f "${env_conf}" ]; then
  echo "error: .env file not found. [${env_conf}]"
  exit 1
fi
export $(xargs < "${env_conf}")

curl() {
  $(type -P curl) -L -q --retry 5 --retry-delay 10 --retry-max-time 60 "$@"
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
        MACHINE='32'
        ;;
      'amd64' | 'x86_64')
        MACHINE='64'
        ;;
      'armv5tel')
        MACHINE='arm32-v5'
        ;;
      'armv6l')
        MACHINE='arm32-v6'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
        ;;
      'armv7' | 'armv7l')
        MACHINE='arm32-v7a'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
        ;;
      'armv8' | 'aarch64')
        MACHINE='arm64-v8a'
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
    ### Refer: https://github.com/v2fly/fhs-install-v2ray/issues/84#issuecomment-688574989
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
    elif [[ "$(type -P dnf)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='dnf -y install'
      PACKAGE_MANAGEMENT_REMOVE='dnf remove'
    elif [[ "$(type -P yum)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='yum -y install'
      PACKAGE_MANAGEMENT_REMOVE='yum remove'
    elif [[ "$(type -P zypper)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='zypper install -y --no-recommends'
      PACKAGE_MANAGEMENT_REMOVE='zypper remove'
    elif [[ "$(type -P pacman)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='pacman -Syu --noconfirm'
      PACKAGE_MANAGEMENT_REMOVE='pacman -Rsn'
    else
      echo "error: The script does not support the package manager in this operating system."
      exit 1
    fi
  else
    echo "error: This operating system is not supported."
    exit 1
  fi
}

check_if_exists_lock_file() {
  if [ -f "${install_lock_conf}" ]; then
    echo "error: .install.lock file already exists. Please remove it and try again."
    exit 1
  fi
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

install_acme(){
  install_software 'socat' 'socat'
  if [ -f "/root/.acme.sh/acme.sh" ]; then
    echo "info: acme is installed."
  else
    curl https://get.acme.sh | sh -s email="${TLSMAIL}" --home="/root/.acme.sh"
  fi
}

install_trojan(){
  echo 'Installing trojan..'
  export JSON_PATH="${trojan_conf_dir}"
  bash <(curl -L https://raw.githubusercontent.com/chinayin/v2ray_install/master/fhs-install-trojan/install-release.sh)
  systemctl enable trojan
}

update_trojan_config(){
  cat > "${trojan_conf}" <<EOF
run-type: server
local-addr: 0.0.0.0
local-port: 12308
remote-addr: ${PROXY_REMOTE_ADDR}
remote-port: ${PROXY_REMOTE_PORT:-443}
password:
  - ${uuid}
ssl:
  cert: ${trojan_conf_dir}/server.crt
  key: ${trojan_conf_dir}/server.key
  sni: ${DOMAIN}
router:
  enabled: true
  block:
    - 'geoip:private'
  geoip: /usr/local/share/trojan/geoip.dat
  geosite: /usr/local/share/trojan/geosite.dat
EOF
}

issue_domain() {
  echo "Issue domain: $DOMAIN"
  "/root/.acme.sh"/acme.sh --issue --dns dns_ali -d "$DOMAIN" --cert-file "${trojan_conf_dir}/server.crt" --key-file "${trojan_conf_dir}/server.key"
  chmod 755 ${trojan_conf_dir}/server.crt ${trojan_conf_dir}/server.key
}

save_lock_file() {
  cat > "${install_lock_conf}" <<EOF
uuid: ${uuid}
sni: ${DOMAIN}
time: $(date +"%Y-%m-%dT%H:%M:%S%Z")
EOF
}

remove_lock_file() {
  rm -f "${install_lock_conf}"
}

show_lock_file() {
  echo -e "\n\nTrojan configuration:\n"
  cat "${install_lock_conf}"
}

show_help() {
  echo "usage: $0 [--remove | --version number | -c | -f | -h | -l | -p]"
  echo '  [-p address] [--version number | -c | -f]'
  echo '  --remove        Remove Trojan'
  echo '  --version       Install the specified version of Trojan, e.g., --version v0.10.6'
  echo '  -c, --check     Check if Trojan can be updated'
  echo '  -f, --force     Force installation of the latest version of Trojan'
  echo '  -h, --help      Show help'
  echo '  -l, --local     Install Trojan from a local file'
  echo '  -p, --proxy     Download through a proxy server, e.g., -p http://127.0.0.1:8118 or -p socks5://127.0.0.1:1080'
  exit 0
}

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

main() {
  check_if_running_as_root
  identify_the_operating_system_and_architecture
  judgment_parameters "$@"

  # Parameter information
  [[ "$HELP" -eq '1' ]] && show_help
#  [[ "$CHECK" -eq '1' ]] && check_update
#  [[ "$REMOVE" -eq '1' ]] && remove_v2ray
  [[ "$FORCE" -eq '1' ]] && remove_lock_file

  check_if_exists_lock_file

  TMP_DIRECTORY="$(mktemp -d)"

  install_software 'curl' 'curl'
  install_software 'unzip' 'unzip'

  install_acme
  install_trojan

  update_trojan_config
  issue_domain

  save_lock_file
  show_lock_file
}

main "$@"

