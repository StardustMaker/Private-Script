#!/usr/bin/env bash

# 用途：测试SMTP/SMTPS连通性与协议握手（不发送邮件）

if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "需要使用bash运行：bash $0"
  exit 1
fi

CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-5}"
TLS_TIMEOUT="${TLS_TIMEOUT:-8}"
SMTP_TIMEOUT="${SMTP_TIMEOUT:-6}"

ONLY_SERVICE=""

if [[ -n "${NO_COLOR:-}" || ! -t 1 ]]; then
  COLOR_RED=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_BLUE=""
  COLOR_CYAN=""
  COLOR_BOLD=""
  COLOR_RESET=""
else
  COLOR_RED="\033[31m"
  COLOR_GREEN="\033[32m"
  COLOR_YELLOW="\033[33m"
  COLOR_BLUE="\033[34m"
  COLOR_CYAN="\033[36m"
  COLOR_BOLD="\033[1m"
  COLOR_RESET="\033[0m"
fi

SERVICES=(
  "Gmail|smtp.gmail.com|25,465,587|谷歌发信"
  "AliyunPersonal|smtp.aliyun.com|25,465,587|阿里云个人邮"
  "AliyunEnterprise|smtp.mxhichina.com|25,465,587|阿里云企业邮"
  "AliyunQiye|smtp.qiye.aliyun.com|25,465,587|阿里云企业邮(另一入口)"
  "QQ|smtp.qq.com|25,465,587|QQ邮箱"
  "Outlook|smtp.office365.com|25,587|Outlook/Office365"
  "Yahoo|smtp.mail.yahoo.com|25,465,587|Yahoo"
  "Mail163|smtp.163.com|25,465,587|163邮箱"
)

if [[ -n "${CUSTOM_SERVICES:-}" ]]; then
  IFS=';' read -r -a CUSTOM_LIST <<< "$CUSTOM_SERVICES"
  for item in "${CUSTOM_LIST[@]}"; do
    [[ -n "$item" ]] && SERVICES+=("$item")
  done
fi

TCP_TOTAL=0
TCP_OK=0
PROTO_TOTAL=0
PROTO_OK=0

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

trim() {
  local input="$1"
  input="${input#"${input%%[![:space:]]*}"}"
  input="${input%"${input##*[![:space:]]}"}"
  printf '%s' "$input"
}

result_line() {
  local label="$1"
  local status="$2"
  local detail="${3:-}"
  local color="$COLOR_RESET"

  case "$status" in
    OK) color="$COLOR_GREEN";;
    FAIL) color="$COLOR_RED";;
    WARN) color="$COLOR_YELLOW";;
    SKIP) color="$COLOR_BLUE";;
    INFO) color="$COLOR_CYAN";;
  esac

  if [[ -n "$detail" ]]; then
    detail=" - $detail"
  fi
  printf '  %-22s %b%-5s%b%s\n' "$label" "$color" "$status" "$COLOR_RESET" "$detail"
}

usage() {
  cat <<'EOF'
用法:
  ./email.sh [--only NAME] [--list]

说明:
  脚本仅用于测试SMTP/SMTPS连通性与协议握手，不发送邮件、不需要账号。

  --only NAME      仅测试指定服务(如 Gmail/QQ/AliyunPersonal)
  --list           列出内置服务名称
EOF
}

list_services() {
  for svc in "${SERVICES[@]}"; do
    IFS='|' read -r name host ports note <<< "$svc"
    printf '%-18s %s (%s)\n' "$name" "$host" "$ports"
  done
}

port_mode() {
  case "$1" in
    465|994) echo "smtps";;
    587) echo "starttls";;
    *) echo "smtp";;
  esac
}

tcp_check() {
  local host="$1"
  local port="$2"
  if has_cmd nc; then
    nc -z -w "$CONNECT_TIMEOUT" "$host" "$port" >/dev/null 2>&1
    return $?
  fi
  if has_cmd timeout; then
    timeout "$CONNECT_TIMEOUT" bash -c "cat < /dev/null > /dev/tcp/$host/$port" >/dev/null 2>&1
    return $?
  fi
  bash -c "cat < /dev/null > /dev/tcp/$host/$port" >/dev/null 2>&1
}

smtp_banner_check() {
  local host="$1"
  local port="$2"
  local banner=""
  if has_cmd timeout; then
    banner=$(timeout "$SMTP_TIMEOUT" bash -c "exec 3<>/dev/tcp/$host/$port; head -n 1 <&3" 2>/dev/null)
  else
    banner=$(bash -c "exec 3<>/dev/tcp/$host/$port; head -n 1 <&3" 2>/dev/null)
  fi
  if [[ "$banner" == 220* ]]; then
    result_line "SMTP Banner" "OK" "$banner"
    return 0
  fi
  result_line "SMTP Banner" "WARN" "${banner:-无响应}"
  return 1
}

tls_handshake_check() {
  local host="$1"
  local port="$2"
  local mode="$3"
  if ! has_cmd openssl; then
    result_line "TLS Handshake" "WARN" "openssl未安装"
    return 2
  fi

  local -a cmd=(openssl s_client -connect "${host}:${port}" -servername "$host" -crlf -quiet)
  if [[ "$mode" == "starttls" ]]; then
    cmd+=( -starttls smtp )
  fi

  local output=""
  if has_cmd timeout; then
    output=$(timeout "$TLS_TIMEOUT" "${cmd[@]}" </dev/null 2>&1 || true)
  else
    output=$("${cmd[@]}" </dev/null 2>&1 || true)
  fi

  if echo "$output" | grep -qE 'SSL-Session|Cipher is|TLSv'; then
    result_line "TLS Handshake" "OK" "握手完成"
    return 0
  fi
  result_line "TLS Handshake" "FAIL" "握手失败"
  return 1
}

test_service() {
  local name="$1"
  local host="$2"
  local ports="$3"
  local note="$4"

  echo
  printf '%b==> %s%b (%s) %s\n' "$COLOR_BOLD" "$name" "$COLOR_RESET" "$host" "${note:+- $note}"

  IFS=',' read -r -a port_list <<< "$ports"
  for port in "${port_list[@]}"; do
    port="$(trim "$port")"
    [[ -z "$port" ]] && continue
    local mode
    mode="$(port_mode "$port")"

    TCP_TOTAL=$((TCP_TOTAL + 1))
    if tcp_check "$host" "$port"; then
      TCP_OK=$((TCP_OK + 1))
      result_line "TCP $port" "OK" "连通"
    else
      result_line "TCP $port" "FAIL" "无法连接"
      continue
    fi

    PROTO_TOTAL=$((PROTO_TOTAL + 1))
    if [[ "$mode" == "smtp" ]]; then
      if smtp_banner_check "$host" "$port"; then
        PROTO_OK=$((PROTO_OK + 1))
      fi
    else
      if tls_handshake_check "$host" "$port" "$mode"; then
        PROTO_OK=$((PROTO_OK + 1))
      fi
    fi
  done

}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--only)
      ONLY_SERVICE="$2"
      shift 2
      ;;
    -l|--list)
      list_services
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数：$1"
      usage
      exit 1
      ;;
  esac
done

echo -e "${COLOR_BOLD}SMTP/SMTPS 发信能力与通断测试${COLOR_RESET}"
printf '时间: %s\n' "$(date '+%F %T')"

for svc in "${SERVICES[@]}"; do
  IFS='|' read -r name host ports note <<< "$svc"
  if [[ -n "$ONLY_SERVICE" && "$name" != "$ONLY_SERVICE" ]]; then
    continue
  fi
  test_service "$name" "$host" "$ports" "$note"
done
