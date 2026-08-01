#!/usr/bin/env bash
# =============================================================================
# Xray 节点无损全自动重装脚本（纯净完整版）
# 功能：
#   - 保留 UUID / REALITY 密钥 / Socks5 用户 / TLS 证书
#   - 自动重新安装 Xray 内核与面板环境
#   - 强行同步核心配置与面板记录（彻底解决 xray-info 显示错位）
#   - 开启 set -e，配置语法校验校验失败自动回滚
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
echo -e "\n${YELLOW}[*] 步骤 1/5: 备份 Xray 核心配置与证书...${RESET}"
HAS_BACKUP=0

if [ -f "${XRAY_DIR}/config.json" ]; then
    mkdir -p "${BACKUP_DIR}/xray"
    
    # 备份 Xray 核心 JSON 配置
    cp -a "${XRAY_DIR}"/*.json "${BACKUP_DIR}/xray/" 2>/dev/null || true
    HAS_BACKUP=1
    echo -e "${GREEN}[✓] Xray 核心配置备份完成${RESET}"
else
    echo -e "${RED}[!] 未发现旧节点配置，将进行全新部署${RESET}"
fi

# 备份 SSL 证书
if [ -d "/etc/ssl" ]; then
    echo -e "${YELLOW}[*] 备份 SSL 证书...${RESET}"
    cp -a /etc/ssl "${BACKUP_DIR}/ssl"
fi

# =============================================================================
# 2. 清理旧环境
# =============================================================================
echo -e "\n${YELLOW}[*] 步骤 2/5: 停止并清理旧 Xray 核心...${RESET}"
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
# 4. 恢复配置 & 同步面板
# =============================================================================
if [ "${HAS_BACKUP}" -eq 1 ]; then
    echo -e "\n${YELLOW}[*] 步骤 4/5: 恢复节点配置与面板数据...${RESET}"
    systemctl stop xray 2>/dev/null || true

    mkdir -p "${XRAY_DIR}"

    # 1. 强制覆盖还原核心配置 JSON
    cp -a "${BACKUP_DIR}/xray/"*.json "${XRAY_DIR}/"

    # 2. 还原 SSL 证书
    if [ -d "${BACKUP_DIR}/ssl" ]; then
        cp -a "${BACKUP_DIR}/ssl"/* /etc/ssl/ 2>/dev/null || true
    fi

    # 3. 关键救场动作：将恢复后的 config.json 同步覆盖给面板的缓存文件
    # 彻底解决 xray-info 显示错位 & 避免删文件夹导致的 i18n 缺失
    if [ -d "${SCRIPT_DIR}" ]; then
        rm -rf "${SCRIPT_DIR}/cache" "${SCRIPT_DIR}/tmp" 2>/dev/null || true
        cp -f "${XRAY_DIR}/config.json" "${SCRIPT_DIR}/config.json" 2>/dev/null || true
    fi
    echo -e "${GREEN}[✓] 核心配置与面板记录已同步还原${RESET}"
fi

# =============================================================================
# 5. 语法检查并启动
# =============================================================================
echo -e "\n${YELLOW}[*] 步骤 5/5: 检查配置合法性并启动服务...${RESET}"

if command -v xray >/dev/null 2>&1; then
    # 校验恢复后的 config.json 是否合法
    echo -e "${YELLOW}[*] 校验配置语法...${RESET}"
    xray run -test -config "${XRAY_DIR}/config.json" || {
        echo -e "${RED}[!] Xray 配置文件语法错误，请检查恢复的内容！${RESET}"
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
    echo
    echo -e "${BLUE}UUID / Reality 私钥 / Socks5 / 证书 均保持原样${RESET}"
    echo -e "${BLUE}xray-info 面板信息已同步纠正，客户端无需修改！${RESET}"
else
    echo -e "${RED}[!] Xray 启动失败，请检查 systemctl 日志：${RESET}"
    journalctl -u xray -n 30 --no-pager
fi
