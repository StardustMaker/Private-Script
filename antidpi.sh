#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
QUEUE_NUM=100; SCRIPT_PATH="/root/gen.py"; SERVICE_NAME="gen"
info() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

detect_os() {
    if [ -f /etc/os-release ]; then . /etc/os-release; OS_ID="$ID"; elif [ -f /etc/redhat-release ]; then OS_ID="centos"; else error "不支持的系统"; fi
    case "$OS_ID" in ubuntu|debian) PKG="apt";; centos|rhel|almalinux|rocky|fedora|amzn) PKG="yum";; *) error "不支持的系统: $OS_ID";; esac
    info "检测到系统: $OS_ID ($PKG)"
}

install_deps() {
    info "安装依赖..."
    if [ "$PKG" = "apt" ]; then
        apt update -qq; apt install -y python3 python3-pip python3-dev gcc build-essential libnetfilter-queue-dev libnfnetlink-dev iptables wget 2>/dev/null
    else
        yum install -y python3 python3-pip python3-devel gcc gcc-c++ libnetfilter_queue-devel libnfnetlink-devel iptables wget 2>/dev/null
    fi
    pip3 install scapy netfilterqueue --break-system-packages 2>/dev/null || pip3 install scapy netfilterqueue 2>/dev/null
    python3 -c "from scapy.all import IP; from netfilterqueue import NetfilterQueue; print('OK')" 2>/dev/null || error "Python依赖安装失败"
    info "依赖安装完成"
}

clean_iptables() { for i in 1 2 3 4 5; do iptables -D OUTPUT -p tcp --sport 443 -j NFQUEUE --queue-num $QUEUE_NUM 2>/dev/null; iptables -D OUTPUT -p tcp --sport 80 -j NFQUEUE --queue-num $QUEUE_NUM 2>/dev/null; done; }

install() {
    echo -e "${CYAN}╔══════════════════════════════════════╗\n║     AntiDPI 一键安装                 ║\n╚══════════════════════════════════════╝${NC}"
    detect_os; install_deps
    info "下载 gen.py..."
    wget -q -O "$SCRIPT_PATH" https://raw.githubusercontent.com/StardustMaker/Private-Script/refs/heads/main/gen.py || error "下载失败"
    info "gen.py 已保存"
    pkill -f "gen.py" 2>/dev/null; sleep 1; clean_iptables
    IPT=$(which iptables 2>/dev/null || echo "/sbin/iptables")
    PY3=$(which python3)
    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=AntiDPI TCP Window Manipulation
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
    systemctl daemon-reload; systemctl enable ${SERVICE_NAME} 2>/dev/null; systemctl start ${SERVICE_NAME}; sleep 2
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        echo -e "\n${GREEN}╔══════════════════════════════════════╗\n║         安装成功！                   ║\n╚══════════════════════════════════════╝${NC}"
        echo -e "\n  管理: bash $0 {status|restart|uninstall}\n"
    else error "启动失败: journalctl -u ${SERVICE_NAME} -e --no-pager"; fi
}

uninstall() {
    warn "正在卸载..."; systemctl stop ${SERVICE_NAME} 2>/dev/null; systemctl disable ${SERVICE_NAME} 2>/dev/null
    rm -f /etc/systemd/system/${SERVICE_NAME}.service; systemctl daemon-reload; pkill -f "gen.py" 2>/dev/null
    clean_iptables; rm -f "$SCRIPT_PATH"; info "卸载完成"
}

status() {
    echo -e "\n${CYAN}━━━ 服务 ━━━${NC}"; systemctl status ${SERVICE_NAME} --no-pager 2>/dev/null || echo "未安装"
    echo -e "\n${CYAN}━━━ 进程 ━━━${NC}"; ps -ef | grep "[g]en.py" || echo "未运行"
    echo -e "\n${CYAN}━━━ iptables ━━━${NC}"; iptables -L OUTPUT -n --line-numbers 2>/dev/null | grep -E "NFQUEUE|Chain" || echo "无规则"; echo ""
}

case "${1:-install}" in
    install) install;; uninstall) uninstall;; status) status;;
    restart) systemctl restart ${SERVICE_NAME}; info "已重启"; systemctl status ${SERVICE_NAME} --no-pager;;
    *) echo "用法: bash $0 {install|uninstall|status|restart}"; exit 1;;
esac
