#!/usr/bin/env bash
# =============================================================================
# Fail2ban 静默一键部署脚本（禁止内核更新 / 无弹窗打扰）
# =============================================================================

# 1. 屏蔽所有 APT 交互弹窗与服务重启提示
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# 2. 修复 /etc/hosts 解决主机名无法解析告警
HOST_NAME=$(hostname)
if [ -n "$HOST_NAME" ] && ! grep -q "$HOST_NAME" /etc/hosts; then
    echo "127.0.0.1 $HOST_NAME" >> /etc/hosts
fi

# 3. 仅安装 Fail2ban 本体（不执行 apt-get upgrade，绝不触发内核升级）
# -o 选项确保跳过配置文件询问与 needrestart 弹窗
apt-get update -y
apt-get install -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  fail2ban

# 4. 写入防爆破规则（10分钟内输错 3 次密码拉黑 24 小时）
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

# 5. 重载服务并设置开机自启
systemctl daemon-reload
systemctl restart fail2ban
systemctl enable fail2ban

# 6. 校验运行状态
echo -e "\n\033[32m[✓] Fail2ban 部署完成！当前防护状态：\033[0m"
fail2ban-client status sshd
