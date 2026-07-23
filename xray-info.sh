cat << 'EOF' > /usr/local/bin/xray-info
#!/usr/bin/env bash
# 定义颜色与样式
GREEN='\033[1;32m'   # 亮绿加粗
YELLOW='\033[33m'
BLUE='\033[36m'
RED='\033[31m'
NC='\033[0m'        # 重置颜色

# 1. 确保安装依赖
if ! command -v qrencode &>/dev/null; then
    apt-get update && apt-get install -y qrencode || yum install -y qrencode
fi

# 获取当前公网 IP
IP=$(curl -fsSL --connect-timeout 3 ipv4.icanhazip.com || curl -sS4 --connect-timeout 3 ip.sb || echo "127.0.0.1")

# 2. 定位配置文件
SCRIPT_CONFIG_PATH="${HOME}/.xray-script/config.json"
XRAY_CONFIG_PATH="/usr/local/etc/xray/config.json"

[ ! -f "$SCRIPT_CONFIG_PATH" ] && SCRIPT_CONFIG_PATH="/usr/local/xray-script/config/config.json"
[ ! -f "$XRAY_CONFIG_PATH" ] && XRAY_CONFIG_PATH="/etc/xray/config.json"

if [ -f "$XRAY_CONFIG_PATH" ] && [ -f "$SCRIPT_CONFIG_PATH" ] && command -v jq &>/dev/null; then

    XRAY_CONFIG="$(jq '.' "${XRAY_CONFIG_PATH}")"
    SCRIPT_CONFIG="$(jq '.' "${SCRIPT_CONFIG_PATH}")"

    # ------------------ 1. 顶部：Socks5 明文账单 ------------------
    S5_PORT=$(echo "${XRAY_CONFIG}" | jq -r '.inbounds[] | select(.tag=="SOCKS5-INBOUND") | .port' 2>/dev/null)
    S5_USER=$(echo "${XRAY_CONFIG}" | jq -r '.inbounds[] | select(.tag=="SOCKS5-INBOUND") | .settings.accounts[0].user' 2>/dev/null)
    S5_PASS=$(echo "${XRAY_CONFIG}" | jq -r '.inbounds[] | select(.tag=="SOCKS5-INBOUND") | .settings.accounts[0].pass' 2>/dev/null)

    if [ -n "$S5_PORT" ] && [ "$S5_PORT" != "null" ]; then
        echo -e "------------------ 浏览器专用 Socks5 ------------------"
        echo -e "代理类型         : Socks5"
        echo -e "代理 IP          : ${IP}"
        echo -e "端口             : ${S5_PORT}"
        echo -e "用户名           : ${GREEN}${S5_USER}${NC}"
        echo -e "密码             : ${GREEN}${S5_PASS}${NC}"
        echo -e "------------------------------------------------------"
    fi

    # ------------------ 2. 原版 get_common_config 精准提取 ------------------
    # 查找 Vision 所在的 inbound 索引
    inbound_index=$(echo "${XRAY_CONFIG}" | jq -r '([.inbounds[].tag] | index("VLESS-Vision-REALITY")) // 0')

    PORT=$(echo "${SCRIPT_CONFIG}" | jq -r ".xray.port // 443")
    PUBKEY=$(echo "${SCRIPT_CONFIG}" | jq -r ".xray.publicKey")
    TAG=$(echo "${SCRIPT_CONFIG}" | jq -r ".xray.tag // \"Vision\"")

    PROTOCOL=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].protocol? // "vless"')
    UUID=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].settings.clients[0].id? // empty')
    PASSWORD=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].settings.clients[0].password? // empty')
    SEED=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.kcpSettings.seed? // empty')
    TYPE=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.network? // "tcp"')
    FLOW=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].settings.clients[0].flow? // "xtls-rprx-vision"')
    SECURITY=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.security? // "reality"')
    PATH_VAL=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.xhttpSettings.path? // empty')

    # 取第 0 个 serverName 和 shortId
    SERVER_NAME=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.realitySettings.serverNames[0]? // "www.leercapitulo.co"')
    SHORT_ID=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.realitySettings.shortIds[0]? // "8e86738553b1b65a"')

    # 如果 SCRIPT_CONFIG 拿到的 publicKey 为空，尝试实时计算兜底
    if [ -z "$PUBKEY" ] || [ "$PUBKEY" = "null" ]; then
        PRIV_KEY=$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.realitySettings.privateKey? // empty')
        XRAY_BIN=$(which xray 2>/dev/null || find /usr -name "xray" -type f 2>/dev/null | head -n 1)
        if [ -n "$PRIV_KEY" ] && [ -n "$XRAY_BIN" ]; then
            PUBKEY=$("$XRAY_BIN" x25519 -i "$PRIV_KEY" 2>/dev/null | grep -i "Public key" | awk '{print $3}')
        fi
    fi

    # ------------------ 3. 拼装标准的 VLESS 链接 (带美国国旗) ------------------
    FP="chrome"
    SPX="%2F"
    VLESS_LINK="vless://${UUID}@${IP}:${PORT}?type=${TYPE}&security=${SECURITY}&sni=${SERVER_NAME}&pbk=${PUBKEY}&sid=${SHORT_ID}&spx=${SPX}&fp=${FP}&flow=${FLOW}#🇺🇸"

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

    echo -e "------------------ 二维码 ------------------"
    if command -v qrencode &>/dev/null; then
        qrencode -t ansiutf8 "${VLESS_LINK}"
    fi

    echo -e "------------------ 分享链接 ------------------"
    echo -e "${GREEN}${VLESS_LINK}${NC}"
    echo -e "------------------------------------------------------\n"

fi
EOF

chmod +x /usr/local/bin/xray-info
