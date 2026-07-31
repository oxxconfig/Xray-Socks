#!/usr/bin/env bash
# =============================================================================
# Xray 重装后节点激活与状态恢复脚本 (全目录无损恢复版)
# =============================================================================

echo -e "\033[33m[*]\033[0m 正在检查配置文件归位状态..."

XRAY_DIR="/usr/local/etc/xray"
BACKUP_DIR="/tmp/xray_config_backup"

# 1. 如果当前配置目录为空或缺失，强制从备份目录无损拉取
if [ ! -d "$XRAY_DIR" ] || [ -z "$(ls -A $XRAY_DIR 2>/dev/null)" ]; then
    if [ -d "$BACKUP_DIR" ] && [ -n "$(ls -A $BACKUP_DIR 2>/dev/null)" ]; then
        echo -e "\033[33m[*]\033[0m 正在从临时隔离区无损还原整个 Xray 配置目录..."
        mkdir -p "$XRAY_DIR"
        # 使用 -aT 参数更安全地将备份目录下的所有文件（含隐藏文件）无损覆盖还原
        cp -aT "$BACKUP_DIR" "$XRAY_DIR"
    else
        echo -e "\033[31m[严重错误] 未找到任何配置备份，无法还原旧节点！\033[0m"
        exit 1
    fi
fi

# 2. 补齐交互菜单 alias，保证终端敲 xray 能顺利进入菜单
for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
    if [ -f "$rc" ]; then
        sed -i '/alias xray=/d' "$rc" 2>/dev/null || true
        echo "alias xray='/usr/local/bin/xray-menu'" >> "$rc"
    fi
done
hash -r 2>/dev/null || true

# 3. 重载 systemd 并强行重启 Xray 服务
echo -e "\033[33m[*]\033[0m 正在刷新服务并唤醒内核程序..."
systemctl daemon-reload
systemctl enable xray >/dev/null 2>&1
systemctl restart xray

# 4. 校验服务与端口状态
sleep 1.5
if systemctl is-active --quiet xray; then
    echo -e "\033[32m[✓] Xray 后台核心服务运行正常 (Active)！\033[0m"
    
    # 打印当前监听端口
    echo -e "\033[33m[*]\033[0m 当前端口监听状态："
    ss -tulnp | grep xray || echo -e "\033[31m[警告] 未检测到 xray 监听端口\033[0m"
    
    echo -e "\n\033[32m[恢复成功] 节点信息已成功无缝复原！\033[0m"
    echo -e "------------------------------------------------------"
    
    # 5. 自动唤醒打印节点看板
    if [ -x "/usr/local/bin/xray-info" ]; then
        /usr/local/bin/xray-info
    fi
else
    echo -e "\033[31m[错误] Xray 服务启动失败！最新日志如下：\033[0m"
    journalctl -u xray --no-pager -n 15
    exit 1
fi
