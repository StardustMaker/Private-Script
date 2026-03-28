#!/bin/bash

# ============================================
# AntiDPI 一键安装脚本
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

QUEUE_NUM=100
SCRIPT_PATH="/root/gen.py"
SERVICE_NAME="gen"
GITHUB_RAW="https://raw.githubusercontent.com/StardustMaker/Private-Script/refs/heads/main"

info() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step() { echo -e "${BLUE}[→]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════╗"
    echo "║          AntiDPI 一键安装脚本            ║"
    echo "║          TCP 流量混淆工具                ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_line() {
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
    elif [ -f /etc/redhat-release ]; then
        OS_ID="centos"
    else
        error "无法检测操作系统"
    fi
    
    case "$OS_ID" in
        ubuntu|debian) PKG="apt" ;;
        centos|rhel|almalinux|rocky|fedora|amzn) PKG="yum" ;;
        *) error "不支持的系统: $OS_ID" ;;
    esac
    
    info "系统: $OS_ID ($PKG)"
}

install_deps() {
    step "正在安装依赖包..."
    
    if [ "$PKG" = "apt" ]; then
        apt update -qq 2>/dev/null
        apt install -y python3 python3-pip python3-dev gcc build-essential \
            libnetfilter-queue-dev libnfnetlink-dev iptables wget 2>/dev/null
    else
        yum install -y python3 python3-pip python3-devel gcc gcc-c++ \
            libnetfilter_queue-devel libnfnetlink-devel iptables wget 2>/dev/null
    fi
    
    step "正在安装 Python 依赖..."
    pip3 install scapy netfilterqueue --break-system-packages 2>/dev/null || \
        pip3 install scapy netfilterqueue 2>/dev/null
    
    python3 -c "from scapy.all import IP; from netfilterqueue import NetfilterQueue" 2>/dev/null || \
        error "Python 依赖安装失败"
    
    info "依赖安装完成"
}

clean_iptables() {
    for i in 1 2 3 4 5; do
        iptables -D OUTPUT -p tcp --sport 443 -j NFQUEUE --queue-num $QUEUE_NUM 2>/dev/null
        iptables -D OUTPUT -p tcp --sport 80 -j NFQUEUE --queue-num $QUEUE_NUM 2>/dev/null
    done
}

install() {
    print_banner
    
    echo -e "${CYAN}[1/5]${NC} 检测系统环境..."
    detect_os
    
    echo -e "${CYAN}[2/5]${NC} 安装依赖..."
    install_deps
    
    echo -e "${CYAN}[3/5]${NC} 下载程序文件..."
    wget -q -O "$SCRIPT_PATH" "$GITHUB_RAW/gen.py" || error "下载 gen.py 失败"
    info "程序文件已保存到 $SCRIPT_PATH"
    
    echo -e "${CYAN}[4/5]${NC} 配置系统服务..."
    pkill -f "gen.py" 2>/dev/null
    sleep 1
    clean_iptables
    
    IPT=$(which iptables 2>/dev/null || echo "/sbin/iptables")
    PY3=$(which python3)
    
    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=AntiDPI TCP Window Obfuscation
After=network.target

[Service]
Type=simple
ExecStartPre=/bin/bash -c '${IPT} -C OUTPUT -p tcp --sport 443 -j NFQUEUE --queue-num ${QUEUE_NUM} 2>/dev/null || ${IPT} -I OUTPUT -p tcp --sport 443 -j NFQUEUE --queue-num ${QUEUE_NUM}'
ExecStartPre=/bin/bash -c '${IPT} -C OUTPUT -p tcp --sport 80 -j NFQUEUE --queue-num ${QUEUE_NUM} 2>/dev/null || ${IPT} -I OUTPUT -p tcp --sport 80 -j NFQUEUE --queue-num ${QUEUE_NUM}'
ExecStart=${PY3} ${SCRIPT_PATH} -q ${QUEUE_NUM} -w 1 -s 7 -c 7 -n 7
ExecStopPost=/bin/bash -c '${IPT} -D OUTPUT -p tcp --sport 443 -j NFQUEUE --queue-num ${QUEUE_NUM} 2>/dev/null; true'
ExecStopPost=/bin/bash -c '${IPT} -D OUTPUT -p tcp --sport 80 -j NFQUEUE --queue-num ${QUEUE_NUM} 2>/dev/null; true'
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    
    echo -e "${CYAN}[5/5]${NC} 启动服务..."
    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME} 2>/dev/null
    systemctl start ${SERVICE_NAME}
    sleep 2
    
    print_line
    
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        echo -e "${GREEN}"
        echo "╔══════════════════════════════════════════╗"
        echo "║            安装成功！                    ║"
        echo "╚══════════════════════════════════════════╝"
        echo -e "${NC}"
        echo -e "  ${CYAN}服务状态:${NC} 运行中"
        echo -e "  ${CYAN}程序路径:${NC} $SCRIPT_PATH"
        echo -e "  ${CYAN}服务名称:${NC} $SERVICE_NAME"
        echo ""
        echo -e "  ${YELLOW}管理命令:${NC}"
        echo -e "    查看状态: bash $0 status"
        echo -e "    重启服务: bash $0 restart"
        echo -e "    卸载程序: bash $0 uninstall"
        echo ""
    else
        error "服务启动失败，请检查: journalctl -u ${SERVICE_NAME} -e --no-pager"
    fi
}

