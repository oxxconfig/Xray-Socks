#!/usr/bin/env bash

# ============================================================
# Xray-Socks 一键部署脚本 (修复优化版)
# 支持：--vision / --xhttp / --fallback
# ============================================================

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

# ------------------------------------------------------------
# 参数识别
# ------------------------------------------------------------

QUICK_INSTALL=""

for arg in "$@"; do
    case "$arg" in
        --vision|--xhttp|--fallback)
            QUICK_INSTALL="$arg"
            ;;
    esac
done

# ------------------------------------------------------------
# 基础环境检查
# ------------------------------------------------------------

if ! command -v apt-get >/dev/null 2>&1; then
    error "当前系统不支持 apt-get，仅支持 Debian / Ubuntu 系统。"
fi

log "基础配置" "正在清理可能存在的 apt 锁并更新依赖..."
killall apt apt-get dpkg 2>/dev/null || true
rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock* 2>/dev/null || true
dpkg --configure -a 2>/dev/null || true

apt-get update -y || error "apt-get update 执行失败。"

apt-get install -y \
    ca-certificates \
    openssl \
    curl \
    wget \
    git \
    jq \
    tzdata \
    qrencode \
    socat \
    cron \
    iproute2 \
    procps \
    dnsutils \
    unzip \
    tar \
    || error "依赖安装失败。"

# ------------------------------------------------------------
# BBR 配置
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# 防火墙放行 443
# ------------------------------------------------------------

if command -v iptables >/dev/null 2>&1; then
    if ! iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p tcp --dport 443 -j ACCEPT \
            || error "iptables 添加 443 放行规则失败。"
    fi

    iptables-save > /etc/iptables.rules 2>/dev/null || true
fi

# ------------------------------------------------------------
# 项目路径与临时目录
# ------------------------------------------------------------

PROJECT_ROOT="/usr/local/xray-script"
CORE_DIR="${PROJECT_ROOT}/core"

TMP_ROOT="/tmp/xray_deploy_temp"
TMP_TAR="${TMP_ROOT}/project.tar.gz"
TMP_EXTRACT="${TMP_ROOT}/extract"
XRAY_TMP="${TMP_ROOT}/xray"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_EXTRACT" "$XRAY_TMP" \
    || error "无法创建临时目录。"

# ------------------------------------------------------------
# 下载并校验项目压缩包
# ------------------------------------------------------------

log "下载项目" "正在拉取 Xray-Socks 主脚本..."

PROJECT_URL="https://github.com/oxxconfig/Xray-Socks/archive/refs/heads/main.tar.gz"

curl -sL --connect-timeout 15 --retry 3 \
    "$PROJECT_URL" -o "$TMP_TAR" \
    || error "项目压缩包下载失败。"

[ -s "$TMP_TAR" ] || error "项目压缩包为空。"

tar -tzf "$TMP_TAR" >/dev/null 2>&1 \
    || error "项目压缩包校验失败。"

tar -xzf "$TMP_TAR" -C "$TMP_EXTRACT" --no-same-owner \
    || error "项目压缩包解压失败。"

ROOT_DIR=$(find "$TMP_EXTRACT" -mindepth 1 -maxdepth 1 -type d | head -n 1)

[ -n "$ROOT_DIR" ] && [ -d "$ROOT_DIR" ] \
    || error "未找到项目目录。"

[ -f "$ROOT_DIR/core/main.sh" ] \
    || error "项目中缺少 core/main.sh。"

# ------------------------------------------------------------
# 自动识别 CPU 架构
# ------------------------------------------------------------

ARCH=$(uname -m)

case "$ARCH" in
    x86_64|amd64)
        XRAY_ARCH="64"
        ;;
    aarch64|arm64)
        XRAY_ARCH="arm64-v8a"
        ;;
    *)
        error "暂不支持当前 CPU 架构：$ARCH"
        ;;
esac

# ------------------------------------------------------------
# 预下载并验证 Xray 核心
# ------------------------------------------------------------

log "预备核心" "正在下载官方 Xray 核心..."

XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip"

curl -sL --connect-timeout 15 --retry 3 \
    "$XRAY_URL" -o "$XRAY_TMP/xray.zip" \
    || error "Xray 核心下载失败。"

[ -s "$XRAY_TMP/xray.zip" ] \
    || error "Xray 核心压缩包为空。"

unzip -tq "$XRAY_TMP/xray.zip" >/dev/null 2>&1 \
    || error "Xray 核心压缩包校验失败。"

