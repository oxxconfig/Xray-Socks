cat << 'EOF' > install.sh
#!/usr/bin/env bash
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[31m[错误] 请使用 root 用户运行此脚本！\033[0m"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:$HOME/bin:/snap/bin
export PATH

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

echo -e "${GREEN}[1/5] 正在优化系统内核与防火墙...${NC}"
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1
if type iptables >/dev/null 2>&1; then
    iptables -I INPUT -p tcp --dport 443 -j ACCEPT
    iptables-save > /etc/iptables.rules 2>/dev/null || true
fi

echo -e "${GREEN}[2/5] 正在更新系统依赖 (含 unzip)...${NC}"
killall apt apt-get dpkg 2>/dev/null || true
rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock* 2>/dev/null || true
dpkg --configure -a 2>/dev/null || true
apt-get update -y
apt-get install -y ca-certificates openssl curl wget git jq tzdata qrencode socat cron iproute2 procps dnsutils unzip tar

echo -e "${GREEN}[3/5] 正在初始化项目目录并下载主脚本...${NC}"
PROJECT_ROOT='/usr/local/xray-script'
systemctl stop xray 2>/dev/null || true
rm -rf "${PROJECT_ROOT}" /usr/local/etc/xray /usr/local/share/xray
mkdir -p "${PROJECT_ROOT}" /usr/local/etc/xray /usr/local/share/xray

tmp_tar="/tmp/xray_deploy_temp.tar.gz"
tmp_dir="/tmp/xray_deploy_extract"
rm -rf "${tmp_tar}" "${tmp_dir}"
curl -sL --connect-timeout 15 --retry 3 "https://github.com/oxxconfig/Xray-Socks/archive/refs/heads/main.tar.gz" -o "${tmp_tar}"
mkdir -p "${tmp_dir}"
tar -xzf "${tmp_tar}" -C "${tmp_dir}" --no-same-owner 2>/dev/null
root_dir=$(find "${tmp_dir}" -
