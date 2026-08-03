#!/usr/bin/env bash
# =============================================================================
# Xray 独立无损重装脚本 (保留旧节点配置 + 恢复 xray 与 xray-info 工具)
# =============================================================================

set -e

# 1. 严格权限断言
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[31m[错误] 请使用 root 用户运行此脚本！\033[0m"
    exit 1
fi

# 2. 全局环境变量压制
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

ORIGINAL_ARGS=("$@")

readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly RED='\033[31m'
readonly NC='\033[0m'

readonly BACKUP_DIR="/tmp/xray_config_backup"
readonly SCRIPT_CONFIG_DIR="${HOME}/.xray-script"
readonly SCRIPT_CONFIG_PATH="${SCRIPT_CONFIG_DIR}/config.json"

declare PROJECT_ROOT=''
declare CORE_DIR=''
declare QUICK_INSTALL=''

function _os() {
    if [[ -f "/etc/debian_version" ]]; then
        local os_id
        os_id=$(grep -oP '^ID=\K\w+' /etc/os-release 2>/dev/null || echo "ubuntu")
        printf -- "%s" "${os_id}"
        return
    fi
    [[ -f "/etc/redhat-release" ]] && printf -- "centos" && return
    printf -- "ubuntu"
}

# 优化系统内核与防火墙
function init_env_optimization() {
    echo -e "${GREEN}[基础配置]${NC} 开始优化系统内核与防火墙规则..."
    
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf

    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

    sysctl -p >/dev/null 2>&1

    if type iptables >/dev/null 2>&1; then
        if ! iptables -L INPUT -n 2>/dev/null | grep -q "dpt:443"; then
            iptables -I INPUT -p tcp --dport 443 -j ACCEPT
            echo -e "${GREEN}[基础配置]${NC} 防火墙已放行 TCP 443 端口"
            
            if type iptables-save >/dev/null 2>&1; then
                iptables-save > /etc/iptables.rules 2>/dev/null || true
            fi
            if type netfilter-persistent >/dev/null 2>&1; then
                netfilter-persistent save >/dev/null 2>&1 || true
            fi
        fi
    fi
}

function check_dependencies() {
    local packages=("ca-certificates" "openssl" "curl" "wget" "git" "jq" "tzdata" "qrencode" "socat")
    local missing=0

    if [[ "$(_os)" == "centos" ]]; then
        packages+=("crontabs" "util-linux" "iproute" "procps-ng" "bind-utils")
        for pkg in "${packages[@]}"; do
            rpm -q "$pkg" &>/dev/null || missing=$((missing+1))
        done
    else
        if apt-cache show bsdextrautils &>/dev/null; then
            packages+=("cron" "bsdextrautils" "iproute2" "procps" "dnsutils")
        else
            packages+=("cron" "bsdmainutils" "iproute2" "procps" "dnsutils")
        fi

        for pkg in "${packages[@]}"; do
            dpkg -s "$pkg" &>/dev/null || missing=$((missing+1))
        done
    fi

    if [ $missing -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

function install_dependencies() {
    if [[ "$(_os)" == "centos" ]]; then
        local packages=("ca-certificates" "openssl" "curl" "wget" "git" "jq" "tzdata" "qrencode" "socat" "crontabs" "util-linux" "iproute" "procps-ng" "bind-utils")
        if type dnf >/dev/null 2>&1; then
            dnf update -y && dnf install -y dnf-plugins-core
            for pkg in "${packages[@]}"; do dnf install -y "${pkg}"; done
        else
            yum update -y && yum install -y epel-release yum-utils
            for pkg in "${packages[@]}"; do yum install -y "${pkg}"; done
        fi
    else
        apt-get update -y -o Acquire::Retries=3 -o Acquire::http::Timeout=10
        
        local packages=("ca-certificates" "openssl" "curl" "wget" "git" "jq" "tzdata" "qrencode" "socat" "cron" "iproute2" "procps" "dnsutils")
        if apt-cache show bsdextrautils &>/dev/null; then
            packages+=("bsdextrautils")
        else
            packages+=("bsdmainutils")
        fi
        
        for pkg in "${packages[@]}"; do
            apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" "${pkg}"
        done
    fi
}

function download_github_files() {
    local target_dir="$1"
    local github_api_url="$2"
    
    mkdir -p "${target_dir}"
    echo -e "${GREEN}[下载核心]${NC} 正在拉取：${github_api_url}"
    
    local tmp_tar="/tmp/xray_deploy_temp.tar.gz"
    local tmp_dir="/tmp/xray_deploy_extract"
    rm -rf "${tmp_tar}" "${tmp_dir}"
    
    if ! curl -sLo "${tmp_tar}" "${github_api_url}"; then
        echo -e "${RED}[错误]${NC} 下载主程序核心失败，请检查 VPS 网络！"
        exit 1
    fi
    
    mkdir -p "${tmp_dir}"
    if ! tar -xzf "${tmp_tar}" -C "${tmp_dir}" --no-same-owner 2>/dev/null; then
        echo -e "${RED}[错误]${NC} 核心包解压失败，下载的文件可能损坏或不完整！"
        rm -rf "${tmp_tar}" "${tmp_dir}"
        exit 1
    fi
    
    local root_dir
    root_dir=$(find "${tmp_dir}" -maxdepth 1 -mindepth 1 -type d | head -n 1)
    
    if [[ -n "${root_dir}" && -d "${root_dir}" ]]; then
        cp -rf "${root_dir}"/* "${target_dir}/"
    fi
    rm -rf "${tmp_tar}" "${tmp_dir}"
}

function download_xray_script_files() {
    download_github_files "$1" "https://github.com/oxxconfig/Xray-Socks/archive/refs/heads/main.tar.gz"
}

function main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --vision | --xhttp | --fallback) QUICK_INSTALL="${1}" ;;
        -d) shift; PROJECT_ROOT="${1}" ;;
        esac
        shift
    done

    # 默认指定极速安装选项（若无传参）
    if [[ -z "${QUICK_INSTALL}" ]]; then
        QUICK_INSTALL="--vision"
    fi

    # ==================== 步骤 1: 锁存现有节点配置与面板数据 ====================
    echo -e "${YELLOW}[备份锁定]${NC} 正在暂存现有的 Xray 节点与面板数据..."
    rm -rf "${BACKUP_DIR}" && mkdir -p "${BACKUP_DIR}"
    local HAS_BACKUP=0

    if [ -d "/usr/local/etc/xray" ] && [ -n "$(ls -A /usr/local/etc/xray 2>/dev/null)" ]; then
        cp -aT /usr/local/etc/xray "${BACKUP_DIR}/xray"
        HAS_BACKUP=1
    fi

    if [ -d "${SCRIPT_CONFIG_DIR}" ]; then
        cp -aT "${SCRIPT_CONFIG_DIR}" "${BACKUP_DIR}/xray-script"
    fi

    if [ ${HAS_BACKUP} -eq 1 ]; then
        echo -e "${GREEN}[✓]${NC} 现有节点配置已成功锁存，稍后将无损还原！"
    else
        echo -e "${YELLOW}[!]${NC} 未检测到旧配置，重装后将部署全新节点。"
    fi
    # =========================================================================

    init_env_optimization

    if check_dependencies; then
        echo -e "${GREEN}[基础配置]${NC} 检测到核心环境依赖已完整，跳过安装"
    else
        echo -e "${YELLOW}[基础配置]${NC} 正在补全系统核心环境依赖..."
        install_dependencies
    fi

    if [[ ! -d "${SCRIPT_CONFIG_DIR}" ]]; then mkdir -p "${SCRIPT_CONFIG_DIR}"; fi

    if [[ ! -f "${SCRIPT_CONFIG_PATH}" ]]; then
        wget --timeout=10 -O "${SCRIPT_CONFIG_PATH}" https://raw.githubusercontent.com/oxxconfig/Xray-Socks/main/config.json || \
        echo '{"version":"2026.03.17","language":"zh","path":"/usr/local/xray-script"}' > "${SCRIPT_CONFIG_PATH}"
    fi

    local script_path
    script_path="$(jq -r '.path' "${SCRIPT_CONFIG_PATH}" 2>/dev/null || echo "")"
    if [[ -z "${script_path}" && -z "${PROJECT_ROOT}" ]]; then
        PROJECT_ROOT='/usr/local/xray-script'
        local json_payload
        json_payload=$(jq --arg path "${PROJECT_ROOT}" '.path = $path' "${SCRIPT_CONFIG_PATH}" 2>/dev/null)
        [[ -n "${json_payload}" ]] && echo "${json_payload}" >"${SCRIPT_CONFIG_PATH}"
    elif [[ -n "${script_path}" ]]; then
        PROJECT_ROOT="${script_path}"
    fi

    CORE_DIR="${PROJECT_ROOT}/core"

    # 停止服务并清理旧目录
    echo -e "${YELLOW}[环境重置]${NC} 正在重置程序运行环境..."
    systemctl stop xray 2>/dev/null || true
    rm -rf "${PROJECT_ROOT}"
    rm -rf /usr/local/etc/xray
    rm -rf /usr/local/share/xray
    
    mkdir -p /usr/local/etc/xray
    mkdir -p /usr/local/share/xray

    # 拉取最新主工程脚本
    download_xray_script_files "${PROJECT_ROOT}"

    local json_lang
    json_lang=$(jq --arg language "zh" '.language = $language' "${SCRIPT_CONFIG_PATH}" 2>/dev/null)
    [[ -n "${json_lang}" ]] && echo "${json_lang}" >"${SCRIPT_CONFIG_PATH}"

    echo -e "${GREEN}[部署运行]${NC} 正在唤起 Xray 部署核心业务..."
    echo "--------------------------------------------------------"
    
    # 唤起主脚本生成环境
    bash "${CORE_DIR}/main.sh" "${QUICK_INSTALL}" </dev/null

    # ==================== 步骤 2: 强行还原旧节点配置 ====================
    if [ ${HAS_BACKUP} -eq 1 ]; then
        echo -e "\n${YELLOW}[节点恢复]${NC} 正在同步还原旧节点配置与面板数据..."
        systemctl stop xray 2>/dev/null || true

        # 还原配置
        cp -aT "${BACKUP_DIR}/xray" /usr/local/etc/xray

        # 还原面板数据缓存
        if [ -d "${BACKUP_DIR}/xray-script" ]; then
            mkdir -p "${SCRIPT_CONFIG_DIR}"
            cp -aT "${BACKUP_DIR}/xray-script" "${SCRIPT_CONFIG_DIR}"
        fi
        echo -e "${GREEN}[✓]${NC} 旧节点配置（UUID/公钥/端口）已恢复！"
    fi
    # =========================================================================

    # ==================== 步骤 3: 确保 xray 和 xray-info 全局可用 ====================
    echo -e "\n${GREEN}[看板配置]${NC} 正在挂载 Xray 全能信息看板工具..."
    curl -sS -H "Cache-Control: no-cache" -L "https://raw.githubusercontent.com/oxxconfig/Xray-Socks/main/xray-info.sh" > /usr/local/bin/xray-info 2>/dev/null
    chmod +x /usr/local/bin/xray-info

    # 1. 确保系统内核 Binary 位于 /usr/bin/xray
    if [ -f "/usr/local/bin/xray" ] && [ "$(file -b /usr/local/bin/xray | grep -i ELF)" != "" ]; then
        mv -f /usr/local/bin/xray /usr/bin/xray
    fi

    # 2. 生成全局交互命令 /usr/local/bin/xray
    printf '#!/usr/bin/env bash\nif [ -f "/usr/local/xray-script/core/main.sh" ]; then\n    exec bash /usr/local/xray-script/core/main.sh "$@"\nelse\n    echo "错误: 未找到 Xray 管理脚本！"\n    exit 1\nfi\n' > /usr/local/bin/xray
    chmod +x /usr/local/bin/xray

    # 3. 部署统一 Systemd 守护进程
    cat << 'EOF' > /etc/systemd/system/xray.service
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
EOF

    rm -rf /etc/systemd/system/xray.service.d
    systemctl daemon-reload

    # 校验配置并重新启动
    if [ -x "/usr/bin/xray" ]; then
        /usr/bin/xray run -test -config /usr/local/etc/xray/config.json || true
    fi
    systemctl enable xray >/dev/null 2>&1 || true
    systemctl restart xray 2>/dev/null || true

    # 清理临时备份
    rm -rf "${BACKUP_DIR}"

    # 唤起看板
    if [ -x "/usr/local/bin/xray-info" ]; then
        echo ""
        /usr/local/bin/xray-info
    fi
}

main "${ORIGINAL_ARGS[@]}"
