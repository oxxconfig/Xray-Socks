# 1. 停止并禁用 xray 相关的系统服务
systemctl stop xray xray-script 2>/dev/null
systemctl disable xray xray-script 2>/dev/null

# 2. 清理系统服务文件
rm -f /etc/systemd/system/xray.service /etc/systemd/system/xray-script.service
systemctl daemon-reload

# 3. 清理二进制文件、配置目录及日志
rm -rf /usr/local/xray-script \
       /usr/local/bin/xray \
       /usr/local/bin/xray-bin \
       /usr/local/bin/xray-info \
       /usr/local/etc/xray \
       /usr/local/share/xray \
       /var/log/xray \
       ~/.xray-script

# 4. 清理可能残留的快捷别名配置
sed -i '/alias xray=/d' ~/.bashrc ~/.zshrc ~/.profile 2>/dev/null
rm -f /etc/profile.d/xray.sh

# 5. 刷新命令缓存
hash -r

echo -e "\033[32m[提示] Xray 及管理脚本已彻底卸载清理完成！\033[0m"
