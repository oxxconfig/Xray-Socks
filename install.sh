#!/usr/bin/env bash
# =============================================================================
# Xray 全自动部署与环境优化脚本 (生产环境稳定版 - 已锁定 v26.3.27 + 整合 IPv6 禁用)
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

# 优化系统内核、防火墙并禁用 IPv6
function init_env_optimization() {
    echo -e "${GREEN}[基础配置]${NC} 开始优化系统内核、防火墙规则并禁用 IPv6..."
    
    # 优化 BBR 与队列规则
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf

    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

    # 写入 IPv6 禁用配置
    cat > /etc/sysctl.d/99-disable-ipv6.conf << "CONF"
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
CONF

    # 刷新 sysctl 配置
    sysctl --system > /dev/null 2>&1

    # 检查 IPv6 禁用结果
    local ipv6_status
    ipv6_status=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
    if [ "$ipv6_status" = "1" ]; then
        echo -e "${GREEN}[成功]${NC} IPv6 已成功禁用！"
    else
        echo -e "${YELLOW}[提示]${NC} IPv6 禁用未能完全生效，但不影响核心运行。"
    fi

    # 防火墙 443 端口放行
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
    local packages=("ca-certificates" "openssl" "curl" "wget" "git" "jq" "tzdata" "qrencode" "socat" "unzip")
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
        local packages=("ca-certificates" "openssl" "curl" "wget" "git" "jq" "tzdata" "qrencode" "socat" "unzip" "crontabs" "util-linux" "iproute" "procps-ng" "bind-utils")
        if type dnf >/dev/null 2>&1; then
            dnf update -y && dnf install -y dnf-plugins-core
            for pkg in "${packages[@]}"; do dnf install -y "${pkg}"; done
        else
            yum update -y && yum install -y epel-release yum-utils
            for pkg in "${packages[@]}"; do yum install -y "${pkg}"; done
        fi
    else
        apt-get update -y -o Acquire::Retries=3 -o Acquire::http::Timeout=10
        
        local packages=("ca-certificates" "openssl" "curl" "wget" "git" "jq" "tzdata" "qrencode" "socat" "unzip" "cron" "iproute2" "procps" "dnsutils")
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

# 【核心修复】：强行锁定并下载 v26.3.27 稳定内核
function pre_install_xray_binary() {
    local XRAY_VERSION="v26.3.27"
    echo -e "${GREEN}[预备核心]${NC} 正在下载与旧 VPS 完全对齐的经典稳定版 Xray 核心 (${XRAY_VERSION})..."
    local _xray_tmp="/tmp/xray_install_pre"
    mkdir -p "${_xray_tmp}"
    local _arch="64"
    [[ "$(uname -m)" =~ "aarch64"|"arm64" ]] && _arch="arm64-v8a"
    
    if curl -sLo "${_xray_tmp}/xray.zip" "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${_arch}.zip"; then
        unzip -qo "${_xray_tmp}/xray.zip" -d "${_xray_tmp}"
        if [ -f "${_xray_tmp}/xray" ]; then
            install -m 755 "${_xray_tmp}/xray" /usr/local/bin/xray
            ln -sf /usr/local/bin/xray /usr/bin/xray
            echo -e "${GREEN}[✓]${NC} Xray 核心 ${XRAY_VERSION} 安装成功！"
        else
            echo -e "${RED}[错误]${NC} 解压后未找到 xray 可执行文件！"
        fi
    else
        echo -e "${RED}[错误]${NC} 下载 Xray 核心 ${XRAY_VERSION} 失败！"
    fi
    rm -rf "${_xray_tmp}"
}

function optimize_system_cron() {
    echo -e "\n${YELLOW}[系统优化]${NC} 正在清理冗余 Cron 任务与后台阻塞服务..."

    mkdir -p /var/log/xray

    rm -f /etc/cron.daily/apport \
          /etc/cron.daily/apt-compat \
          /etc/cron.daily/man-db \
          /etc/cron.weekly/man-db

    if crontab -l >/dev/null 2>&1; then
        local new_cron
        new_cron=$(crontab -l 2>/dev/null | grep -v 'geodata\.sh' || true)

        if [[ -z "${new_cron//[[:space:]]/}" ]]; then
            crontab -r 2>/dev/null || true
        else
            echo "${new_cron}" | crontab - 2>/dev/null || true
        fi
    fi

    if [ -d "/etc/cron.d" ]; then
        grep -rl 'geodata\.sh' /etc/cron.d/ 2>/dev/null | xargs rm -f 2>/dev/null || true
    fi

    systemctl stop apport 2>/dev/null || true
    systemctl disable apport 2>/dev/null || true
    systemctl disable --now systemd-networkd-wait-online.service 2>/dev/null || true

    echo -e "${GREEN}[✓]${NC} 系统 Cron 任务与 VPS 稳定性优化完成！"
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
        [[ -n "${json_payload ]] && echo "${json_payload}" >"${SCRIPT_CONFIG_PATH}"
    elif [[ -n "${script_path}" ]]; then
        PROJECT_ROOT="${script_path}"
    fi

    CORE_DIR="${PROJECT_ROOT}/core"

    # 强制清理旧配置
    echo -e "${YELLOW}[纯净重建]${NC} 清理旧配置与旧脚本，准备重新生成节点..."
    systemctl stop xray 2>/dev/null || true
    rm -rf "${PROJECT_ROOT}"
    rm -rf /usr/local/etc/xray
    rm -rf /usr/local/share/xray
    
    mkdir -p /usr/local/etc/xray
    mkdir -p /usr/local/share/xray

    # 下载最新脚本
    download_xray_script_files "${PROJECT_ROOT}"

    # 拉取完整的 zh.json 语言包
    mkdir -p "${PROJECT_ROOT}/config/xray" "${PROJECT_ROOT}/i18n"
    echo "{}" > "${PROJECT_ROOT}/config/xray/config.json"
    if ! curl -sL --connect-timeout 10 --retry 3 "https://raw.githubusercontent.com/oxxconfig/Xray-Socks/main/i18n/zh.json" -o "${PROJECT_ROOT}/i18n/zh.json"; then
        echo '{"title":{"error":"错误"},"index":{},"management":{},"config":{},"xray":{},"full":{},"route":{},"sni":{},"language":{}}' > "${PROJECT_ROOT}/i18n/zh.json"
    fi
    ln -sf "${PROJECT_ROOT}/i18n/zh.json" "${PROJECT_ROOT}/i18n/.json" 2>/dev/null || true

    # 安装锁定的 v26.3.27 核心
    pre_install_xray_binary

    # 注册 systemd 服务
    cat << 'SERVICE_EOF' > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target network-online.target nss-lookup.target
Wants=network-online.target

[Service]
User=root
ExecStartPre=/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=5s
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000
RuntimeDirectory=xray
RuntimeDirectoryMode=0755

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    rm -rf /etc/systemd/system/xray.service.d
    systemctl daemon-reload
    systemctl enable xray 2>/dev/null || true

    local json_lang
    json_lang=$(jq --arg language "zh" '.language = $language' "${SCRIPT_CONFIG_PATH}" 2>/dev/null)
    [[ -n "${json_lang}" ]] && echo "${json_lang}" >"${SCRIPT_CONFIG_PATH}"

    echo -e "${GREEN}[部署完成]${NC} 前置依赖与系统优化已就绪，正在唤起 Xray 主内核业务脚本..."
    echo "--------------------------------------------------------"
    
    if [ -n "$QUICK_INSTALL" ]; then
        bash "${CORE_DIR}/main.sh" "$QUICK_INSTALL" </dev/null
    else
        bash "${CORE_DIR}/main.sh" </dev/null
    fi

    echo -e "\n${GREEN}[看板配置]${NC} 正在挂载 Xray 全能信息看板工具..."
    curl -sS -H "Cache-Control: no-cache" -L "https://raw.githubusercontent.com/oxxconfig/Xray-Socks/main/xray-info.sh" > /usr/local/bin/xray-info 2>/dev/null
    chmod +x /usr/local/bin/xray-info

    # 生成全局快捷管理命令 `xray`
    printf '#!/usr/bin/env bash\nif [ -f "/usr/local/xray-script/core/main.sh" ]; then\n    exec bash /usr/local/xray-script/core/main.sh "$@"\nelse\n    echo "错误: 未找到 Xray 管理脚本！"\n    exit 1\nfi\n' > /usr/local/bin/xray
    chmod +x /usr/local/bin/xray

    systemctl restart xray || true

    optimize_system_cron

    if [ -x "/usr/local/bin/xray-info" ]; then
        echo ""
        /usr/local/bin/xray-info
    fi
}

main "${ORIGINAL_ARGS[@]}"
