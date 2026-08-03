cat << 'EOF' > /usr/local/bin/Uninstall_backup.sh
#!/usr/bin/env bash
# =============================================================================
# Xray 独立控制面板：备份、恢复与彻底卸载
# =============================================================================

readonly BACKUP_DIR="/var/backups/xray-backups"
readonly CONFIG_PATH="/usr/local/etc/xray/config.json"
readonly GREEN='\033[32m'
readonly RED='\033[31m'
readonly YELLOW='\033[33m'
readonly NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[错误] 请使用 root 用户运行此脚本！${NC}"
    exit 1
fi

mkdir -p "${BACKUP_DIR}"

function backup_config() {
    if [ ! -f "${CONFIG_PATH}" ]; then
        echo -e "${RED}[错误] 未检测到当前运行的 Xray 配置文件 (${CONFIG_PATH})！${NC}"
        return 1
    fi
    local file_name="xray_config_$(date +%Y%m%d_%H%M%S).json"
    cp "${CONFIG_PATH}" "${BACKUP_DIR}/${file_name}"
    echo -e "${GREEN}[成功] 配置文件已成功备份至：${BACKUP_DIR}/${file_name}${NC}"
}

function restore_config() {
    local files=($(ls "${BACKUP_DIR}"/*.json 2>/dev/null))
    if [ ${#files[@]} -eq 0 ]; then
        echo -e "${RED}[错误] 备份目录 ${BACKUP_DIR} 中没有找到任何备份文件！${NC}"
        return 1
    fi

    echo -e "${YELLOW}请选择要恢复的备份文件：${NC}"
    for i in "${!files[@]}"; do
        echo "  [$((i+1))] $(basename "${files[$i]}")"
    done

    read -rp "输入序号: " choice
    if [[ "$choice" -ge 1 && "$choice" -le "${#files[@]}" ]]; then
        local target="${files[$((choice-1))]}"
        mkdir -p /usr/local/etc/xray
        cp "${target}" "${CONFIG_PATH}"
        systemctl restart xray
        echo -e "${GREEN}[成功] 已成功恢复配置并重启 Xray 服务！${NC}"
    else
        echo -e "${RED}[错误] 无效选择！${NC}"
    fi
}

function uninstall_xray() {
    read -rp "确定要彻底卸载 Xray 及其所有服务配置吗？[y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        systemctl stop xray 2>/dev/null || true
        systemctl disable xray 2>/dev/null || true
        
        # 卸载服务和路径
        rm -f /etc/systemd/system/xray.service
        systemctl daemon-reload
        
        rm -rf /usr/local/etc/xray
        rm -rf /usr/local/share/xray
        rm -rf /usr/local/xray-script
        rm -rf ~/.xray-script
        rm -f /usr/bin/xray
        rm -f /usr/local/bin/xray
        rm -f /usr/local/bin/xray-info
        
        echo -e "${GREEN}[成功] Xray 节点及相关所有脚本已清理完毕！${NC}"
    else
        echo -e "${YELLOW}已取消卸载。${NC}"
    fi
}

echo -e "${GREEN}=== Xray 独立管理面板 (备份/恢复/卸载) ===${NC}"
echo " 1. 备份当前 Xray 节点配置"
echo " 2. 从已有备份中恢复配置"
echo " 3. 彻底卸载 Xray 及脚本组件"
echo " 0. 退出"
read -rp "请选择操作 [0-3]: " opt

case "$opt" in
    1) backup_config ;;
    2) restore_config ;;
    3) uninstall_xray ;;
    *) exit 0 ;;
esac
EOF

chmod +x /usr/local/bin/Uninstall_backup.sh
