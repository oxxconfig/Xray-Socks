#!/usr/bin/env bash
# =============================================================================
# Xray 纯净无损清理脚本（完美保留 PBK、UUID 及节点配置）
# =============================================================================

echo -e "\033[33m[*]\033[0m 正在提取现有私钥(PrivateKey)与核心配置文件..."

# 0. 建立临时安全隔离区
BACKUP_DIR="/tmp/xray_config_backup"
rm -rf "${BACKUP_DIR}" && mkdir -p "${BACKUP_DIR}"

HAS_BACKUP=0

# 备份核心配置文件（包含 VLESS UUID、Socks5 密码、REALITY PrivateKey 等核心命脉）
if [ -f "/usr/local/etc/xray/config.json" ]; then
    cp -pf /usr/local/etc/xray/config.json "${BACKUP_DIR}/config.json"
    HAS_BACKUP=1
    echo -e "\033[32m[✓]\033[0m 成功提取核心配置文件，PBK 与 ID 数据已锁定至: ${BACKUP_DIR}/config.json"
else
    echo -e "\033[31m[!]\033[0m 未检测到当前节点的 config.json，本次清理后重装将生成全新节点配置。"
fi

# 备份面板/脚本的运行环境依赖（防止安装脚本判定为首次全新安装）
if [ -d "${HOME}/.xray-script" ]; then
    cp -rpf "${HOME}/.xray-script" "${BACKUP_DIR}/.xray-script"
    echo -e "\033[32m[✓]\033[0m 面板运行记录已锁定"
fi

echo -e "\n\033[33m[*]\033[0m 开始对系统进行深度清理 (清理旧版程序包、服务及快捷键)..."

# 1. 强行终止关联服务
systemctl stop xray xray-script 2>/dev/null
systemctl disable xray xray-script 2>/dev/null

# 2. 拔除 systemd 服务驻留
rm -f /etc/systemd/system/xray.service /etc/systemd/system/xray-script.service
systemctl daemon-reload

# 3. 彻底删除核心与相关扩展 (确保后续 install 时拉取全新二进制)
rm -rf /usr/local/xray-script \
       /usr/local/bin/xray \
       /usr/local/bin/xray-bin \
       /usr/local/bin/xray-menu \
       /usr/local/bin/xray-info \
       /usr/local/etc/xray \
       /usr/local/share/xray \
       /var/log/xray \
       "${HOME}/.xray-script"

# 4. 剔除环境变量及终端 alias 污染
sed -i '/alias xray=/d' ~/.bashrc ~/.zshrc ~/.profile 2>/dev/null
rm -f /etc/profile.d/xray.sh
hash -r 2>/dev/null || true

echo -e "\033[32m[✓]\033[0m 系统环境清理完毕。\n"

# =============================================================================
# 关键防御动作：前置布设原配置数据
# 作用：让稍后运行的 install.sh 在探测阶段识别到现有配置，跳过密钥对重新生成
# =============================================================================
echo -e "\033[33m[*]\033[0m 正在将配置数据归位布置..."

if [ ${HAS_BACKUP} -eq 1 ]; then
    # 提前建好核心目录，归位配置
    mkdir -p /usr/local/etc/xray
    cp -pf "${BACKUP_DIR}/config.json" /usr/local/etc/xray/config.json
    
    # 归位脚本运行环境
    if [ -d "${BACKUP_DIR}/.xray-script" ]; then
        cp -rpf "${BACKUP_DIR}/.xray-script" "${HOME}/.xray-script"
    fi
    
    echo -e "\033[32m[安全完成]\033[0m 已成功预置原 config.json 及私钥数据！\n"
    echo -e "\033[36m👉 接下来您可以放心地直接运行一键安装脚本。\033[0m"
    echo -e "\033[36m👉 新部署的程序会自动接管旧配置，客户端无需更改任何 PBK/ID 即可无缝重连！\033[0m"
else
    echo -e "\033[31m[提醒]\033[0m 由于未提取到旧配置，接下来的安装将是全新部署状态。"
fi
