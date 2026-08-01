#!/usr/bin/env bash
# =============================================================================
# Xray-Socks 无损自动重装恢复脚本
# Ubuntu 22.04 优化版
#
# 保留:
#   UUID
#   Reality PrivateKey
#   Reality ShortID
#   Socks5 用户
#   TLS证书
#   面板数据
#
# 修复:
#   xray-script-temp -> null
#   locale错误
#   半安装状态
# =============================================================================


set -e


# =============================================================================
# 环境初始化
# =============================================================================

export HOME=/root
export SYS_LANG="zh_CN"


# 自动生成中文locale

if ! locale -a 2>/dev/null | grep -qi "zh_CN.utf8"; then

    echo "[*] 正在生成中文系统环境..."

    apt-get update -qq

    apt-get install -y locales >/dev/null 2>&1 || true


    sed -i \
    's/^# *zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' \
    /etc/locale.gen 2>/dev/null || true


    locale-gen zh_CN.UTF-8 >/dev/null 2>&1 || true

fi


export LANG="zh_CN.UTF-8"
export LC_ALL="zh_CN.UTF-8"



# =============================================================================
# 参数
# =============================================================================


BACKUP_DIR="/root/xray_config_backup"

XRAY_DIR="/usr/local/etc/xray"

SCRIPT_DIR="/root/.xray-script"


GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[36m"
RESET="\033[0m"



echo -e "${YELLOW}[*] 初始化环境...${RESET}"



# =============================================================================
# 创建备份
# =============================================================================


echo

echo -e "${YELLOW}[*] 步骤 1/6: 备份节点数据...${RESET}"



# 防止覆盖旧备份

if [ -d "${BACKUP_DIR}" ]; then

    mv "${BACKUP_DIR}" \
    "${BACKUP_DIR}_$(date +%Y%m%d_%H%M%S)"

fi



mkdir -p "${BACKUP_DIR}"



HAS_BACKUP=0



# Xray配置

if [ -f "${XRAY_DIR}/config.json" ]; then


    mkdir -p "${BACKUP_DIR}/xray"


    cp -a \
    "${XRAY_DIR}"/*.json \
    "${BACKUP_DIR}/xray/" \
    2>/dev/null || true


    HAS_BACKUP=1


    echo -e "${GREEN}[✓] Xray配置备份完成${RESET}"

else

    echo -e "${RED}[!] 未发现config.json${RESET}"

fi




# TLS

if [ -d "/etc/ssl" ]; then

    cp -a \
    /etc/ssl \
    "${BACKUP_DIR}/ssl" \
    2>/dev/null || true

fi



# 面板数据

if [ -d "${SCRIPT_DIR}" ]; then


    cp -a \
    "${SCRIPT_DIR}" \
    "${BACKUP_DIR}/xray-script"


fi




# =============================================================================
# 清理旧环境
# =============================================================================


echo

echo -e "${YELLOW}[*] 步骤 2/6: 清理旧Xray环境...${RESET}"



systemctl stop xray 2>/dev/null || true

systemctl disable xray 2>/dev/null || true



rm -f /usr/local/bin/xray


rm -rf \
/usr/local/share/xray \
/usr/local/etc/xray




# ★关键修复
# 清除导致null错误的缓存


if [ -d "${SCRIPT_DIR}" ]; then


    rm -rf \
    "${SCRIPT_DIR}/xray-script-temp" \
    "${SCRIPT_DIR}/null"


fi



rm -f /root/install.sh





# =============================================================================
# 下载安装
# =============================================================================


echo

echo -e "${YELLOW}[*] 步骤 3/6: 下载最新安装脚本...${RESET}"



curl \
--connect-timeout 10 \
--retry 3 \
-sSO \
https://raw.githubusercontent.com/oxxconfig/Xray-Socks/main/install.sh



sed -i 's/\r$//' install.sh




echo

echo -e "${YELLOW}[*] 开始重新安装Xray...${RESET}"



SYS_LANG="zh_CN" \
LANG="zh_CN.UTF-8" \
LC_ALL="zh_CN.UTF-8" \
timeout 300 \
bash install.sh --vision




# 检查核心

if [ ! -x "/usr/local/bin/xray" ]; then


    echo -e "${RED}[错误] Xray核心安装失败${RESET}"

    exit 1

fi




# =============================================================================
# 恢复配置
# =============================================================================


if [ "${HAS_BACKUP}" = "1" ]; then



echo

echo -e "${YELLOW}[*] 步骤 4/6: 恢复节点配置...${RESET}"



systemctl stop xray 2>/dev/null || true



mkdir -p "${XRAY_DIR}"



# 恢复JSON

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




# 权限修复

chown -R root:root "${XRAY_DIR}"


chmod 600 \
"${XRAY_DIR}/config.json" \
2>/dev/null || true



fi




# =============================================================================
# 配置检测
# =============================================================================


echo

echo -e "${YELLOW}[*] 步骤 5/6: 检查Xray配置...${RESET}"



xray run \
-test \
-config "${XRAY_DIR}/config.json"




# =============================================================================
# 启动
# =============================================================================


echo

echo -e "${YELLOW}[*] 步骤 6/6: 启动服务...${RESET}"



systemctl daemon-reload


systemctl restart xray



sleep 3




if systemctl is-active --quiet xray; then


echo

echo -e "${GREEN}"
echo "======================================"
echo " Xray 无损重装恢复成功 "
echo "======================================"
echo -e "${RESET}"


echo -e "${BLUE}✓ UUID 保留${RESET}"
echo -e "${BLUE}✓ Reality密钥保留${RESET}"
echo -e "${BLUE}✓ Socks5用户保留${RESET}"
echo -e "${BLUE}✓ TLS证书保留${RESET}"
echo -e "${BLUE}✓ 客户端无需修改${RESET}"



else


echo -e "${RED}[错误] Xray启动失败${RESET}"


journalctl \
-u xray \
-n 50 \
--no-pager


exit 1


fi
