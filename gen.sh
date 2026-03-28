#!/bin/bash

# ============================================
# Gen TCP混淆 一键安装脚本
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
SCRIPT_URL="$GITHUB_RAW/gen.sh"
LOCAL_MODE=false

ENABLE_SEQ_CONFUSION=true
SEQ_OFFSET_MIN=-500
SEQ_OFFSET_MAX=500

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step() { echo -e "${BLUE}[→]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════╗"
    echo "║         Gen TCP混淆 一键安装             ║"
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
    
    echo -e "${CYAN}[3/5]${NC} 获取程序文件..."
    
    if [ "$LOCAL_MODE" = true ]; then
        LOCAL_GEN="$SCRIPT_DIR/gen.py"
        if [ -f "$LOCAL_GEN" ]; then
            cp "$LOCAL_GEN" "$SCRIPT_PATH"
            info "使用本地文件: $LOCAL_GEN"
        else
            error "本地文件不存在: $LOCAL_GEN"
        fi
    else
        wget -q -O "$SCRIPT_PATH" "$GITHUB_RAW/gen.py" || error "下载 gen.py 失败"
        info "从 GitHub 下载完成"
    fi
    
    info "程序文件已保存到 $SCRIPT_PATH"
    
    echo -e "${CYAN}[4/5]${NC} 配置系统服务..."
    pkill -f "gen.py" 2>/dev/null
    sleep 1
    clean_iptables
    
    IPT=$(which iptables 2>/dev/null || echo "/sbin/iptables")
    PY3=$(which python3)
    
    SEQ_CONFUSION_ARGS=""
    if [ "$ENABLE_SEQ_CONFUSION" = true ]; then
        SEQ_CONFUSION_ARGS="-e --seq_offset_min ${SEQ_OFFSET_MIN} --seq_offset_max ${SEQ_OFFSET_MAX}"
    fi
    
    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Gen TCP Window Obfuscation
After=network.target

[Service]
Type=simple
ExecStartPre=/bin/bash -c '${IPT} -C OUTPUT -p tcp --sport 443 -j NFQUEUE --queue-num ${QUEUE_NUM} 2>/dev/null || ${IPT} -I OUTPUT -p tcp --sport 443 -j NFQUEUE --queue-num ${QUEUE_NUM}'
ExecStartPre=/bin/bash -c '${IPT} -C OUTPUT -p tcp --sport 80 -j NFQUEUE --queue-num ${QUEUE_NUM} 2>/dev/null || ${IPT} -I OUTPUT -p tcp --sport 80 -j NFQUEUE --queue-num ${QUEUE_NUM}'
ExecStart=${PY3} ${SCRIPT_PATH} -q ${QUEUE_NUM} -w 1 -s 7 -c 7 -n 7 ${SEQ_CONFUSION_ARGS}
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
        if [ "$ENABLE_SEQ_CONFUSION" = true ]; then
            echo -e "  ${CYAN}序列号干扰:${NC} ${GREEN}已启用${NC}"
            echo -e "  ${CYAN}偏移范围:${NC} ${SEQ_OFFSET_MIN} ~ ${SEQ_OFFSET_MAX}"
        fi
        echo ""
        echo -e "  ${YELLOW}管理命令:${NC}"
        echo -e "    查看状态: bash <(curl -L -s $SCRIPT_URL) status"
        echo -e "    重启服务: bash <(curl -L -s $SCRIPT_URL) restart"
        echo -e "    卸载程序: bash <(curl -L -s $SCRIPT_URL) uninstall"
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
        
        CMD=$(ps -p $PID -o args= 2>/dev/null)
        if echo "$CMD" | grep -q "\-e"; then
            echo -e "  序列号干扰: ${GREEN}已启用${NC}"
        fi
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
    echo -e "  重启服务: ${YELLOW}bash <(curl -L -s $SCRIPT_URL) restart${NC}"
    echo -e "  卸载程序: ${YELLOW}bash <(curl -L -s $SCRIPT_URL) uninstall${NC}"
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

show_help() {
    print_banner
    echo -e "  ${CYAN}用法:${NC}"
    echo ""
    echo -e "  ${YELLOW}本地模式 (使用同目录下的 gen.py):${NC}"
    echo -e "    bash $0 --local install              安装 Gen TCP混淆 (使用本地文件)"
    echo -e "    bash $0 -l install                   安装 Gen TCP混淆 (使用本地文件)"
    echo ""
    echo -e "  ${YELLOW}在线模式 (从 GitHub 下载):${NC}"
    echo -e "    bash $0 install                      安装 Gen TCP混淆 (基础模式)"
    echo -e "    bash $0 --seq install                安装并启用序列号干扰"
    echo -e "    bash $0 --seq --offset-min -1000 --offset-max 1000 install"
    echo -e "                                         自定义序列号偏移范围"
    echo -e "    bash $0 uninstall                    卸载 Gen TCP混淆"
    echo -e "    bash $0 status                       查看状态"
    echo -e "    bash $0 restart                      重启服务"
    echo ""
    echo -e "  ${YELLOW}序列号干扰参数:${NC}"
    echo -e "    --seq                  启用序列号干扰增强防检测"
    echo -e "    --offset-min <num>     序列号偏移最小值 (默认: -500)"
    echo -e "    --offset-max <num>     序列号偏移最大值 (默认: 500)"
    echo ""
    echo -e "  ${YELLOW}远程一键安装:${NC}"
    echo -e "    bash <(curl -L -s $SCRIPT_URL) install"
    echo -e "    bash <(curl -L -s $SCRIPT_URL) --seq install"
    echo ""
    exit 1
}

for arg in "$@"; do
    case "$arg" in
        --local|-l)
            LOCAL_MODE=true
            ;;
        --seq)
            ENABLE_SEQ_CONFUSION=true
            ;;
        --offset-min)
            shift
            SEQ_OFFSET_MIN="$1"
            ;;
        --offset-max)
            shift
            SEQ_OFFSET_MAX="$1"
            ;;
    esac
done

ACTION=""
for arg in "$@"; do
    case "$arg" in
        --local|-l|--seq|--offset-min|--offset-max) ;;
        -[0-9]*) ;;
        [0-9]*) ;;
        *) ACTION="$arg" ;;
    esac
done

case "${ACTION:-install}" in
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
    -h|--help|help)
        show_help
        ;;
    *)
        show_help
        ;;
esac
