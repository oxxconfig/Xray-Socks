#!/usr/bin/env bash
# =============================================================================
# Xray 重装后节点激活与状态恢复脚本
# =============================================================================

echo -e "\033[33m[*]\033[0m 正在检查配置文件归位状态..."

# 1. 检查是否存在提前归位的配置文件
if [ ! -f "/usr/local/etc/xray/config.json" ]; then
    echo -e "\033[31m[错误] 未检测到 /usr/local/etc/xray/config.json！\033[0m"
    if [ -f "/tmp/xray_config_backup/config.json" ]; then
        echo -e "\033[33m[*]\033[0m 正在从临时隔离区强行拉取备份恢复..."
        mkdir -p /usr/local/etc/xray
        cp -pf /tmp/xray_config_backup/config.json /usr/local/etc/xray/config.json
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
    ss -tulnp | grep xray || echo -e "\033[31m[警告] 未检测到 xray 监听端口，请检查 config.json 格式是否正确\033[0m"
    
    echo -e "\n\033[32m[恢复成功] 节点信息已成功无缝复原，客户端无需任何修改直接可用！\033[0m"
    echo -e "------------------------------------------------------"
    
    # 5. 自动唤醒打印节点看板
    if [ -x "/usr/local/bin/xray-info" ]; then
        /usr/local/bin/xray-info
    fi
else
    echo -e "\033[31m[错误] Xray 服务启动失败，请运行 systemctl status xray 查看详细日志！\033[0m"
fi
