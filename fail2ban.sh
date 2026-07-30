#!/usr/bin/env bash
# =============================================================================
# Fail2ban 静默一键部署脚本（禁止内核更新 / 无弹窗打扰）
# =============================================================================

# 1. 设置非交互环境变量，防止再次弹出内核窗口
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# 2. 清理并修复被意外中断的 apt 任务
dpkg --configure -a
apt-get install -f -y

# 3. 重新静默安装 Fail2ban
apt-get update -y
apt-get install -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  fail2ban

# 4. 写入防爆破规则
cat << 'EOF' > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = ssh
filter = sshd
backend = auto
maxretry = 3
findtime = 600
bantime = 86400
EOF

# 5. 重启并激活服务
systemctl daemon-reload
systemctl restart fail2ban
systemctl enable fail2ban

# 6. 校验运行状态
echo -e "\n\033[32m[✓] Fail2ban 部署完成！当前防护状态：\033[0m"
fail2ban-client status sshd
