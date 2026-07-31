#!/usr/bin/env bash
# =============================================================================
# Xray 无损全自动重装脚本（完全同步核心配置 + 面板缓存）
# =============================================================================

BACKUP_DIR="/tmp/xray_config_backup"
rm -rf "${BACKUP_DIR}" && mkdir -p "${BACKUP_DIR}"

echo -e "\033[33m[*]\033[0m 步骤 1/4: 锁定现有节点配置与面板数据..."
HAS_BACKUP=0

# 1. 备份 Xray 核心配置目录
if [ -d "/usr/local/etc/xray" ] && [ -n "$(ls -A /usr/local/etc/xray 2>/dev/null)" ]; then
    cp -aT /usr/local/etc/xray "${BACKUP_DIR}/xray"
    HAS_BACKUP=1
fi

# 2. 备份面板缓存记录目录（确保 xray-info 显示数据不混乱）
if [ -d "${HOME}/.xray-script" ]; then
    cp -aT "${HOME}/.xray-script" "${BACKUP_DIR}/xray-script"
fi

if [ ${HAS_BACKUP} -eq 1 ]; then
    echo -e "\033[32m[✓]\033[0m 旧节点配置与面板数据已成功锁定！"
else
    echo -e "\033[31m[!]\033[0m 未找到旧配置，本次将进行全新部署。"
fi

echo -e "\n\033[33m[*]\033[0m 步骤 2/4: 清理旧版本程序..."
systemctl stop xray 2>/dev/null
systemctl disable xray 2>/dev/null
rm -rf /usr/local/bin/xray /usr/local/share/xray /usr/local/etc/xray "${HOME}/.xray-script"

echo -e "\n\033[33m[*]\033[0m 步骤 3/4: 触发一键安装脚本..."
rm -f install.sh
curl --connect-timeout 10 --retry 3 -sSO https://raw.githubusercontent.com/oxxconfig/Xray-Socks/main/install.sh
sed -i 's/\r$//' install.sh
bash install.sh --vision

# =============================================================================
# 关键还原动作：同时还原核心配置 + 面板记录
# =============================================================================
if [ ${HAS_BACKUP} -eq 1 ]; then
    echo -e "\n\033[33m[*]\033[0m 步骤 4/4: 强制同步还原旧节点与面板信息..."
    systemctl stop xray 2>/dev/null
    
    # 还原 Xray 配置
    cp -aT "${BACKUP_DIR}/xray" /usr/local/etc/xray
    
    # 还原面板数据缓存
    if [ -d "${BACKUP_DIR}/xray-script" ]; then
        mkdir -p "${HOME}/.xray-script"
        cp -aT "${BACKUP_DIR}/xray-script" "${HOME}/.xray-script"
    fi
    
    systemctl restart xray
    echo -e "\033[32m[完美成功]\033[0m 旧节点及面板信息（UUID/PBK/Socks5）已全部同步复原！"
    echo -e "\033[36m👉 客户端无需做任何更改，xray-info 亦已恢复旧公钥显示！\033[0m"
fi
