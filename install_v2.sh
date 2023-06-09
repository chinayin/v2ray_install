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
v2ray_conf_dir=/etc/v2ray
caddy_conf_dir=/etc/caddy
v2ray_conf="${v2ray_conf_dir}/config.json"
caddy_conf="${caddy_conf_dir}/Caddyfile"
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

install_caddy(){
  apt install -y debian-keyring debian-archive-keyring apt-transport-https
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
  apt update

  install_software 'caddy' 'caddy'
}

install_v2ray(){
  echo 'Installing v2ray..'
  export JSON_PATH="${v2ray_conf_dir}"
  bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
  systemctl enable v2ray
}

update_v2ray_config(){
  cat > "${v2ray_conf}" <<EOF
{
  "log": {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "warn"
  },
  "inbounds": [
    {
      "port": 10000,
      "tag": "vmess-in",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${WS_PATH}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    }
  ],
  "dns": {
    "servers": [
      "https+local://1.1.1.1/dns-query",
      "8.8.8.8",
      "localhost"
    ]
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "inboundTag": [
          "vmess-in"
        ],
        "outboundTag": "direct"
      }
    ]
  }
}
EOF
}

update_caddy_config(){
  cat > "${caddy_conf}" <<EOF
{
  admin off
  log {
    output stdout
  }
}
${DOMAIN} {
  encode gzip
  tls ${TLSMAIL} {
    protocols tls1.2 tls1.3
    ciphers TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256
    curves x25519
  }
  @websockets {
    header Connection *Upgrade*
    header Upgrade websocket
  }
  handle @websockets {
    reverse_proxy 127.0.0.1:10000
  }
  handle {
    reverse_proxy ${PROXY_HOST} {
      trusted_proxies 0.0.0.0/0
      header_up Host {upstream_hostport}
    }
  }
}
EOF
}

save_lock_file() {
  cat > "${install_lock_conf}" <<EOF
uuid: "${uuid}"
domain: "${DOMAIN}"
ws_path: ${WS_PATH}"
time: $(date +"%Y-%m-%dT%H:%M:%SZ")
EOF
}

remove_lock_file() {
  rm -f "${install_lock_conf}"
}

show_lock_file() {
  echo -e "\n\n\nV2Ray configuration:"
  cat "${install_lock_conf}"
}

show_help() {
  echo "usage: $0 [--remove | --version number | -c | -f | -h | -l | -p]"
  echo '  [-p address] [--version number | -c | -f]'
  echo '  --remove        Remove V2Ray'
  echo '  --version       Install the specified version of V2Ray, e.g., --version v4.18.0'
  echo '  -c, --check     Check if V2Ray can be updated'
  echo '  -f, --force     Force installation of the latest version of V2Ray'
  echo '  -h, --help      Show help'
  echo '  -l, --local     Install V2Ray from a local file'
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

  install_software "$package_provide_tput" 'tput'
  red=$(tput setaf 1)
  green=$(tput setaf 2)
  aoi=$(tput setaf 6)
  reset=$(tput sgr0)

  # Parameter information
  [[ "$HELP" -eq '1' ]] && show_help
#  [[ "$CHECK" -eq '1' ]] && check_update
#  [[ "$REMOVE" -eq '1' ]] && remove_v2ray
  [[ "$FORCE" -eq '1' ]] && remove_lock_file

  check_if_exists_lock_file

  TMP_DIRECTORY="$(mktemp -d)"

  install_software 'curl' 'curl'
  install_software 'unzip' 'unzip'

  install_caddy
  install_v2ray

  update_v2ray_config
  update_caddy_config

  save_lock_file
  show_lock_file
}

main "$@"
