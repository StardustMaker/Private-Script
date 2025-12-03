#!/bin/bash

# =========================================================
# Realm 一键安装配置脚本
# =========================================================

# --- 基础设置 ---
# 遇到错误立即停止 (除了部分特定检查)
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

# 检查 Root 权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 请使用 sudo 或 root 用户运行此脚本！${PLAIN}"
    exit 1
fi

# 变量定义
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/realm"
SERVICE_FILE="/etc/systemd/system/realm.service"
DEFAULT_VERSION="v2.9.2-2"  # 如果获取最新版失败，使用此备用版本

# --- 函数定义 ---

# 1. 环境与架构检测
check_env() {
    echo -e "${GREEN}>>> 正在检查系统环境...${PLAIN}"
    
    # 安装必要工具
    local DEPS="wget tar"
    if ! command -v wget &> /dev/null || ! command -v tar &> /dev/null; then
        echo "安装依赖: ${DEPS}..."
        if command -v apt &> /dev/null; then
            apt update -q && apt install -y -q $DEPS
        elif command -v yum &> /dev/null; then
            yum install -y -q $DEPS
        else
            echo -e "${RED}无法自动安装依赖，请手动安装: wget tar${PLAIN}"
            exit 1
        fi
    fi

    # 架构检测
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  REALM_ARCH="x86_64-unknown-linux-gnu" ;;
        aarch64) REALM_ARCH="aarch64-unknown-linux-gnu" ;;
        armv7l)  REALM_ARCH="arm-unknown-linux-gnueabi" ;;
        *)       echo -e "${RED}不支持的架构: ${ARCH}${PLAIN}"; exit 1 ;;
    esac
    echo -e "系统架构: ${SKYBLUE}${ARCH}${PLAIN} (匹配: ${REALM_ARCH})"
}

