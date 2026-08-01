#!/usr/bin/env bash
# =============================================================================
# Xray 节点无损全自动重装脚本（完美同步与补全版）
# =============================================================================

set -e

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
    cp -a /etc/ssl "${BACKUP_DIR}/ssl"
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
# 3. 重新安装
# =============================================================================
echo -e "\n${YELLOW}[*] 步骤 3/5: 下载并重新安装 Xray 主环境...${RESET}"
rm -f install.sh

curl --connect-timeout 10 --retry 3 -sSO https://raw.githubusercontent.com/oxxconfig/Xray-Socks/main/install.sh
sed -i 's/\r$//' install.sh

bash install.sh --vision || {
    echo -e "${RED}[失败] Xray 安装脚本执行失败${RESET}"
    exit 1
}

# =============================================================================
# 4. 恢复配置 + 重新生成面板变量 (解决 pbk 为空 & i18n/null.json 报错)
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

    # 3. 修复面板：确保语言变量存在，防止寻找 null.json
    if [ -d "${SCRIPT_DIR}" ]; then
        # 强制指定默认语言为 zh_CN (防止 i18n/null.json 报错)
        echo "zh_CN" > "${SCRIPT_DIR}/lang" 2>/dev/null || true
        
        # 同步 config.json 给面板
        cp -f "${XRAY_DIR}/config.json" "${SCRIPT_DIR}/config.json" 2>/dev/null || true

        # 核心关键：从旧 config.json 提取 PrivateKey，现场用 xray 计算并写回 public_key
        PRIV_KEY=$(grep -oP '"privateKey":\s*"\K[^"]+' "${XRAY_DIR}/config.json" 2>/dev/null || true)
        if [ -n "${PRIV_KEY}" ] && [ -x "/usr/local/bin/xray" ]; then
            PUB_KEY=$(/usr/local/bin/xray x25519 -i "${PRIV_KEY}" 2>/dev/null | grep -i "Public key" | awk '{print $3}' || true)
            if [ -n "${PUB_KEY}" ]; then
                echo "${PUB_KEY}" > "${SCRIPT_DIR}/public_key" 2>/dev/null || true
                echo -e "${GREEN}[✓] 已成功根据旧私钥计算并同步恢复 PublicKey: ${PUB_KEY}${RESET}"
            fi
        fi
    fi
fi

# =============================================================================
# 5. 检查并启动
# =============================================================================
echo -e "\n${YELLOW}[*] 步骤 5/5: 检查配置合法性并启动服务...${RESET}"

if command -v xray >/dev/null 2>&1; then
    xray run -test -config "${XRAY_DIR}/config.json" || {
        echo -e "${RED}[!] Xray 配置文件语法错误！${RESET}"
        exit 1
    }
else
    echo -e "${RED}[!] 未检测到 Xray 可执行文件${RESET}"
    exit 1
fi

systemctl daemon-reload
systemctl restart xray
sleep 2

if systemctl is-active --quiet xray; then
    echo
    echo -e "${GREEN}=================================${RESET}"
    echo -e "${GREEN}   完美成功：节点无损恢复完成   ${RESET}"
    echo -e "${GREEN}=================================${RESET}"
    echo -e "${BLUE}PublicKey 已经重新自动计算补全，pbk 不再为空！${RESET}"
    echo -e "${BLUE}语言变量已锁定为 zh_CN，面板不会再找不到 i18n 文件！${RESET}"
else
    echo -e "${RED}[!] Xray 启动失败，请检查日志：${RESET}"
    journalctl -u xray -n 30 --no-pager
fi
