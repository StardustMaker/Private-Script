#!/bin/bash

# ========== 配置区 ==========
CURL_ARGS="$useNIC $usePROXY $xForward $resolve $dns --max-time 10"
UA_BROWSER="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

# 测试地址
TEST_URLS=(
    "https://www.netflix.com/title/81280792"  # LEGO Ninjago
    "https://www.netflix.com/title/70143836"  # Breaking Bad
)

# 颜色定义
readonly COLOR_RED="\033[31m"
readonly COLOR_GREEN="\033[32m"
readonly COLOR_YELLOW="\033[33m"
readonly COLOR_RESET="\033[0m"

# ========== 函数定义 ==========

# 获取 HTTP 状态码
get_http_code() {
    local url="$1"
    curl $CURL_ARGS -4 \
        --user-agent "${UA_BROWSER}" \
        -fsLI -X GET \
        --write-out '%{http_code}' \
        --output /dev/null \
        --tlsv1.3 \
        "$url" 2>&1
}

# 获取地区代码
get_region() {
    local redirect_url
    redirect_url=$(curl $CURL_ARGS -4 \
        -fSsI -X GET \
        --user-agent "${UA_BROWSER}" \
        --write-out '%{redirect_url}' \
        --output /dev/null \
        --tlsv1.3 \
        "https://www.netflix.com/login" 2>&1)
    
    # 更健壮的地区提取：支持 /cn-zh/ 和 /browse 等格式
    if [[ "$redirect_url" =~ /([a-z]{2})-[a-z]{2}/ ]]; then
        echo "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]'
    elif [[ "$redirect_url" =~ netflix\.com/([a-z]{2})/ ]]; then
        echo "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]'
    else
        echo "US"  # 默认美国
    fi
}

# 输出结果
print_result() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${COLOR_RESET}"
}

# ========== 主逻辑 ==========

# 并发测试两个 URL
results=()
for url in "${TEST_URLS[@]}"; do
    results+=("$(get_http_code "$url")")
done

result1="${results[0]}"
result2="${results[1]}"

# 调试信息（可选）
# echo "[DEBUG] result1=$result1, result2=$result2"

# ========== 判断逻辑（使用 elif 避免重复输出）==========

# 1. 网络问题
if [[ "$result1" == "000" ]] || [[ "$result2" == "000" ]]; then
    print_result "$COLOR_RED" "检测失败：网络连接超时"
    exit 1

# 2. 完全不支持（被封禁）
elif [[ "$result1" == "403" ]] && [[ "$result2" == "403" ]]; then
    print_result "$COLOR_RED" "不支持解锁：IP 已被 Netflix 识别"
    exit 1

# 3. 部分支持或检测不准确
elif [[ "$result1" == "403" ]] || [[ "$result2" == "403" ]]; then
    print_result "$COLOR_YELLOW" "部分内容受限：可能仅支持部分地区内容"
    
# 4. 仅自制剧
elif [[ "$result1" == "404" ]] && [[ "$result2" == "404" ]]; then
    print_result "$COLOR_YELLOW" "仅支持自制剧：非自制内容不可用"

# 5. 完整解锁
elif [[ "$result1" == "200" ]] || [[ "$result2" == "200" ]]; then
    region=$(get_region)
    if [[ -n "$region" ]]; then
        print_result "$COLOR_GREEN" "完整解锁非自制剧 | 地区: $region"
    else
        print_result "$COLOR_GREEN" "完整解锁非自制剧 | 地区: 未知"
    fi

# 6. 未知状态
else
    print_result "$COLOR_YELLOW" "? 未知状态: result1=$result1, result2=$result2"
fi
