#!/usr/bin/env bash
# =============================================================================
# Xray 全自动部署与环境优化脚本 (终极修复纯净版)
# =============================================================================

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

# 3. 备份原始参数
ORIGINAL_ARGS=("$@")

readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly RED='\033[31m'
readonly NC='\033[0m'

readonly CUR_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
readonly CUR_FILE="$(basename "$0")"

readonly SCRIPT_CONFIG_DIR="${HOME}/.xray-script"
readonly SCRIPT_CONFIG_PATH="${SCRIPT_CONFIG_DIR}/config.json"

declare PROJECT_ROOT=''
declare CORE_DIR=''
declare QUICK_INSTALL=''
declare LANG_PARAM='--lang=zh'
declare FORCE_CHECK_DEPS=0

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
        else
            echo -e "${GREEN}[基础配置]${NC} 防火墙 TCP 443 端口规则已存在，跳过配置"
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

    if [[ -z "${PROJECT_ROOT}" || "${PROJECT_ROOT}" == "/" || "${PROJECT_ROOT}" == "/usr" || "${PROJECT_ROOT}" == "/root" || "${PROJECT_ROOT}" == "/home" ]]; then
        echo -e "${RED}[核心防御] 安全熔断：PROJECT_ROOT 路径异常 (${PROJECT_ROOT})，拒绝执行 rm -rf！\033[0m"
        exit 1
    fi

    CORE_DIR="${PROJECT_ROOT}/core"

    # 强制清理旧文件并拉取最新脚本
    rm -rf "${PROJECT_ROOT}"
    download_xray_script_files "${PROJECT_ROOT}"

    local json_lang
    json_lang=$(jq --arg language "zh" '.language = $language' "${SCRIPT_CONFIG_PATH}" 2>/dev/null)
    [[ -n "${json_lang}" ]] && echo "${json_lang}" >"${SCRIPT_CONFIG_PATH}"

    # ================= 核心修复点 1 =================
    # 在唤起业务脚本前，强制创建底层所需的所有目录，防止 jq 写入时报 No such file 错误
    mkdir -p /usr/local/etc/xray
    mkdir -p /usr/local/share/xray
    # ================================================

    echo -e "${GREEN}[部署完成]${NC} 前置依赖与系统优化已就绪，正在唤起 Xray 主内核业务脚本..."
    echo "--------------------------------------------------------"
    
    bash "${CORE_DIR}/main.sh" "${QUICK_INSTALL}" </dev/null

    echo -e "\n${GREEN}[看板配置]${NC} 正在挂载 Xray 全能信息看板工具..."
    curl -sS -H "Cache-Control: no-cache" -L "https://raw.githubusercontent.com/oxxconfig/Xray-Socks/main/xray-info.sh" > /usr/local/bin/xray-info 2>/dev/null
    chmod +x /usr/local/bin/xray-info

    # ================= 核心修复点 2 =================
    # 确保真正官方二进制文件存放于标准位置 /usr/bin/xray，绝不改名
    if [ -f "/usr/local/bin/xray" ] && [ "$(file -b /usr/local/bin/xray | grep -i ELF)" != "" ]; then
        mv -f /usr/local/bin/xray /usr/bin/xray
    fi

    # 生成全局菜单命令：用户直接输入 xray，呼出管理菜单
    printf '#!/usr/bin/env bash\nif [ -f "/usr/local/xray-script/core/main.sh" ]; then\n    exec bash /usr/local/xray-script/core/main.sh "$@"\nelse\n    echo "错误: 未找到 Xray 管理脚本！"\n    exit 1\nfi\n' > /usr/local/bin/xray
    chmod +x /usr/local/bin/xray

    # ================= 核心修复点 3 =================
    # 全量覆写 systemd 文件，写死 /usr/bin/xray 绝对路径，杜绝 sed 造成的 bad unit file 报错
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

    # 清理任何可能干扰的残留配置并重启守护进程
    rm -rf /etc/systemd/system/xray.service.d
    systemctl daemon-reload
    systemctl restart xray 2>/dev/null || true
    # ================================================

    # 执行并打印看板信息
    if [ -x "/usr/local/bin/xray-info" ]; then
        echo ""
        /usr/local/bin/xray-info
    fi
}

main "${ORIGINAL_ARGS[@]}"
