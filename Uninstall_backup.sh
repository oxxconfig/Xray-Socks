#!/usr/bin/env bash
# =============================================================================
# Xray 纯净无损清理脚本（保留节点/Socks5 配置）
# =============================================================================

echo -e "\033[33m[*]\033[0m 正在备份现有节点与 Socks5 配置文件..."

# 0. 建立临时备份目录
BACKUP_DIR="/tmp/xray_config_backup"
rm -rf "${BACKUP_DIR}" && mkdir -p "${BACKUP_DIR}"

# 备份核心配置文件
HAS_BACKUP=0
if [ -f "/usr/local/etc/xray/config.json" ]; then
    cp -f /usr/local/etc/xray/config.json "${BACKUP_DIR}/config.json"
    HAS_BACKUP=1
    echo -e "\033[32m[✓]\033[0m 核心配置文件已安全备份至 ${BACKUP_DIR}/config.json"
else
    echo -e "\033[31m[!]\033[0m 未找到原 config.json，将进行全新清理"
fi

# 备份脚本自身的记录数据
if [ -d "${HOME}/.xray-script" ]; then
    cp -rf "${HOME}/.xray-script" "${BACKUP_DIR}/.xray-script"
fi

echo -e "\033[33m[*]\033[0m 开始清理旧服务与文件环境..."

# 1. 停止并禁用 xray 相关的系统服务
systemctl stop xray xray-script 2>/dev/null
systemctl disable xray xray-script 2>/dev/null

# 2. 清理系统服务文件
rm -f /etc/systemd/system/xray.service /etc/systemd/system/xray-script.service
systemctl daemon-reload

# 3. 清理二进制文件、脚本目录及日志
rm -rf /usr/local/xray-script \
       /usr/local/bin/xray \
       /usr/local/bin/xray-bin \
       /usr/local/bin/xray-info \
       /usr/local/etc/xray \
       /usr/local/share/xray \
       /var/log/xray \
       ~/.xray-script

# 4. 清理快捷别名
sed -i '/alias xray=/d' ~/.bashrc ~/.zshrc ~/.profile 2>/dev/null
rm -f /etc/profile.d/xray.sh
hash -r 2>/dev/null || true

# =============================================================================
# 关键修复点：预先还原配置文件目录，防止重装时生成新 ID
# =============================================================================
if [ ${HAS_BACKUP} -eq 1 ]; then
    mkdir -p /usr/local/etc/xray
    cp -f "${BACKUP_DIR}/config.json" /usr/local/etc/xray/config.json
    
    if [ -d "${BACKUP_DIR}/.xray-script" ]; then
        cp -rf "${BACKUP_DIR}/.xray-script" "${HOME}/.xray-script"
    fi
    echo -e "\033[32m[✓]\033[0m 已将原 config.json 与 ID 配置提前归位！下一次运行 install.sh 将直接复用原节点信息。"
fi

echo -e "\033[32m[完成] Xray 环境已清理完毕！\033[0m"
