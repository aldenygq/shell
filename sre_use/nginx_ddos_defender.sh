#!/bin/bash

# Nginx DDoS攻击检测与防御脚本
# 脚本功能说明
#此脚本能够实时监控 Nginx 访问日志，自动识别并防御 DDoS 攻击，主要功能包括：
#1、实时监控：定期分析 Nginx 访问日志，检测异常流量模式
# 智能识别：通过请求频率阈值和突发流量检测识别潜在 DDoS 攻击
# 自动防御：发现攻击后自动封禁恶意 IP，并更新 Nginx 配置
# 邮件告警：当检测到超过阈值的攻击时发送邮件通知管理员
# 可视化统计：生成攻击历史图表和当前封禁 IP 列表的 HTML 报告
# IP 白名单：支持配置信任 IP / 网段，避免误封合法流量
# 自动解封：封禁 IP 一段时间后自动解封，避免长期封禁

# 脚本使用方法
#1、将脚本保存为nginx_ddos_defender.sh并赋予执行权限
#2、根据需要修改脚本开头的配置参数
#3、测试运行：./nginx_ddos_defender.sh check
#4、作为守护进程运行：./nginx_ddos_defender.sh daemon

# 配置建议
#1、根据服务器性能和流量特点调整THRESHOLD和BURST_THRESHOLD参数
#2、配置有效的ALERT_EMAIL以接收攻击告警
#3、添加内部网络和已知信任 IP 到WHITELIST_IPS
#4、如需长期监控，建议将脚本添加到系统服务中自动启动

# 配置参数
LOG_FILE="/var/log/nginx/access.log"          # Nginx访问日志路径
BLOCK_FILE="/etc/nginx/block_ips.conf"        # 封禁IP配置文件
TEMP_FILE="/tmp/ddos_ips.tmp"                 # 临时文件
THRESHOLD=300                                  # 请求阈值(每分钟)
BURST_THRESHOLD=1000                           # 突发流量阈值
BAN_TIME=3600                                  # 封禁时间(秒)
CHECK_INTERVAL=30                              # 检查间隔(秒)
NGINX_RELOAD_CMD="nginx -s reload"            # Nginx重载命令
MAX_BLOCKED_IPS=5000                           # 最大封禁IP数
ALERT_EMAIL="admin@example.com"                # 告警邮箱
ALERT_THRESHOLD=500                            # 触发告警的请求数
WHITELIST_IPS="192.168.1.0/24 10.0.0.0/8"    # 白名单IP段
LOG_RETENTION=7                                # 日志保留天数(天)
ENABLE_VISUALIZATION=1                         # 是否启用可视化(1=启用,0=禁用)
VISUALIZATION_DIR="/var/www/ddos_stats"        # 可视化数据目录

# 日志函数
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message"
    echo "[$timestamp] [$level] $message" >> /var/log/nginx_ddos_defender.log
}

# 检查依赖
check_dependencies() {
    local dependencies=("grep" "awk" "sort" "uniq" "tail" "date" "mktemp" "ss" "bc")
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log "ERROR" "缺少依赖: $dep，请安装后再运行此脚本"
            exit 1
        fi
    done
    
    # 检查邮件发送工具
    if [ -n "$ALERT_EMAIL" ]; then
        if ! command -v mail &> /dev/null && ! command -v sendmail &> /dev/null; then
            log "WARNING" "未找到邮件发送工具，告警功能将无法使用"
            ALERT_EMAIL=""
        fi
    fi
    
    # 检查可视化依赖
    if [ "$ENABLE_VISUALIZATION" -eq 1 ]; then
        if ! command -v gnuplot &> /dev/null; then
            log "WARNING" "未找到gnuplot，可视化功能将无法使用"
            ENABLE_VISUALIZATION=0
        fi
    fi
}

