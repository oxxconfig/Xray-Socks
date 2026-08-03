sudo bash -c 'cat > /etc/sysctl.d/99-disable-ipv6.conf << "CONF"
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
CONF'
sudo sysctl --system > /dev/null 2>&1
STATUS=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
if [ "$STATUS" = "1" ]; then
    echo -e "\033[32m[成功] ！\033[0m"
else
    echo -e "\033[31m[失败] 请检查系统权限。\033[0m"
fi
EOF
)"
