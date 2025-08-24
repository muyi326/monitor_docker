#!/bin/bash

# 监控配置
GITHUB_URL="https://raw.githubusercontent.com/muyi326/updateRi/refs/heads/main/MuYi"
CHECK_INTERVAL=1800  # 30分钟 = 1800秒（修正）
CURRENT_VALUE_FILE="/tmp/docker_monitor_current_value.txt"
LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')]"

# 优雅退出处理
cleanup() {
    echo "$LOG_PREFIX 收到退出信号，清理中..."
    exit 0
}
trap cleanup SIGINT SIGTERM

# 函数：获取GitHub上的数值（带重试）
get_github_value() {
    local value=""
    local retry_count=3
    
    for i in $(seq 1 $retry_count); do
        value=$(curl -fsSL "$GITHUB_URL" 2>/dev/null | grep 'DEFAULT_VALUE=' | cut -d'"' -f2)
        if [ -n "$value" ]; then
            break
        fi
        sleep 2
    done
    echo "$value"
}

# 函数：关闭docker-compose窗口并创建新窗口
restart_docker_compose() {
    echo "$LOG_PREFIX 检测到数值变化，执行重启流程..."
    
    # 确保Terminal应用运行
    osascript -e 'tell application "Terminal" to activate' 2>/dev/null
    sleep 1
    
    # 先终止docker-compose进程
    pkill -f "docker-compose"
    sleep 1

    # 关闭docker-compose窗口
    osascript <<EOF
tell application "Terminal"
    set targetWindows to every window whose name contains "docker-compose"
    repeat with theWindow in targetWindows
        try
            set index of theWindow to 1
            activate
            delay 0.5
            
            tell application "System Events"
                keystroke "c" using {control down}
            end tell
            delay 0.3
            tell application "System Events"
                keystroke "c" using {control down}
            end tell
            delay 0.3
            
            delay 1
            close theWindow saving no
            
        on error errMsg
            log "Error: " & errMsg
        end try
    end repeat
end tell
EOF

    sleep 2

    # 创建新窗口
    osascript <<EOF
tell application "Terminal"
    activate
    delay 1
    
    set newWindow to do script "bash <(curl -fsSL $GITHUB_URL)"
    delay 3
    
    set bounds of first window to {742, 25, 1509, 634}
    set custom title of newWindow to "docker-compose-monitor"
end tell
EOF

    echo "$LOG_PREFIX 重启流程完成"
}

# 主监控循环
main() {
    echo "$LOG_PREFIX 启动docker-compose监控服务"
    echo "$LOG_PREFIX 监控URL: $GITHUB_URL"
    echo "$LOG_PREFIX 检查间隔: $CHECK_INTERVAL 秒"
    
    # 初始化当前值
    if [ ! -f "$CURRENT_VALUE_FILE" ]; then
        local current_value=$(get_github_value)
        if [ -n "$current_value" ]; then
            echo "$current_value" > "$CURRENT_VALUE_FILE"
            echo "$LOG_PREFIX 初始化当前值: $current_value"
        else
            echo "$LOG_PREFIX 错误: 无法从GitHub获取初始值"
            exit 1
        fi
    fi
    
    local current_value=$(cat "$CURRENT_VALUE_FILE")
    echo "$LOG_PREFIX 当前监控值: $current_value"
    
    # 监控循环
    while true; do
        echo "$LOG_PREFIX 检查GitHub数值..."
        
        local github_value=$(get_github_value)
        
        if [ -z "$github_value" ]; then
            echo "$LOG_PREFIX 警告: 无法从GitHub获取数值，等待下一次检查..."
        elif [ "$github_value" != "$current_value" ]; then
            echo "$LOG_PREFIX 检测到数值变化: $current_value -> $github_value"
            echo "$github_value" > "$CURRENT_VALUE_FILE"
            current_value="$github_value"
            restart_docker_compose
        else
            echo "$LOG_PREFIX 数值未变化: $current_value"
        fi
        
        echo "$LOG_PREFIX 下一次检查在 $(date -v+${CHECK_INTERVAL}S '+%H:%M:%S')"
        sleep "$CHECK_INTERVAL"
    done
}

# 运行主函数
main