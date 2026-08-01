#!/usr/bin/env bash
# =============================================================================
# Xray 节点无损全自动重装脚本（环境变量防死锁终极版）
# =============================================================================

set -e

# 1. 强制初始化系统语言环境变量，防止 install.sh 报 null/core/main.sh 错误
export SYS_LANG="zh_CN"
export LANG="zh_CN.UTF-8"

BACKUP_DIR="/root/xray_config_backup"
XRAY_DIR="/usr/local/etc/xray"
SCRIPT_DIR="${HOME}/.xray-script"

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[36m"
RESET="\033[0m"

echo -e "${YELLOW}[*] 初始化备份目录...${RESET}"
rm -rf "${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"

# =============================================================================
# 1. 备份配置
# =============================================================================
echo -e "\n${YELLOW}[*] 步骤 1/5: 备份 Xray 核心配置...${RESET}"
HAS_BACKUP=0

if [ -f "${XRAY_DIR}/config.json" ]; then
    mkdir -p "${BACKUP_DIR}/xray"
    cp -a "${XRAY_DIR}"/*.json "${BACKUP_DIR}/xray/" 2>/dev/null || true
    HAS_BACKUP=1
    echo -e "${GREEN}[✓] Xray 核心配置备份完成${RESET}"
else
    echo -e "${RED}[!] 未发现旧节点配置，将进行全新部署${RESET}"
fi

# 备份 SSL 证书
if [ -d "/etc/ssl" ]; then
    cp -a /etc/ssl "${BACKUP_DIR}/ssl" 2>/dev/null || true
fi

# =============================================================================
# 2. 清理旧环境
# =============================================================================
echo -e "\n${YELLOW}[*] 步骤 2/5: 清理旧 Xray 核心...${RESET}"
systemctl stop xray 2>/dev/null || true
systemctl disable xray 2>/dev/null || true

rm -f /usr/local/bin/xray
rm -rf /usr/local/share/xray /usr/local/etc/xray

# =============================================================================
# 3. 重新安装（带环境变量注入）
# =============================================================================
echo -e "\n${YELLOW}[*] 步骤 3/5: 下载并重新安装 Xray 主环境...${RESET}"
rm -f install.sh

curl --connect-timeout 10 --retry 3 -sSO https://raw.githubusercontent.com/oxxconfig/Xray-Socks/main/install.sh
sed -i 's/\r$//' install.sh

# 传入环境变量并执行安装
SYS_LANG="zh_CN" bash install.sh --vision

# 强制检测核心程序是否安装成功
if [ ! -f "/usr/local/bin/xray" ]; then
    echo -e "${RED}[严重错误] install.sh 未能成功编译安装 /usr/local/bin/xray，重装中断！${RESET}"
    exit 1
fi

# =============================================================================
# 4. 恢复配置 + 重新生成面板变量
# =============================================================================
if [ "${HAS_BACKUP}" -eq 1 ]; then
    echo -e "\n${YELLOW}[*] 步骤 4/5: 恢复节点配置并修复面板公钥与语言...${RESET}"
    systemctl stop xray 2>/dev/null || true

    mkdir -p "${XRAY_DIR}"
    
    # 1. 恢复核心配置 JSON
    cp -a "${BACKUP_DIR}/xray/"*.json "${XRAY_DIR}/"

    # 2. 还原 SSL 证书
    if [ -d "${BACKUP_DIR}/ssl" ]; then
        cp -a "${BACKUP_DIR}/ssl"/* /etc/ssl/ 2>/dev/null || true
    fi

    # 3. 修复面板：锁定语言并同步重新计算的 PublicKey
    mkdir -p "${SCRIPT_DIR}"
    echo "zh_CN" > "${SCRIPT_DIR}/lang" 2>/dev/null || true
    cp -f "${XRAY_DIR}/config.json" "${SCRIPT_DIR}/config.json" 2>/dev/null || true

    PRIV_KEY=$(grep -oP '"privateKey":\s*"\K[^"]+' "${XRAY_DIR}/config.json" 2>/dev/null || true)
    if [ -n "${PRIV_KEY}" ] && [ -x "/usr/local/bin/xray" ]; then
        PUB_KEY=$(/usr/local/bin/xray x25519 -i "${PRIV_KEY}" 2>/dev/null | grep -i "Public key" | awk '{print $3}' || true)
        if [ -n "${PUB_KEY}" ]; then
            echo "${PUB_KEY}" > "${SCRIPT_DIR}/public_key" 2>/dev/null || true
            echo -e "${GREEN}[✓] 自动推算并更新恢复 PublicKey: ${PUB_KEY}${RESET}"
        fi
    fi
fi
# =============================================================================
# 5. 检查并启动
# =============================================================================
echo -e "\n${YELLOW}[*] 步骤 5/5: 检查配置合法性并启动服务...${RESET}"

/usr/local/bin/xray run -test -config "${XRAY_DIR}/config.json" || {
    echo -e "${RED}[!] Xray 配置文件语法错误！${RESET}"
    exit 1
}

systemctl daemon-reload
systemctl restart xray
sleep 2

if systemctl is-active --quiet xray; then
    echo
    echo -e "${GREEN}=================================${RESET}"
    echo -e "${GREEN}    完美成功：节点无损恢复完成   ${RESET}"
    echo -e "${GREEN}=================================${RESET}"
    echo -e "${BLUE}UUID / Reality / Socks5 均保持原样${RESET}"
    
    # ---------------------------------------------------------------------
    # 【关键修正】：恢复配置并写入公钥后，必须重新唤起看板输出最新正确链接！
    # ---------------------------------------------------------------------
    if [ -x "/usr/local/bin/xray-info" ]; then
        echo -e "\n${GREEN}[看板同步] 正在读取恢复后的配置生成最新节点链接：${RESET}"
        /usr/local/bin/xray-info
    fi
else
    echo -e "${RED}[!] Xray 启动失败，请检查日志：${RESET}"
    journalctl -u xray -n 30 --no-pager
fi
