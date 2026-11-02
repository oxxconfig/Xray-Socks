cat << 'EOF' > install.sh
#!/usr/bin/env bash
if [ "$EUID" -ne 0 ]; then
echo -e "\033[31m[错误] 请使用 root 用户运行此脚本！\033[0m"
exit 1
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

ORIGINAL_ARGS=("$@")
QUICK_INSTALL=""
for arg in "$@"; do
case "$arg" in
    --vision|--xhttp|--fallback) QUICK_INSTALL="$arg" ;;
esac
done

GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
NC='\033[0m'

echo -e "${GREEN}[基础配置]${NC} 正在优化系统内核与防火墙..."
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1
if type iptables >/dev/null 2>&1; then
iptables -I INPUT -p tcp --dport 443 -j ACCEPT
iptables-save > /etc/iptables.rules 2>/dev/null || true
fi

echo -e "${YELLOW}[基础配置]${NC} 正在更新依赖 (含 unzip)..."
apt-get update -y
apt-get install -y ca-certificates openssl curl wget git jq tzdata qrencode socat cron iproute2 procps dnsutils unzip

echo -e "${GREEN}[纯净重建]${NC} 清理旧配置与旧脚本..."
PROJECT_ROOT='/usr/local/xray-script'
systemctl stop xray 2>/dev/null || true
rm -rf "${PROJECT_ROOT}" /usr/local/etc/xray /usr/local/share/xray
mkdir -p "${PROJECT_ROOT}" /usr/local/etc/xray /usr/local/share/xray

echo -e "${GREEN}[下载核心]${NC} 正在拉取主脚本压缩包..."
tmp_tar="/tmp/xray_deploy_temp.tar.gz"
tmp_dir="/tmp/xray_deploy_extract"
curl -sLo "${tmp_tar}" "https://github.com/oxxconfig/Xray-Socks/archive/refs/heads/main.tar.gz"
mkdir -p "${tmp_dir}"
tar -xzf "${tmp_tar}" -C "${tmp_dir}" --no-same-owner 2>/dev/null
root_dir=$(find "${tmp_dir}" -maxdepth 1 -mindepth 1 -type d | head -n 1)
[[ -n "${root_dir}" && -d "${root_dir}" ]] && cp -rf "${root_dir}"/* "${PROJECT_ROOT}/"
rm -rf "${tmp_tar}" "${tmp_dir}"

echo -e "${GREEN}[预备核心]${NC} 正在预先下载官方 Xray 核心并注册到 /usr/bin/xray..."
_xray_tmp="/tmp/xray_install_pre"
mkdir -p "${_xray_tmp}"
_arch="64"
[[ "$(uname -m)" =~ "aarch64"|"arm64" ]] && _arch="arm64-v8a"
if curl -sLo "${_xray_tmp}/xray.zip" "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${_arch}.zip"; then
unzip -qo "${_xray_tmp}/xray.zip" -d "${_xray_tmp}"
[ -f "${_xray_tmp}/xray" ] && install -m 755 "${_xray_tmp}/xray" /usr/bin/xray
fi
rm -rf "${_xray_tmp}"

CORE_DIR="${PROJECT_ROOT}/core"
echo -e "${GREEN}[业务脚本]${NC} 正在执行配置生成..."
if [ -n "$QUICK_INSTALL" ]; then
bash "${CORE_DIR}/main.sh" "$QUICK_INSTALL" </dev/null
else
bash "${CORE_DIR}/main.sh" </dev/null
fi

echo -e "${GREEN}[服务注册]${NC} 正在配置 systemd xray.service..."
cat << 'SERVICE_EOF' > /etc/systemd/system/xray.service
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
systemctl enable xray 2>/dev/null || true
systemctl restart xray || true

echo -e "${GREEN}[看板挂载]${NC} 正在配置 xray-info..."
curl -sS -H "Cache-Control: no-cache" -L "https://raw.githubusercontent.com/oxxconfig/Xray-Socks/main/xray-info.sh" > /usr/local/bin/xray-info 2>/dev/null
chmod +x /usr/local/bin/xray-info

if [ -x "/usr/local/bin/xray-info" ]; then
echo ""
/usr/local/bin/xray-info
fi
EOF
