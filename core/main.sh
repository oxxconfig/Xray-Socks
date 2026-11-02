cat << 'EOF' > install.sh
#!/usr/bin/env bash

if [ "$EUID" -ne 0 ]; then
    echo -e "\033[31m[错误] 请使用 root 用户运行此脚本！\033[0m"
    exit 1
fi

set -o pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:$HOME/bin:/snap/bin
export PATH

GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$1]${NC} $2"
}

error() {
    echo -e "${RED}[错误]${NC} $1"
    exit 1
}

QUICK_INSTALL=""
for arg in "$@"; do
    case "$arg" in
        --vision|--xhttp|--fallback)
            QUICK_INSTALL="$arg"
            ;;
    esac
done

SCRIPT_CONFIG_DIR="${HOME}/.xray-script"
SCRIPT_CONFIG_PATH="${SCRIPT_CONFIG_DIR}/config.json"
mkdir -p "${SCRIPT_CONFIG_DIR}"
cat << 'JSON_EOF' > "${SCRIPT_CONFIG_PATH}"
{
  "version": "2026.03.17",
  "language": "zh",
  "path": "/usr/local/xray-script"
}
JSON_EOF

log "基础配置" "正在更新依赖..."
killall apt apt-get dpkg 2>/dev/null || true
rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock* 2>/dev/null || true
dpkg --configure -a 2>/dev/null || true

apt-get update -y || error "apt-get update 执行失败。"
apt-get install -y ca-certificates openssl curl wget git jq tzdata qrencode socat cron iproute2 procps dnsutils unzip tar || error "依赖安装失败。"

log "基础配置" "正在配置 BBR..."
SYSCTL_FILE="/etc/sysctl.conf"
touch "$SYSCTL_FILE" || error "无法写入 $SYSCTL_FILE"
sed -i '/^[[:space:]]*net\.core\.default_qdisc[[:space:]]*=/d' "$SYSCTL_FILE"
sed -i '/^[[:space:]]*net\.ipv4\.tcp_congestion_control[[:space:]]*=/d' "$SYSCTL_FILE"
cat >> "$SYSCTL_FILE" <<'SYSCTL_EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
SYSCTL_EOF
sysctl -p >/dev/null 2>&1 || true

if command -v iptables >/dev/null 2>&1; then
    if ! iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p tcp --dport 443 -j ACCEPT || error "iptables 添加 443 放行规则失败。"
    fi
    iptables-save > /etc/iptables.rules 2>/dev/null || true
fi

PROJECT_ROOT="/usr/local/xray-script"
CORE_DIR="${PROJECT_ROOT}/core"
TMP_ROOT="/tmp/xray_deploy_temp"
TMP_TAR="${TMP_ROOT}/project.tar.gz"
TMP_EXTRACT="${TMP_ROOT}/extract"
XRAY_TMP="${TMP_ROOT}/xray"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_EXTRACT" "$XRAY_TMP" || error "无法创建临时目录。"

log "下载项目" "正在拉取 Xray-Socks 主脚本..."
PROJECT_URL="https://github.com/oxxconfig/Xray-Socks/archive/refs/heads/main.tar.gz"
curl -sL --connect-timeout 15 --retry 3 "$PROJECT_URL" -o "$TMP_TAR" || error "项目压缩包下载失败。"
[ -s "$TMP_TAR" ] || error "项目压缩包为空。"
tar -xzf "$TMP_TAR" -C "$TMP_EXTRACT" --no-same-owner || error "项目压缩包解压失败。"

ROOT_DIR=$(find "$TMP_EXTRACT" -mindepth 1 -maxdepth 1 -type d | head -n 1)
[ -n "$ROOT_DIR" ] && [ -d "$ROOT_DIR" ] || error "未找到项目目录。"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) XRAY_ARCH="64" ;;
    aarch64|arm64) XRAY_ARCH="arm64-v8a" ;;
    *) error "暂不支持当前 CPU 架构：$ARCH" ;;
esac

log "预备核心" "正在下载官方 Xray 核心..."
XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip"
curl -sL --connect-timeout 15 --retry 3 "$XRAY_URL" -o "$XRAY_TMP/xray.zip" || error "Xray 核心下载失败。"
unzip -qo "$XRAY_TMP/xray.zip" -d "$XRAY_TMP" || error "Xray 核心解压失败。"
chmod 755 "$XRAY_TMP/xray"

log "纯净重建" "正在清理旧配置与旧脚本..."
systemctl stop xray 2>/dev/null || true
rm -rf "$PROJECT_ROOT" /usr/local/etc/xray /usr/local/share/xray
mkdir -p "$PROJECT_ROOT" /usr/local/etc/xray /usr/local/share/xray

cp -a "$ROOT_DIR"/. "$PROJECT_ROOT/" || error "复制项目文件失败。"

# 完美补齐占位目录，防止远端 main.sh 读取 config/xray/.json 爆 null
mkdir -p "${PROJECT_ROOT}/config/xray"
echo "{}" > "${PROJECT_ROOT}/config/xray/config.json"
mkdir -p "${PROJECT_ROOT}/i18n"
echo "{}" > "${PROJECT_ROOT}/i18n/zh.json"
ln -sf "${PROJECT_ROOT}/i18n/zh.json" "${PROJECT_ROOT}/i18n/.json" 2>/dev/null || true

install -m 755 "$XRAY_TMP/xray" /usr/bin/xray || error "安装 Xray 核心失败。"

log "业务脚本" "正在执行配置生成..."
if [ -n "$QUICK_INSTALL" ]; then
    bash "$CORE_DIR/main.sh" "$QUICK_INSTALL" </dev/null || error "业务脚本执行失败：$QUICK_INSTALL"
else
    bash "$CORE_DIR/main.sh" </dev/null || error "业务脚本执行失败。"
fi

CONFIG_FILE="/usr/local/etc/xray/config.json"
[ -s "$CONFIG_FILE" ] || error "配置文件不存在或为空：$CONFIG_FILE"

log "服务注册" "正在配置 systemd xray.service..."
cat > /etc/systemd/system/xray.service <<'SERVICE_EOF'
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
SERVICE_EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray || error "Xray 服务启动失败。"

log "看板挂载" "正在配置 xray-info..."
curl -sL --connect-timeout 15 --retry 3 "https://raw.githubusercontent.com/oxxconfig/Xray-Socks/main/xray-info.sh" -o /usr/local/bin/xray-info
chmod 755 /usr/local/bin/xray-info
rm -rf "$TMP_ROOT"

echo ""
log "安装完成" "Xray 已成功安装并运行。"
if [ -x "/usr/local/bin/xray-info" ]; then
    /usr/local/bin/xray-info
fi
EOF

# 重点：这里执行的是本地写出来的 install.sh 文件，而不是远程管道符！
bash install.sh --vision