# 初始化
init() {
    log "INFO" "初始化Nginx DDoS防御系统..."
    
    # 检查root权限
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR" "此脚本需要root权限运行"
        exit 1
    fi
    
    # 创建封禁文件(如果不存在)
    if [ ! -f "$BLOCK_FILE" ]; then
        echo "# 自动封禁的IP列表 - $(date)" > "$BLOCK_FILE"
        log "INFO" "创建封禁文件: $BLOCK_FILE"
    fi
    
    # 创建临时文件目录
    mkdir -p "$(dirname "$TEMP_FILE")"
    
    # 创建可视化目录
    if [ "$ENABLE_VISUALIZATION" -eq 1 ]; then
        mkdir -p "$VISUALIZATION_DIR"
        touch "$VISUALIZATION_DIR/attack_stats.dat"
    fi
    
    log "INFO" "初始化完成，开始监控..."
}

# 检查IP是否在白名单中
is_whitelisted() {
    local ip="$1"
    for subnet in $WHITELIST_IPS; do
        if [[ "$subnet" == */* ]]; then
            # CIDR格式
            local base=$(echo "$subnet" | cut -d/ -f1)
            local mask=$(echo "$subnet" | cut -d/ -f2)
            if [[ $(ip_in_subnet "$ip" "$base" "$mask") -eq 1 ]]; then
                return 0
            fi
        else
            # 单IP
            if [[ "$ip" == "$subnet" ]]; then
                return 0
            fi
        fi
    done
    return 1
}

# 判断IP是否在子网内(辅助函数)
ip_in_subnet() {
    local ip=$1
    local base=$2
    local mask=$3
    
    # 转换IP为32位整数
    local ip_num=$(ip_to_int "$ip")
    local base_num=$(ip_to_int "$base")
    local mask_bits=$((32 - mask))
    local mask_num=$((0xFFFFFFFF << mask_bits))
    
    if [[ $((ip_num & mask_num)) -eq $((base_num & mask_num)) ]]; then
        echo 1
    else
        echo 0
    fi
}

# IP转整数(辅助函数)
ip_to_int() {
    local IFS=.
    read -r i1 i2 i3 i4 <<< "$1"
    echo $(( (i1 << 24) + (i2 << 16) + (i3 << 8) + i4 ))
}

# 检测DDoS攻击
detect_ddos() {
    log "INFO" "开始检测DDoS攻击..."
    
    # 获取最近一段时间的日志行数
    local log_lines=$(tail -n 10000 "$LOG_FILE")
    
    # 统计每个IP的请求数
    local ip_counts=$(echo "$log_lines" | awk '{print $1}' | sort | uniq -c | sort -nr)
    
    # 计算总请求数
    local total_requests=$(echo "$ip_counts" | awk '{sum+=$1} END {print sum}')
    
    # 记录攻击统计数据(用于可视化)
    if [ "$ENABLE_VISUALIZATION" -eq 1 ]; then
        local timestamp=$(date +%s)
        echo "$timestamp $total_requests" >> "$VISUALIZATION_DIR/attack_stats.dat"
    fi
    
    # 检查是否超过突发阈值
    if [ "$total_requests" -gt "$BURST_THRESHOLD" ]; then
        log "ALERT" "检测到突发流量: $total_requests 请求 (阈值: $BURST_THRESHOLD)"
        send_alert "突发流量警报" "检测到突发流量: $total_requests 请求 (阈值: $BURST_THRESHOLD)"
    fi
    
    # 找出超过阈值的IP
    local suspicious_ips=$(echo "$ip_counts" | awk -v threshold="$THRESHOLD" '$1 > threshold {print $2, $1}')
    
    if [ -n "$suspicious_ips" ]; then
        log "INFO" "检测到可疑IP: $(echo "$suspicious_ips" | wc -l) 个"
        block_ips "$suspicious_ips"
    else
        log "INFO" "未检测到DDoS攻击"
    fi
    
    # 清理过期封禁
    cleanup_expired
}

# 封禁IP
block_ips() {
    local suspicious_ips="$1"
    local new_blocks=0
    local current_time=$(date +%s)
    
    # 创建临时文件
    local temp_file=$(mktemp)
    cp "$BLOCK_FILE" "$temp_file"
    
    while read -r line; do
        local ip=$(echo "$line" | awk '{print $1}')
        local count=$(echo "$line" | awk '{print $2}')
        
        # 检查是否在白名单
        if is_whitelisted "$ip"; then
            log "INFO" "跳过白名单IP: $ip"
            continue
        fi
        
        # 检查是否已封禁
        if grep -q "$ip" "$BLOCK_FILE"; then
            log "INFO" "IP $ip 已被封禁"
            continue
        fi
        
        # 添加到封禁列表
        echo "deny $ip;" >> "$temp_file"
        echo "# Blocked at $(date) - Requests: $count" >> "$temp_file"
        
        log "ALERT" "封禁IP: $ip (请求数: $count)"
        ((new_blocks++))
        
        # 触发告警
        if [ "$count" -gt "$ALERT_THRESHOLD" ]; then
            send_alert "DDoS攻击警报" "已封禁IP: $ip (请求数: $count)"
        fi
        
        # 限制最大封禁IP数
        local current_count=$(grep -c "deny" "$temp_file")
        if [ "$current_count" -gt "$MAX_BLOCKED_IPS" ]; then
            log "ERROR" "已达到最大封禁IP数($MAX_BLOCKED_IPS)"
            break
        fi
    done <<< "$(echo "$suspicious_ips")"
    
    # 如果有新封禁，替换原文件并重载Nginx
    if [ "$new_blocks" -gt 0 ]; then
        mv "$temp_file" "$BLOCK_FILE"
        log "INFO" "封禁了 $new_blocks 个IP，重新加载Nginx配置..."
        
        if ! $NGINX_RELOAD_CMD; then
            log "ERROR" "Nginx配置重载失败，请检查配置文件"
        fi
    else
        rm -f "$temp_file"
    fi
}

# 发送告警邮件
send_alert() {
    if [ -z "$ALERT_EMAIL" ]; then
        return
    fi
    
    local subject="$1"
    local message="$2"
    
    # 添加系统信息
    local system_info=$(hostname -f)
    local traffic_info=$(ss -s)
    
    message="$message\n\n系统: $system_info\n网络状态:\n$traffic_info"
    
    # 尝试使用mail命令发送
    if command -v mail &> /dev/null; then
        echo -e "$message" | mail -s "$subject" "$ALERT_EMAIL"
    # 否则使用sendmail
    elif command -v sendmail &> /dev/null; then
        (
            echo "To: $ALERT_EMAIL"
            echo "Subject: $subject"
            echo "Content-Type: text/plain; charset=UTF-8"
            echo ""
            echo -e "$message"
        ) | sendmail -t
    fi
}

# 清理过期封禁
cleanup_expired() {
    # 计算过期时间戳
    local expire_time=$(date -d "$BAN_TIME seconds ago" +%s)
    
    # 创建临时文件
    local temp_file=$(mktemp)
    
    # 保留头部注释
    head -n 1 "$BLOCK_FILE" > "$temp_file"
    
    # 过滤掉过期的封禁
    local in_comment=0
    local comment_time=0
    
    while IFS= read -r line; do
        # 检查是否是注释行
        if [[ "$line" == \#* ]]; then
            in_comment=1
            # 尝试提取时间戳
            comment_time=$(date -d "$(echo "$line" | grep -oP 'Blocked at \K.*?(?= -)')" +%s 2>/dev/null)
            echo "$line" >> "$temp_file"
        # 检查是否是deny行
        elif [[ "$line" == deny* ]]; then
            if [ "$in_comment" -eq 1 ] && [ -n "$comment_time" ] && [ "$comment_time" -lt "$expire_time" ]; then
                # 过期的封禁，跳过
                log "INFO" "解封IP: $(echo "$line" | awk '{print $2}' | tr -d ';') (封禁时间已过)"
                in_comment=0
                comment_time=0
            else
                # 未过期，保留
                echo "$line" >> "$temp_file"
                in_comment=0
                comment_time=0
            fi
        else
            # 其他行，保留
            echo "$line" >> "$temp_file"
            in_comment=0
            comment_time=0
        fi
    done < "$BLOCK_FILE"
    
    # 替换原文件
    mv "$temp_file" "$BLOCK_FILE"
    
    # 重载Nginx配置
    if [ $(grep -c "deny" "$BLOCK_FILE") -ne $(grep -c "deny" "$BLOCK_FILE.bak") ]; then
        log "INFO" "清理了过期封禁，重新加载Nginx配置..."
        cp "$BLOCK_FILE" "$BLOCK_FILE.bak"
        if ! $NGINX_RELOAD_CMD; then
            log "ERROR" "Nginx配置重载失败，请检查配置文件"
        fi
    fi
}

# 生成可视化图表
generate_visualization() {
    if [ "$ENABLE_VISUALIZATION" -eq 0 ]; then
        return
    fi
    
    local plot_file="$VISUALIZATION_DIR/plot.gp"
    local html_file="$VISUALIZATION_DIR/index.html"
    
    # 创建gnuplot脚本
    cat > "$plot_file" <<EOF
set terminal png size 1200,600 enhanced font 'Arial,10'
set output '$VISUALIZATION_DIR/attack_history.png'
set title 'Nginx DDoS攻击历史'
set xlabel '时间'
set ylabel '请求数/分钟'
set grid
set timefmt '%s'
set xdata time
set format x '%H:%M:%S'
plot '$VISUALIZATION_DIR/attack_stats.dat' using 1:2 with lines title '请求数'
EOF
    
    # 生成图表
    gnuplot "$plot_file"
    
    # 创建HTML报告
    cat > "$html_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Nginx DDoS攻击统计</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .stats { margin-top: 20px; }
        .blocked-ips { margin-top: 40px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 8px; border: 1px solid #ddd; text-align: left; }
        th { background-color: #f2f2f2; }
        .alert { color: red; font-weight: bold; }
    </style>
</head>
<body>
    <h1>Nginx DDoS攻击统计</h1>
    <div class="stats">
        <h2>攻击历史趋势</h2>
        <img src="attack_history.png" alt="攻击历史趋势图">
    </div>
    <div class="blocked-ips">
        <h2>当前封禁的IP列表</h2>
        <table>
            <tr>
                <th>IP地址</th>
                <th>封禁时间</th>
                <th>请求数</th>
            </tr>
EOF
    
    # 添加封禁IP信息
    local in_comment=0
    local current_ip=""
    local block_time=""
    local request_count=""
    
    while IFS= read -r line; do
        if [[ "$line" == \#* ]]; then
            in_comment=1
            block_time=$(echo "$line" | grep -oP 'Blocked at \K.*?(?= -)')
            request_count=$(echo "$line" | grep -oP 'Requests: \K.*')
        elif [[ "$line" == deny* && "$in_comment" -eq 1 ]]; then
            current_ip=$(echo "$line" | awk '{print $2}' | tr -d ';')
            echo "            <tr>" >> "$html_file"
            echo "                <td>$current_ip</td>" >> "$html_file"
            echo "                <td>$block_time</td>" >> "$html_file"
            echo "                <td>$request_count</td>" >> "$html_file"
            echo "            </tr>" >> "$html_file"
            in_comment=0
        fi
    done < "$BLOCK_FILE"
    
    # 完成HTML文件
    cat >> "$html_file" <<EOF
        </table>
    </div>
    <div class="footer">
        <p>更新时间: $(date)</p>
    </div>
</body>
</html>
EOF
    
    log "INFO" "更新了可视化统计数据"
}

# 主函数
main() {
    check_dependencies
    init
    
    # 单次运行模式
    if [ "$1" == "check" ]; then
        detect_ddos
        if [ "$ENABLE_VISUALIZATION" -eq 1 ]; then
            generate_visualization
        fi
        exit 0
    fi
    
    # 守护进程模式
    if [ "$1" == "daemon" ]; then
        log "INFO" "启动DDoS防御守护进程，检查间隔: $CHECK_INTERVAL 秒"
        
        # 捕获终止信号
        trap 'log "INFO" "收到终止信号，正在退出..."; exit 0' SIGINT SIGTERM
        
        while true; do
            detect_ddos
            if [ "$ENABLE_VISUALIZATION" -eq 1 ]; then
                generate_visualization
            fi
            sleep "$CHECK_INTERVAL"
        done
    fi
    
    # 显示帮助
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  check     执行一次检测并退出"
    echo "  daemon    作为守护进程运行"
    echo "  --help    显示此帮助信息"
    exit 1
}

# 执行主函数
main "$@"    
