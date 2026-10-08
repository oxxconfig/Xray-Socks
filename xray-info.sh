cat << 'EOF' > /usr/local/bin/xray-info
#!/usr/bin/env bash
# =============================================================================
# Xray 全能节点信息提取与看板工具 (适配 Debian/Ubuntu/CentOS/RHEL)
# =============================================================================

# 定义颜色与样式
GREEN='\033[1;32m'   # 亮绿加粗
YELLOW='\033[33m'
BLUE='\033[36m'
RED='\033[31m'
NC='\033[0m'        # 重置颜色

# 1. 跨系统自动检测并安装 qrencode 依赖
if ! command -v qrencode &>/dev/null; then
    if command -v apt-get &>/dev/null; then
        apt-get update -y &>/dev/null && apt-get install -y qrencode &>/dev/null
    elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
        PM=$(command -v dnf &>/dev/null && echo "dnf" || echo "yum")
        $PM install -y epel-release &>/dev/null || true
        $PM install -y qrencode &>/dev/null
    fi
fi

# 获取当前公网 IP
IP=$(curl -fsSL --connect-timeout 3 ipv4.icanhazip.com || curl -sS4 --connect-timeout 3 ip.sb || echo "127.0.0.1")

# 2. 定位配置文件
SCRIPT_CONFIG_PATH="${HOME}/.xray-script/config.json"
XRAY_CONFIG_PATH="/usr/local/etc/xray/config.json"

[ ! -f "$SCRIPT_CONFIG_PATH" ] && SCRIPT_CONFIG_PATH="/usr/local/xray-script/config/config.json"
[ ! -f "$XRAY_CONFIG_PATH" ] && XRAY_CONFIG_PATH="/etc/xray/config.json"

