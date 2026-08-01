#!/usr/bin/env bash
# =============================================================================
# Xray 节点无损全自动重装脚本
# 修复版：解决 xray-script-temp / null 自更新死锁问题
# =============================================================================


set -e


# ===============================
# 环境初始化
# ===============================

export HOME=/root
export SYS_LANG="zh_CN"
export LANG="zh_CN.UTF-8"
export LC_ALL="zh_CN.UTF-8"


BACKUP_DIR="/root/xray_config_backup"
XRAY_DIR="/usr/local/etc/xray"
SCRIPT_DIR="/root/.xray-script"


GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[36m"
RESET="\033[0m"



echo -e "${YELLOW}[*] 初始化备份环境...${RESET}"


# 保留旧备份

if [ -d "${BACKUP_DIR}" ]; then

    mv "${BACKUP_DIR}" \
    "${BACKUP_DIR}_$(date +%Y%m%d_%H%M%S)"

fi


mkdir -p "${BACKUP_DIR}"



# ===============================
# 1. 备份
# ===============================


echo
echo -e "${YELLOW}[*] 步骤 1/5: 备份节点数据...${RESET}"


HAS_BACKUP=0



# Xray配置

if [ -f "${XRAY_DIR}/config.json" ]; then


mkdir -p "${BACKUP_DIR}/xray"


cp -a "${XRAY_DIR}"/*.json \
"${BACKUP_DIR}/xray/" \
2>/dev/null || true


HAS_BACKUP=1


echo -e "${GREEN}[✓] Xray配置已备份${RESET}"


fi



# SSL

if [ -d /etc/ssl ]; then

cp -a /etc/ssl \
"${BACKUP_DIR}/ssl" \
2>/dev/null || true

fi



# 面板数据

if [ -d "${SCRIPT_DIR}" ]; then


cp -a "${SCRIPT_DIR}" \
"${BACKUP_DIR}/xray-script"


fi



# ===============================
# 2. 清理
# ===============================


echo
echo -e "${YELLOW}[*] 步骤 2/5: 清理旧环境...${RESET}"



systemctl stop xray 2>/dev/null || true

systemctl disable xray 2>/dev/null || true



rm -f /usr/local/bin/xray


rm -rf \
/usr/local/share/xray \
/usr/local/etc/xray



# ★关键修复
# 删除损坏更新缓存

if [ -d "${SCRIPT_DIR}" ]; then


rm -rf \
"${SCRIPT_DIR}/xray-script-temp" \
"${SCRIPT_DIR}/null"


fi



# 清除旧安装文件

rm -f /root/install.sh



# ===============================
# 3.重新安装
# ===============================


echo
echo -e "${YELLOW}[*] 步骤 3/5: 重新安装 Xray...${RESET}"



curl \
--connect-timeout 10 \
--retry 3 \
-sSO \
https://raw.githubusercontent.com/oxxconfig/Xray-Socks/main/install.sh



sed -i 's/\r$//' install.sh



SYS_LANG="zh_CN" \
LANG="zh_CN.UTF-8" \
LC_ALL="zh_CN.UTF-8" \
bash install.sh --vision



# 检查

if [ ! -x /usr/local/bin/xray ]; then


echo -e "${RED}[错误] Xray安装失败${RESET}"


exit 1


fi



# ===============================
# 4.恢复
# ===============================


if [ "${HAS_BACKUP}" = "1" ]; then



echo
echo -e "${YELLOW}[*] 步骤 4/5: 恢复节点数据...${RESET}"



systemctl stop xray 2>/dev/null || true



mkdir -p "${XRAY_DIR}"



# 恢复配置

cp -a \
"${BACKUP_DIR}/xray/"*.json \
"${XRAY_DIR}/" \
2>/dev/null || true



# 恢复SSL

if [ -d "${BACKUP_DIR}/ssl" ]; then

cp -a \
"${BACKUP_DIR}/ssl/"* \
/etc/ssl/ \
2>/dev/null || true

fi



# 恢复面板数据

if [ -d "${BACKUP_DIR}/xray-script" ]; then


rm -rf "${SCRIPT_DIR}"


cp -a \
"${BACKUP_DIR}/xray-script" \
/root/


fi



# 修复权限


chown -R root:root "${XRAY_DIR}"


chmod 600 \
"${XRAY_DIR}/config.json" \
2>/dev/null || true



fi




# ===============================
# 5.检查启动
# ===============================


echo
echo -e "${YELLOW}[*] 步骤 5/5: 检查并启动...${RESET}"



xray run \
-test \
-config "${XRAY_DIR}/config.json"



systemctl daemon-reload


systemctl restart xray



sleep 3



if systemctl is-active --quiet xray; then


echo
echo -e "${GREEN}"
echo "================================="
echo " Xray 无损重装恢复成功 "
echo "================================="
echo -e "${RESET}"


echo -e "${BLUE}UUID 保留${RESET}"
echo -e "${BLUE}Reality 私钥保留${RESET}"
echo -e "${BLUE}Socks5 用户保留${RESET}"
echo -e "${BLUE}客户端无需修改${RESET}"


else


echo -e "${RED}Xray启动失败${RESET}"

journalctl -u xray \
-n 50 \
--no-pager


fi
