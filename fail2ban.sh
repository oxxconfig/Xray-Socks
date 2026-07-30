# 1. 安装 Fail2ban
apt update && apt install -y fail2ban

# 2. 写入全局防爆破规则
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

# 3. 启动并开机自启
systemctl restart fail2ban
systemctl enable fail2ban

# 4. 实时查看当前拉黑效果
fail2ban-client status sshd