if [ -f "$XRAY_CONFIG_PATH" ] && [ -f "$SCRIPT_CONFIG_PATH" ] && command -v jq &>/dev/null; then

    XRAY_CONFIG="$(jq '.' "${XRAY_CONFIG_PATH}" 2>/dev/null)"
    SCRIPT_CONFIG="$(jq '.' "${SCRIPT_CONFIG_PATH}" 2>/dev/null)"

    # ------------------ 1. 顶部：Socks5 明文账单 ------------------
    S5_PORT=$(echo "${XRAY_CONFIG}" | jq -r '.inbounds[]? | select(.tag=="SOCKS5-INBOUND") | .port' 2>/dev/null | tr -d '"')
    S5_USER=$(echo "${XRAY_CONFIG}" | jq -r '.inbounds[]? | select(.tag=="SOCKS5-INBOUND") | .settings.accounts[0].user' 2>/dev/null | tr -d '"')
    S5_PASS=$(echo "${XRAY_CONFIG}" | jq -r '.inbounds[]? | select(.tag=="SOCKS5-INBOUND") | .settings.accounts[0].pass' 2>/dev/null | tr -d '"')

    if [ -n "$S5_PORT" ] && [ "$S5_PORT" != "null" ] && [ "$S5_PORT" != "0" ]; then
        echo -e "${YELLOW}[ 🌐 浏览器专用 Socks5 配置 ]${NC}"
        echo -e " 🔹 代理类型 : Socks5"
        echo -e " 🔹 代理 IP          : ${IP}"
        echo -e " 🔹 端口             : ${S5_PORT}"
        echo -e " 🔹 用户名           : ${GREEN}${S5_USER}${NC}"
        echo -e " 🔹 密码             : ${GREEN}${S5_PASS}${NC}"
        # 快捷链接保持纯文本，避免复制进 ANSI 转义序列导致格式损坏
        echo -e " 🔹 快捷链接         : socks5://${S5_USER}:${S5_PASS}@${IP}:${S5_PORT}"
        echo -e "------------------------------------------------------"
    fi

    # ------------------ 2. 提取 VLESS REALITY 配置参数 ------------------
    # 查找 Vision 所在的 inbound 索引
    inbound_index=$(echo "${XRAY_CONFIG}" | jq -r '([.inbounds[].tag] | index("VLESS-Vision-REALITY")) // 0' 2>/dev/null)

    PORT=$(echo "${SCRIPT_CONFIG}" | jq -r ".xray.port // 443" 2>/dev/null)
    PUBKEY=$(echo "${SCRIPT_CONFIG}" | jq -r ".xray.publicKey // empty" 2>/dev/null)
    TAG=$(echo "${SCRIPT_CONFIG}" | jq -r ".xray.tag // \"VLESS-REALITY\"" 2>/dev/null)

    PROTOCOL=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].protocol? // "vless"' 2>/dev/null)
    UUID=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].settings.clients[0].id? // empty' 2>/dev/null)
    PASSWORD=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].settings.clients[0].password? // empty' 2>/dev/null)
    SEED=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.kcpSettings.seed? // empty' 2>/dev/null)
    TYPE=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.network? // "tcp"' 2>/dev/null)
    FLOW=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].settings.clients[0].flow? // "xtls-rprx-vision"' 2>/dev/null)
    SECURITY=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.security? // "reality"' 2>/dev/null)
    PATH_VAL=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.xhttpSettings.path? // empty' 2>/dev/null)

    # 取第 0 个 serverName 和 shortId
    SERVER_NAME=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.realitySettings.serverNames[0]? // "www.leercapitulo.co"' 2>/dev/null)
    SHORT_ID=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.realitySettings.shortIds[0]? // "8e86738553b1b65a"' 2>/dev/null)

    # 如果 SCRIPT_CONFIG 拿到的 publicKey 为空，尝试实时计算兜底
    if [ -z "$PUBKEY" ] || [ "$PUBKEY" = "null" ]; then
        PRIV_KEY=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.realitySettings.privateKey? // empty' 2>/dev/null)
        XRAY_BIN=$(command -v xray || find /usr -name "xray" -type f 2>/dev/null | head -n 1)
        if [ -n "$PRIV_KEY" ] && [ -n "$XRAY_BIN" ]; then
            PUBKEY=$("$XRAY_BIN" x25519 -i "$PRIV_KEY" 2>/dev/null | grep -i "Public key" | awk '{print $3}')
        fi
    fi

    # ------------------ 3. 拼装标准的 VLESS 链接  ------------------
    FP="chrome"
    SPX="%2F"
    
    # URL Encode 节点名称（避免名称中含特殊字符破坏链接格式）
    LINK_NAME=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${TAG}'))" 2>/dev/null || echo "${TAG}")
    
    VLESS_LINK="vless://${UUID}@${IP}:${PORT}?type=${TYPE}&security=${SECURITY}&sni=${SERVER_NAME}&pbk=${PUBKEY}&sid=${SHORT_ID}&spx=${SPX}&fp=${FP}&flow=${FLOW}#${LINK_NAME}"

    echo -e "\n------------------ 客户端配置(${TAG}) ------------------"
    echo -e "address          : ${IP}"
    echo -e "port             : ${PORT}"
    echo -e "protocol         : ${PROTOCOL}"
    echo -e "uuid             : ${UUID}"
    echo -e "password(trojan) : ${PASSWORD}"
    echo -e "seed(mKCP)       : ${SEED}"
    echo -e "flow             : ${FLOW}"
    echo -e "network          : ${TYPE}"
    echo -e "security         : ${SECURITY}"
    echo -e "ServerName       : ${SERVER_NAME}"
    echo -e "path             : ${PATH_VAL}"
    echo -e "Fingerprint      : chrome"
    echo -e "PublicKey        : ${PUBKEY}"
    echo -e "ShortId          : ${SHORT_ID}"
    echo -e "SpiderX          : /"

    echo -e "\n${YELLOW}[ 📱 手机扫码专用二维码 ]${NC}"
    if command -v qrencode &>/dev/null; then
        qrencode -t ansiutf8 "${VLESS_LINK}"
    fi

    echo -e "${YELLOW}[ 🚀 核心 VLESS-REALITY 订阅链接 ]${NC}"
    echo -e "${GREEN}${VLESS_LINK}${NC}"
    echo -e "------------------------------------------------------\n"

else
    echo -e "${RED}[!] 错误: 未找到 Xray 配置文件或缺少 jq 命令。${NC}"
fi
EOF

chmod +x /usr/local/bin/xray-info