# 2. 获取最新版本
get_latest_version() {
    echo -e "${GREEN}>>> 正在获取 Realm 最新版本信息...${PLAIN}"
    # 尝试通过 GitHub API 获取最新 tag
    LATEST_TAG=$(wget -qO- -t1 -T2 "https://api.github.com/repos/zhboner/realm/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    
    if [[ -z "$LATEST_TAG" ]]; then
        echo -e "${YELLOW}获取最新版本失败，使用默认版本: ${DEFAULT_VERSION}${PLAIN}"
        REALM_VERSION="${DEFAULT_VERSION}"
    else
        echo -e "检测到最新版本: ${SKYBLUE}${LATEST_TAG}${PLAIN}"
        REALM_VERSION="${LATEST_TAG}"
    fi
}

# 3. 用户配置
configure_realm() {
    echo -e "${GREEN}>>> 配置转发规则...${PLAIN}"
    
    # 获取本地端口
    while true; do
        read -p "请输入本地监听端口 [默认: 8848]: " LOCAL_PORT
        LOCAL_PORT=${LOCAL_PORT:-8848}
        if [[ ! $LOCAL_PORT =~ ^[0-9]+$ ]] || [ $LOCAL_PORT -lt 1 ] || [ $LOCAL_PORT -gt 65535 ]; then
            echo -e "${RED}端口无效，请输入 1-65535 之间的数字。${PLAIN}"
        else
            # 简单检查端口占用 (如果 lsof 存在)
            if command -v lsof &> /dev/null; then
                if lsof -i :$LOCAL_PORT > /dev/null; then
                    echo -e "${YELLOW}警告: 端口 $LOCAL_PORT 似乎已被占用，可能导致启动失败。${PLAIN}"
                    read -p "是否继续? (y/n): " confirm
                    [[ "$confirm" != "y" ]] && continue
                fi
            fi
            break
        fi
    done

    # 获取目标地址
    while true; do
        read -p "请输入目标地址 (IP:端口) [例如 1.1.1.1:443]: " REMOTE_ADDR
        if [[ -z "$REMOTE_ADDR" ]]; then
            echo -e "${RED}目标地址不能为空。${PLAIN}"
        else
            break
        fi
    done
}

# 4. 安装核心逻辑
install_realm() {
    echo -e "${GREEN}>>> 开始下载与安装...${PLAIN}"
    cd /tmp
    
    # 构造下载链接
    DOWNLOAD_URL="https://github.com/zhboner/realm/releases/download/${REALM_VERSION}/realm-${REALM_ARCH}.tar.gz"
    echo "下载地址: $DOWNLOAD_URL"
    
    if ! wget -O realm.tar.gz "$DOWNLOAD_URL"; then
        echo -e "${RED}下载失败！请检查网络连接或版本号是否存在。${PLAIN}"
        exit 1
    fi

    tar -xzf realm.tar.gz
    
    # 查找二进制文件 (兼容不同版本的压缩包结构)
    if [ -f "realm" ]; then
        BINARY="realm"
    elif [ -f "realm-${REALM_ARCH}" ]; then
        BINARY="realm-${REALM_ARCH}"
    else
        # 尝试暴力搜索
        BINARY=$(find . -type f -name "realm" | head -n 1)
    fi

    if [[ -z "$BINARY" || ! -f "$BINARY" ]]; then
         echo -e "${RED}错误: 解压后找不到 realm 二进制文件。${PLAIN}"
         ls -R
         exit 1
    fi

    # 停止旧服务
    systemctl stop realm 2>/dev/null || true

    # 移动文件
    cp "$BINARY" "${INSTALL_DIR}/realm"
    chmod +x "${INSTALL_DIR}/realm"
    rm -f realm.tar.gz "$BINARY"
    echo -e "Realm 二进制文件已安装到: ${INSTALL_DIR}/realm"
}

# 5. 生成配置
write_config() {
    echo -e "${GREEN}>>> 生成配置文件...${PLAIN}"
    mkdir -p "${CONFIG_DIR}"

    # 注意: Realm v2.x 标准配置语法为 [[endpoints]]
    cat > "${CONFIG_DIR}/config.toml" <<EOF
[network]
no_tcp = false
use_udp = true

[[endpoints]]
listen = "0.0.0.0:${LOCAL_PORT}"
remote = "${REMOTE_ADDR}"
EOF
}

# 6. 配置系统服务
setup_service() {
    echo -e "${GREEN}>>> 配置 Systemd 服务...${PLAIN}"
    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Realm Network Relay Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${INSTALL_DIR}/realm -c ${CONFIG_DIR}/config.toml
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable realm
    systemctl restart realm
}

# 7. 防火墙配置
setup_firewall() {
    if command -v ufw &> /dev/null && systemctl is-active --quiet ufw; then
        echo -e "${GREEN}>>> 检测到 UFW，正在放行端口 ${LOCAL_PORT}...${PLAIN}"
        ufw allow "${LOCAL_PORT}/tcp" >/dev/null
        ufw allow "${LOCAL_PORT}/udp" >/dev/null
        ufw reload
    fi
    # 提示用户
    echo -e "${YELLOW}提示: 如果使用云服务器(AWS/Oracle/阿里云等)，请务必在后台安全组放行端口 ${LOCAL_PORT}${PLAIN}"
}

# 8. 状态检查
check_status() {
    sleep 2
    if systemctl is-active --quiet realm; then
        echo -e ""
        echo -e "${GREEN}=========================================${PLAIN}"
        echo -e "${GREEN}      ✅ Realm 安装成功并已启动！      ${PLAIN}"
        echo -e "${GREEN}=========================================${PLAIN}"
        echo -e " 版本: ${SKYBLUE}${REALM_VERSION}${PLAIN}"
        echo -e " 监听: ${SKYBLUE}0.0.0.0:${LOCAL_PORT}${PLAIN}"
        echo -e " 转发: ${SKYBLUE}${REMOTE_ADDR}${PLAIN}"
        echo -e " 配置: ${CONFIG_DIR}/config.toml"
        echo -e "-----------------------------------------"
        echo -e " 查看日志: sudo journalctl -u realm -f"
        echo -e " 重启服务: sudo systemctl restart realm"
        echo -e "${GREEN}=========================================${PLAIN}"
    else
        echo -e "${RED}❌ 服务启动失败！${PLAIN}"
        echo "请检查以下日志："
        systemctl status realm --no-pager -l
        journalctl -u realm --no-pager -n 10
    fi
}

# --- 主程序执行 ---
check_env
get_latest_version
configure_realm
install_realm
write_config
setup_service
setup_firewall
check_status