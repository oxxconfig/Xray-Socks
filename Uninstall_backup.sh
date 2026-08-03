#!/usr/bin/env bash
# =============================================================================
# Xray 独立无损全自动重装脚本（不依赖 install.sh / 保持节点完全不变）
# =============================================================================

set -e

# 1. 权限与环境判断
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[31m[错误] 请使用 root 用户运行此脚本！\033[0m"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
BACKUP_DIR="/tmp/xray_config_backup"
XRAY_BIN="/usr/bin/xray"
CONFIG_DIR="/usr/local/etc/xray"
DATA_DIR="/usr/local/share/xray"
PANEL_DIR="${HOME}/.xray-script"

echo -e "\033[33m[*]\033[0m 步骤 1/5: 锁定现有节点配置与面板数据..."
rm -rf "${BACKUP_DIR}" && mkdir -p "${BACKUP_DIR}"
HAS_BACKUP=0

# 备份配置与面板缓存
if [ -d "${CONFIG_DIR}" ] && [ -n "$(ls -A "${CONFIG_DIR}" 2>/dev/null)" ]; then
    cp -aT "${CONFIG_DIR}" "${BACKUP_DIR}/xray"
    HAS_BACKUP=1
fi

if [ -d "${PANEL_DIR}" ]; then
    cp -aT "${PANEL_DIR}" "${BACKUP_DIR}/xray-script"
fi

if [ ${HAS_BACKUP} -eq 1 ]; then
    echo -e "\033[32m[✓]\033[0m 旧节点配置与面板数据已成功锁定！"
else
    echo -e "\033[31m[!]\033[0m 未找到旧配置，本次重装将仅部署空白环境。"
fi

echo -e "\n\033[33m[*]\033[0m 步骤 2/5: 清理旧版本二进制与服务依赖..."
systemctl stop xray 2>/dev/null || true
systemctl disable xray 2>/dev/null || true
rm -f /usr/local/bin/xray "${XRAY_BIN}"
rm -rf "${DATA_DIR}" "${CONFIG_DIR}" "${PANEL_DIR}"

echo -e "\n\033[33m[*]\033[0m 步骤 3/5: 独立补全系统依赖与下载 Xray 核心..."
if type apt-get >/dev/null 2>&1; then
    apt-get update -y -q >/dev/null 2>&1
    apt-get install -y -q curl wget jq unzip ca-certificates >/dev/null 2>&1
elif type dnf >/dev/null 2>&1 || type yum >/dev/null 2>&1; then
    yum install -y -q curl wget jq unzip ca-certificates >/dev/null 2>&1
fi

# 获取 Xray 最新官方发行包
LATEST_TAG=$(curl -s --connect-timeout 10 https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name 2>/dev/null || echo "v24.11.30")
echo -e "\033[32m[+] 抓取到最新 Xray-core 版本: ${LATEST_TAG}\033[0m"

TMP_ZIP="/tmp/xray-core.zip"
TMP_EXTRACT="/tmp/xray-core-extract"
rm -rf "${TMP_ZIP}" "${TMP_EXTRACT}" && mkdir -p "${TMP_EXTRACT}"

# 架构判定
ARCH=$(uname -m)
case "${ARCH}" in
    x86_64|amd64) XARCH="64" ;;
    aarch64|arm64) XARCH="arm64-v8a" ;;
    *) echo -e "\033[31m[错误] 暂不支持的架构: ${ARCH}\033[0m"; exit 1 ;;
esac

DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/${LATEST_TAG}/Xray-linux-${XARCH}.zip"
echo -e "\033[33m[*]\033[0m 正在下载核心程序包..."
curl -sSL --connect-timeout 10 --retry 3 "${DOWNLOAD_URL}" -o "${TMP_ZIP}"

unzip -q "${TMP_ZIP}" -d "${TMP_EXTRACT}"
mkdir -p "${DATA_DIR}" "${CONFIG_DIR}"
mv -f "${TMP_EXTRACT}/xray" "${XRAY_BIN}"
mv -f "${TMP_EXTRACT}/geoip.dat" "${DATA_DIR}/" 2>/dev/null || true
mv -f "${TMP_EXTRACT}/geosite.dat" "${DATA_DIR}/" 2>/dev/null || true
chmod +x "${XRAY_BIN}"
rm -rf "${TMP_ZIP}" "${TMP_EXTRACT}"

echo -e "\n\033[33m[*]\033[0m 步骤 4/5: 配置独立 Systemd 守护进程与面板脚本..."
cat << 'EOF' > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000
RuntimeDirectory=xray
RuntimeDirectoryMode=0755

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# 挂载面板交互脚本
curl -sS -H "Cache-Control: no-cache" -L "https://raw.githubusercontent.com/oxxconfig/Xray-Socks/main/xray-info.sh" > /usr/local/bin/xray-info 2>/dev/null || true
chmod +x /usr/local/bin/xray-info 2>/dev/null || true

echo -e "\n\033[33m[*]\033[0m 步骤 5/5: 强制同步还原旧节点与面板信息..."
if [ ${HAS_BACKUP} -eq 1 ]; then
    # 还原 Xray 配置
    cp -aT "${BACKUP_DIR}/xray" "${CONFIG_DIR}"
    
    # 还原面板数据缓存（连同 public_key 一起带回）
    if [ -d "${BACKUP_DIR}/xray-script" ]; then
        mkdir -p "${PANEL_DIR}"
        cp -aT "${BACKUP_DIR}/xray-script" "${PANEL_DIR}"
    fi

    # 校验并重启
    "${XRAY_BIN}" run -test -config "${CONFIG_DIR}/config.json"
    systemctl enable xray >/dev/null 2>&1 || true
    systemctl restart xray
    
    rm -rf "${BACKUP_DIR}"
    echo -e "\033[32m[完美成功]\033[0m 旧节点及面板信息（UUID/PBK/Socks5）已全部无损同步复原！"
    
    # 自动调用面板展示
    if [ -x "/usr/local/bin/xray-info" ]; then
        echo -e "\n\033[36m👉 正在调用面板验证最终配置：\033[0m"
        /usr/local/bin/xray-info
    fi
else
    echo -e "\033[33m[!] 未检测到备份，未还原任何旧节点。\033[0m"
fi