uninstall() {
    print_banner
    
    echo -e "${CYAN}[1/4]${NC} 停止服务..."
    systemctl stop ${SERVICE_NAME} 2>/dev/null
    systemctl disable ${SERVICE_NAME} 2>/dev/null
    info "服务已停止"
    
    echo -e "${CYAN}[2/4]${NC} 清理 iptables 规则..."
    clean_iptables
    info "iptables 规则已清理"
    
    echo -e "${CYAN}[3/4]${NC} 删除服务文件..."
    rm -f /etc/systemd/system/${SERVICE_NAME}.service
    systemctl daemon-reload
    pkill -f "gen.py" 2>/dev/null
    info "服务文件已删除"
    
    echo -e "${CYAN}[4/4]${NC} 删除程序文件..."
    rm -f "$SCRIPT_PATH"
    info "程序文件已删除"
    
    print_line
    
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════╗"
    echo "║            卸载完成！                    ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${CYAN}所有组件已清理完毕${NC}"
    echo ""
}

status() {
    print_banner
    
    print_line
    echo -e "${CYAN}  服务状态${NC}"
    print_line
    
    if systemctl is-active --quiet ${SERVICE_NAME} 2>/dev/null; then
        echo -e "  状态:     ${GREEN}● 运行中${NC}"
        echo -e "  开机启动: ${GREEN}● 已启用${NC}"
    else
        if [ -f /etc/systemd/system/${SERVICE_NAME}.service ]; then
            echo -e "  状态:     ${RED}● 已停止${NC}"
            echo -e "  开机启动: ${YELLOW}● 已禁用${NC}"
        else
            echo -e "  状态:     ${RED}● 未安装${NC}"
        fi
    fi
    
    echo ""
    print_line
    echo -e "${CYAN}  进程信息${NC}"
    print_line
    
    PID=$(pgrep -f "gen.py" 2>/dev/null)
    if [ -n "$PID" ]; then
        echo -e "  PID:      $PID"
        echo -e "  内存:     $(ps -p $PID -o rss= 2>/dev/null | awk '{printf "%.1f MB", $1/1024}')"
        echo -e "  CPU:      $(ps -p $PID -o %cpu= 2>/dev/null | awk '{printf "%.1f%%", $1}')"
        echo -e "  运行时间: $(ps -p $PID -o etime= 2>/dev/null | xargs)"
    else
        echo -e "  ${YELLOW}无运行进程${NC}"
    fi
    
    echo ""
    print_line
    echo -e "${CYAN}  iptables 规则${NC}"
    print_line
    
    RULES=$(iptables -L OUTPUT -n 2>/dev/null | grep -c "NFQUEUE" 2>/dev/null)
    if [ "$RULES" -gt 0 ]; then
        echo -e "  规则数量: ${GREEN}$RULES 条${NC}"
        iptables -L OUTPUT -n --line-numbers 2>/dev/null | grep "NFQUEUE" | while read line; do
            echo -e "  ${CYAN}→${NC} $line"
        done
    else
        echo -e "  ${YELLOW}无 NFQUEUE 规则${NC}"
    fi
    
    echo ""
    print_line
    echo -e "${CYAN}  管理命令${NC}"
    print_line
    echo -e "  重启服务: ${YELLOW}bash $0 restart${NC}"
    echo -e "  卸载程序: ${YELLOW}bash $0 uninstall${NC}"
    echo ""
}

restart() {
    print_banner
    
    if [ ! -f /etc/systemd/system/${SERVICE_NAME}.service ]; then
        error "服务未安装，请先执行安装"
    fi
    
    step "正在重启服务..."
    systemctl restart ${SERVICE_NAME}
    sleep 1
    
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        info "服务重启成功"
    else
        error "服务重启失败"
    fi
}

case "${1:-install}" in
    install)
        install
        ;;
    uninstall)
        uninstall
        ;;
    status)
        status
        ;;
    restart)
        restart
        ;;
    *)
        print_banner
        echo -e "  ${CYAN}用法:${NC}"
        echo -e "    bash $0 install     安装 AntiDPI"
        echo -e "    bash $0 uninstall   卸载 AntiDPI"
        echo -e "    bash $0 status      查看状态"
        echo -e "    bash $0 restart     重启服务"
        echo ""
        exit 1
        ;;
esac
