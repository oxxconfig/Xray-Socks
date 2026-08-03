#!/bin/bash

# 写入 sysctl 配置
sudo bash -c 'cat > /etc/sysctl.d/99-disable-ipv6.conf << "CONF"
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
CONF'

# 刷新 sysctl 配置
sudo sysctl --system > /dev/null 2>&1

# 检查结果
STATUS=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
if [ "$STATUS" = "1" ]; then
    echo -e "\033[32m[成功] IPv6 已成功禁用！\033[0m"
else
    echo -e "\033[31m[失败] IPv6 禁用未生效，请检查权限。\033[0m"
fi
