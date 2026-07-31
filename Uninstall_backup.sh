#!/usr/bin/env bash
# =============================================================================
# Xray 无损全自动重装脚本（强行还原旧 PBK/UUID/Socks5）
# =============================================================================

BACKUP_DIR="/tmp/xray_config_backup"
rm -rf "${BACKUP_DIR}" && mkdir -p "${BACKUP_DIR}"

echo -e "\033[33m[*]\033[0m 步骤 1/4: 锁定现有节点配置..."
HAS_BACKUP=0
if [ -d "/usr/local/etc/xray" ] && [ -n "$(ls -A /usr/local/etc/xray 2>/dev/null)" ]; then
    cp -aT /usr/local/etc/xray "${BACKUP_DIR}/xray"
    HAS_BACKUP=1
    echo -e "\033[32m[✓]\033[0m 旧节点配置已安全锁定在内存/临时区！"
else
    echo -e "\033[31m[!]\033[0m 未找到旧配置，本次将进行全新的安装。"
fi

echo -e "\n\033[33m[*]\033[0m 步骤 2/4: 清理旧版本程序..."
systemctl stop xray 2>/dev/null
systemctl disable xray 2>/dev/null
rm -rf /usr/local/bin/xray /usr/local/share/xray /usr/local/etc/xray

echo -e "\n\033[33m[*]\033[0m 步骤 3/4: 触发一键安装脚本..."
rm -f install.sh
curl --connect-timeout 10 --retry 3 -sSO https://raw.githubusercontent.com/oxxconfig/Xray-Socks/main/install.sh
sed -i 's/\r$//' install.sh
bash install.sh --vision

# =============================================================================
# 关键救场动作：在 install.sh 跑完并生成新配置后，强行把旧配置覆写回去！
# =============================================================================
if [ ${HAS_BACKUP} -eq 1 ]; then
    echo -e "\n\033[33m[*]\033[0m 步骤 4/4: 检测到旧配置，正在强制覆写还原节点..."
    systemctl stop xray 2>/dev/null
    
    # 强制将备份的配置文件还原回 Xray 目录
    cp -aT "${BACKUP_DIR}/xray" /usr/local/etc/xray
    
    # 重启 Xray 加载旧配置
    systemctl restart xray
    echo -e "\033[32m[完美成功]\033[0m 已成功抹掉 install.sh 生成的新密钥，旧节点（UUID/PBK/Socks5）已完全复原！"
    echo -e "\033[36m👉 客户端无需做任何更改，直接连接即可！\033[0m"
fi
