cat << 'EOF' > install.sh
#!/usr/bin/env bash
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[31m[错误] 请使用 root 用户运行此脚本！\033[0m"
    exit 1
fi
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH
ORIGINAL_ARGS=("$@")
readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly RED='\033[31m'
readonly NC='\033[0m'
readonly SCRIPT_CONFIG_DIR="${HOME}/.xray-script"
readonly SCRIPT_CONFIG_PATH="${SCRIPT_CONFIG_DIR}/config.json"
declare PROJECT_ROOT=''
declare CORE_DIR=''
declare QUICK_INSTALL=''

function init_env_optimization() {
    echo -e "${GREEN}[基础配置]${NC} 正在优化系统内核与防火墙..."
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    if type iptables >/dev/null 2>&1; then
        if ! iptables -L INPUT -n 2>/dev/null | grep -q "dpt:443"; then
            iptables -I INPUT -p tcp --dport 443 -j ACCEPT
            iptables-save > /etc/iptables.rules 2>/dev/null || true
        fi
    fi
}

function install_dependencies() {
    echo -e "${YELLOW}[基础配置]${NC} 正在更新依赖 (含 unzip)..."
    killall apt apt-get dpkg 2>/dev/null || true
    rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock* 2>/dev/null || true
    dpkg --configure -a 2>/dev/null || true
    apt-get update -y -o Acquire::Retries=3 -o Acquire::http::Timeout=10
    local packages=("ca-certificates" "openssl" "curl" "wget" "git" "jq" "tzdata" "qrencode" "socat" "cron" "iproute2" "procps" "dnsutils" "unzip")
    if apt-cache show bsdextrautils &>/dev/null; then
        packages+=("bsdextrautils")
    else
        packages+=("bsdmainutils")
    fi
    for pkg in "${packages[@]}"; do
        apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" "${pkg}"
    done
}

function download_github_files() {
    local target_dir="$1"
    local github_api_url="$2"
    mkdir -p "${target_dir}"
    local tmp_tar="/tmp/xray_deploy_temp.tar.gz"
    local tmp_dir="/tmp/xray_deploy_extract"
    rm -rf "${tmp_tar}" "${tmp_dir}"
    curl -sLo "${tmp_tar}" "${github_api_url}" || exit 1
    mkdir -p "${tmp_dir}"
    tar -xzf "${tmp_tar}" -C "${tmp_dir}" --no-same-owner 2>/dev/null
    local root_dir
    root_dir=$(find "${tmp_dir}" -maxdepth 1 -mindepth 1 -type d | head -n 1)
    if [[ -n "${root_dir}" && -d "${root_dir}" ]]; then
        cp -rf "${root_dir}"/* "${target_dir}/"
    fi
    rm -rf "${tmp_tar}" "${tmp_dir}"
}

function main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --vision | --xhttp | --fallback) QUICK_INSTALL="${1}" ;;
        -d) shift; PROJECT_ROOT="${1}" ;;
        esac
        shift
    done
    init_env_optimization
    install_dependencies
    mkdir -p "${SCRIPT_CONFIG_DIR}"
    echo '{"version":"2026.03.17","language":"zh","path":"/usr/local/xray-script"}' > "${SCRIPT_CONFIG_PATH}"
    PROJECT_ROOT='/usr/local/xray-script'
    CORE_DIR="${PROJECT_ROOT}/core"
    systemctl stop xray 2>/dev/null || true
    rm -rf "${PROJECT_ROOT}" /usr/local/etc/xray /usr/local/share/xray
    mkdir -p /usr/local/etc/xray /usr/local/share/xray
    download_github_files "${PROJECT_ROOT}" "https://github.com/oxxconfig/Xray-Socks/archive/refs/heads/main.tar.gz"
    
    local _xray_tmp="/tmp/xray_install_pre"
    mkdir -p "${_xray_tmp}"
    local _arch="64"
    [[ "$(uname -m)" =~ "aarch64"|"arm64" ]] && _arch="arm64-v8a"
    if curl -sLo "${_xray_tmp}/xray.zip" "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${_arch}.zip"; then
        unzip -qo "${_xray_tmp}/xray.zip" -d "${_xray_tmp}"
        [ -f "${_xray_tmp}/xray" ] && install -m 755 "${_xray_tmp}/xray" /usr/bin/xray
    fi
    rm -rf "${_xray_tmp}"

    if [ -n "${QUICK_INSTALL}" ]; then
        bash "${CORE_DIR}/main.sh" "${QUICK_INSTALL}" </dev/null
    else
        bash "${CORE_DIR}/main.sh" </dev/null
    fi

    cat << 'SERVICE_EOF' > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000
RuntimeDirectory=xray
RuntimeDirectoryMode=0755

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    systemctl daemon-reload
    systemctl enable xray 2>/dev/null || true
    systemctl restart xray 2>/dev/null || true
    [ -x "/usr/local/bin/xray-info" ] && /usr/local/bin/xray-info
}
main "${ORIGINAL_ARGS[@]}"
EOF

bash install.sh --vision