unzip -qo "$XRAY_TMP/xray.zip" -d "$XRAY_TMP" \
    || error "Xray 核心解压失败。"

[ -f "$XRAY_TMP/xray" ] \
    || error "压缩包中未找到 Xray 核心文件。"

chmod 755 "$XRAY_TMP/xray"

"$XRAY_TMP/xray" version >/dev/null 2>&1 \
    || error "Xray 核心无法正常运行。"

# ------------------------------------------------------------
# 纯净重建
# ------------------------------------------------------------

log "纯净重建" "正在清理旧配置与旧脚本..."

systemctl stop xray 2>/dev/null || true

rm -rf "$PROJECT_ROOT" \
    /usr/local/etc/xray \
    /usr/local/share/xray

mkdir -p \
    "$PROJECT_ROOT" \
    /usr/local/etc/xray \
    /usr/local/share/xray \
    || error "创建安装目录失败。"

cp -a "$ROOT_DIR"/. "$PROJECT_ROOT/" \
    || error "复制项目文件失败。"

install -m 755 "$XRAY_TMP/xray" /usr/bin/xray \
    || error "安装 Xray 核心失败。"

[ -x /usr/bin/xray ] \
    || error "/usr/bin/xray 不存在或不可执行。"

# ------------------------------------------------------------
# 执行业务配置脚本 (修复参数传入与标准输入重定向)
# ------------------------------------------------------------

log "业务脚本" "正在执行配置生成..."

[ -f "$CORE_DIR/main.sh" ] \
    || error "找不到业务脚本：$CORE_DIR/main.sh"

if [ -n "$QUICK_INSTALL" ]; then
    bash "$CORE_DIR/main.sh" "$QUICK_INSTALL" </dev/null \
        || error "业务脚本执行失败：$QUICK_INSTALL"
else
    bash "$CORE_DIR/main.sh" </dev/null \
        || error "业务脚本执行失败。"
fi

# ------------------------------------------------------------
# 检查配置文件
# ------------------------------------------------------------

CONFIG_FILE="/usr/local/etc/xray/config.json"

[ -s "$CONFIG_FILE" ] \
    || error "配置文件不存在或为空：$CONFIG_FILE"

log "配置检查" "正在验证 Xray 配置..."

/usr/bin/xray run -test -config "$CONFIG_FILE" \
    || error "Xray 配置验证失败，请检查 config.json。"

# ------------------------------------------------------------
# 注册 systemd 服务
# ------------------------------------------------------------

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

systemctl daemon-reload \
    || error "systemd daemon-reload 执行失败。"

systemctl enable xray \
    || error "启用 xray 服务失败。"

systemctl restart xray \
    || error "Xray 服务启动失败。"

sleep 2

if ! systemctl is-active --quiet xray; then
    echo -e "${RED}[错误] Xray 服务未正常运行，最近日志如下：${NC}"
    journalctl -u xray -n 30 --no-pager
    error "Xray 服务启动验证失败。"
fi

# ------------------------------------------------------------
# 下载看板脚本
# ------------------------------------------------------------

log "看板挂载" "正在配置 xray-info..."

INFO_TMP="/usr/local/bin/xray-info.tmp"

rm -f "$INFO_TMP"

curl -sL --connect-timeout 15 --retry 3 \
    -H "Cache-Control: no-cache" \
    "https://raw.githubusercontent.com/oxxconfig/Xray-Socks/main/xray-info.sh" \
    -o "$INFO_TMP" \
    || error "xray-info 下载失败。"

[ -s "$INFO_TMP" ] \
    || error "xray-info 文件为空。"

chmod 755 "$INFO_TMP" \
    || error "xray-info 权限设置失败。"

mv -f "$INFO_TMP" /usr/local/bin/xray-info \
    || error "安装 xray-info 失败。"

# ------------------------------------------------------------
# 清理临时文件
# ------------------------------------------------------------

rm -rf "$TMP_ROOT"

# ------------------------------------------------------------
# 安装完成
# ------------------------------------------------------------

echo ""
log "安装完成" "Xray 已成功安装并运行。"

echo -e "${GREEN}Xray 核心：${NC} /usr/bin/xray"
echo -e "${GREEN}配置目录：${NC} /usr/local/etc/xray"
echo -e "${GREEN}管理目录：${NC} ${PROJECT_ROOT}"
echo -e "${GREEN}服务状态：${NC} $(systemctl is-active xray)"

if [ -x "/usr/local/bin/xray-info" ]; then
    echo ""
    /usr/local/bin/xray-info
fi
