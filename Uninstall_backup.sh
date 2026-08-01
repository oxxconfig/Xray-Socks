#!/usr/bin/env bash
# =============================================================================
# Xray 节点无损全自动重装脚本（纯净还原版）
# =============================================================================

BACKUP_DIR="/tmp/xray_config_backup"
rm -rf "${BACKUP_DIR}" && mkdir -p "${BACKUP_DIR}"

echo -e "\033[33m[*]\033[0m 步骤 1/4: 备份节点核心配置..."
HAS_BACKUP=0

# 仅备份真正的 Xray 核心配置，不备份会引起排版乱码的 UI 缓存
if [ -d "/usr/local/etc/xray" ] && [ -n "$(ls -A /usr/local/etc/xray 2>/dev/null)" ]; then
    cp -aT /usr/local/etc/xray "${BACKUP_DIR}/xray"
    HAS_BACKUP=1
    echo -e "\033[32m[✓]\033[0m 节点所有关键凭据（UUID/私钥/Socks5）已成功备份！"
else
    echo -e "\033[31m[!]\033[0m 未检测到旧节点，本次将进行全新安装。"
fi

echo -e "\n\033[33m[*]\033[0m 步骤 2/4: 清理旧版本程序与环境变量..."
systemctl stop xray 2>/dev/null
systemctl disable xray 2>/dev/null
rm -rf /usr/local/bin/xray /usr/local/share/xray /usr/local/etc/xray "${HOME}/.xray-script"

echo -e "\n\033[33m[*]\033[0m 步骤 3/4: 触发一键安装脚本..."
rm -f install.sh
curl --connect-timeout 10 --retry 3 -sSO https://raw.githubusercontent.com/oxxconfig/Xray-Socks/main/install.sh
sed -i 's/\r$//' install.sh
bash install.sh --vision

# =============================================================================
# 关键还原动作：覆写核心配置 + 重置 UI 面板缓存
# =============================================================================
if [ ${HAS_BACKUP} -eq 1 ]; then
    echo -e "\n\033[33m[*]\033[0m 步骤 4/4: 正在恢复节点并重置 UI 面板..."
    systemctl stop xray 2>/dev/null
    
    # 1. 强行把备份的旧节点配置覆写回去
    cp -aT "${BACKUP_DIR}/xray" /usr/local/etc/xray
    
    # 2. 删除 UI 面板的临时缓存，强制面板读取新的 config.json 重新生成展示数据
    rm -rf "${HOME}/.xray-script"
    
    systemctl restart xray
    echo -e "\033[32m[完美成功]\033[0m 节点所有信息已恢复，面板显示已重置正常！"
    echo -e "\033[36m👉 客户端无需任何更改，直接连接即可！\033[0m"
fi
