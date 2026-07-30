# 1. 修复 /etc/hosts 解决主机名无法解析告警
HOST_NAME=$(hostname)
if ! grep -q "$HOST_NAME" /etc/hosts; then
    echo "127.0.0.1 $HOST_NAME" >> /etc/hosts
fi

# 2. 安装并开启 Fail2ban 自动防爆破
apt-get update && apt-get install -y fail2ban

# 3. 写入防爆破规则（输错 3 次密码拉黑 24 小时）
cat << 'EOF' > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime = 86400
EOF

# 4. 启动并开机自启
systemctl restart fail2ban
systemctl enable fail2ban

# 5. 查看拉黑状态
fail2ban-client status sshd
