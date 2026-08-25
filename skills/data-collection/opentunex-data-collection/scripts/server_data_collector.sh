#!/bin/bash

# 服务器数据采集脚本
# 作者: RicardoJDLi
# 创建时间: $(date)
# 功能: 收集系统性能数据、配置信息和硬件信息
# 用法: ./server_data_collector.sh [duration] [pid]
#   duration: 每个组件采集持续时间（秒），默认10秒
#   pid: 要监控的进程ID，可选参数

ARCH_TARGET="aarch64"
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) ARCH_TARGET="x86_64" ;;
    aarch64|arm64) ARCH_TARGET="aarch64" ;;
esac

# 默认参数值
DURATION=10
INTERVAL=1
TIMEOUT_DURATION=60
PIDS=""
OUTPUT_DIR=""
CHECK_ONLY=false
#输出文件
KSPECT_FILE=""
TOPDOWN_FILE=""
NUMAFAST_FILE=""
HOTSPOT_FILE=""
MEMORY_FILE=""
TURBOSTAT_FILE=""
KSYS_FILE=""
STATIC_FILE=""
BOTTLENECK_FILE=""
TOP_PROC_FILE=""
HOTSPOT_ANALYSIS_FILE=""
SYSCALL_FILE=""
MICROARCH_FILE=""
IO_METRICS_FILE=""
LOCK_TRACE_FILE=""
MEM_METRICS_FILE=""
NET_METRICS_FILE=""
SCHED_TRACE_FILE=""
CPU_DETAIL_FILE=""
KERNEL_CONFIG_FILE=""
PMU_INFO_FILE=""
PROCESS_DETAIL_INFO_FILE=""
SYSTEM_DETAIL_INFO_FILE=""
CONTAINER_FILE=""
ERROR_LOG=""
# 补充数据记录文件
SUPPLE_FILE=""
SOFTWARE_FILE=""
#可选择执行的指令
AVAILABLE_COMMANDS=(
    "collect_ksys"            # devkit ksys分析
    "collect_hotspot_analysis" #热点函数分析（需要指定pid）
    "collect_syscall_analysis" #系统调用分析（需要指定pid）
    "collect_microarch_analysis" #微架构瓶颈分析（需要指定pid）
    "collect_global_bottleneck" #全局资源瓶颈
    "collect_top_processes" # top资源消耗进程
    "collect_process_detail_info" # 进程详细信息
    "collect_container_info" # 容器信息
    "collect_io_metrics"      # I/O分析
    "collect_lock_trace"      # 锁跟踪分析
    "collect_mem_metrics"     # 内存指标分析
    "collect_net_metrics"     # 网络指标分析
    "collect_sched_trace"     # 新增调度器跟踪分析
    "collect_kernel_config_info" # kernel配置信息
    "collect_cpu_detail_info"  # cpu详细信息
    "collect_system_detail_info" # 系统详细信息
    "collect_static_info"  # 静态配置信息
)

# 条件添加 aarch64 相关命令
if [[ "${ARCH_TARGET}" = "aarch64" ]]; then
    AVAILABLE_COMMANDS+=(
        "collect_devkit_topdown"
        "collect_devkit_memory"
        "collect_devkit_hotspot"
        "collect_devkit_numafast"
        "collect_devkit_turbostat"
        "collect_kspect"
        "collect_pmu_info"
    )
fi

SELECTED_COMMANDS=()

set_output_file() {
    KSPECT_FILE="${OUTPUT_DIR}/devkit_kspect.txt"
    TOPDOWN_FILE="${OUTPUT_DIR}/devkit_topdown.txt"
    NUMAFAST_FILE="${OUTPUT_DIR}/devkit_numafast.txt"
    HOTSPOT_FILE="${OUTPUT_DIR}/devkit_hotspot.txt"
    MEMORY_FILE="${OUTPUT_DIR}/devkit_memory.txt"
    TURBOSTAT_FILE="${OUTPUT_DIR}/devkit_turbostat.txt"
    KSYS_FILE="${OUTPUT_DIR}/devkit_ksys.txt"

    STATIC_FILE="${OUTPUT_DIR}/static_info.txt"
    BOTTLENECK_FILE="${OUTPUT_DIR}/global_bottleneck.txt"
    TOP_PROC_FILE="${OUTPUT_DIR}/top_processes.txt"
    HOTSPOT_ANALYSIS_FILE="${OUTPUT_DIR}/hotspot_analysis.txt"
    SYSCALL_FILE="${OUTPUT_DIR}/syscall_analysis.txt"
    MICROARCH_FILE="${OUTPUT_DIR}/microarch_analysis.txt"
    IO_METRICS_FILE="${OUTPUT_DIR}/io_metrics_analysis.txt"
    LOCK_TRACE_FILE="${OUTPUT_DIR}/lock_trace_analysis.txt"
    MEM_METRICS_FILE="${OUTPUT_DIR}/memory_metrics_analysis.txt"
    NET_METRICS_FILE="${OUTPUT_DIR}/network_metrics_analysis.txt"
    SCHED_TRACE_FILE="${OUTPUT_DIR}/scheduler_trace_analysis.txt"
    CPU_DETAIL_FILE="${OUTPUT_DIR}/cpu_detail_info.txt"
    KERNEL_CONFIG_FILE="${OUTPUT_DIR}/kernel_config_info.txt"
    PMU_INFO_FILE="${OUTPUT_DIR}/pmu_info.txt"
    PROCESS_DETAIL_INFO_FILE="${OUTPUT_DIR}/process_detail_info.txt"
    SYSTEM_DETAIL_INFO_FILE="${OUTPUT_DIR}/system_detail_info.txt"
    CONTAINER_FILE="${OUTPUT_DIR}/container_info.txt"
    ERROR_LOG="$OUTPUT_DIR/err_log.txt"
    # 补充数据记录文件
    SOFTWARE_FILE="${OUTPUT_DIR}/software.txt"
}


# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 显示用法
show_usage() {
    cat << EOF
用法: $0 -d <持续时间> -p <进程ID> [-o <输出目录>] [-c <采集项目>] [-t <超时缓冲>] [-C] [-h]

参数说明:
    -d <持续时间>    采集数据的持续时间（秒）
    -p <进程ID>      要监控的进程ID（多个PID用逗号分隔）
    -o <输出目录>    数据输出目录（可选）
    -c <采集项目>    要采集的项目，多个项目用逗号分隔（可选）
    -t <超时缓冲>    命令执行超时缓冲时间（秒），默认60秒（可选）
    -C              仅执行前置检查，不进行数据采集（可选）
    -h              显示此帮助信息

可用的采集项目:
    collect_ksys                  - devkit ksys分析
    collect_io_metrics            - I/O分析
    collect_lock_trace            - 锁跟踪分析
    collect_mem_metrics           - 内存指标分析
    collect_net_metrics           - 网络指标分析
    collect_sched_trace           - 调度器跟踪分析
    collect_cpu_detail_info       - CPU详细信息
    collect_kernel_config_info    - Kernel配置信息
    collect_process_detail_info   - 进程详细信息
    collect_system_detail_info    - 系统详细信息
    collect_container_info        - 容器信息
    collect_hotspot_analysis      - 热点函数分析(需要指定pid)
    collect_syscall_analysis      - 系统调用分析(需要指定pid)
    collect_microarch_analysis    - 微架构瓶颈分析(需要指定pid)
    collect_global_bottleneck     - 全局资源瓶颈
    collect_top_processes         - top资源消耗进程
    collect_static_info           - 静态配置信息
AARCH64才支持的项目:
    collect_devkit_topdown        - devkit topdown
    collect_devkit_memory         - devkit memory
    collect_devkit_hotspot        - devkit hotspot
    collect_devkit_numafast       - devkit numafast
    collect_devkit_turbostat      - devkit turbostat
    collect_kspect                - devkit kspect
    collect_pmu_info              - pmu info

示例:
    # 仅执行前置检查，验证依赖软件
    $0 -C
    
    # 使用默认采集项目
    $0 -d 10
    
    # 采集对应进程，并采集默认项目
    $0 -d 60 -p 1234
    
    # 指定采集项目
    $0 -d 30 -p 1234 -c collect_ksys,collect_io_metrics
    
    # 完整示例
    $0 -d 120 -p 1234,5678 -o /tmp/profiling -c collect_cpu_detail_info,collect_mem_metrics,collect_net_metrics
    
    # 采集所有项目
    $0 -d 60 -p 1234 -c $(IFS=,; echo "${AVAILABLE_COMMANDS[*]}")
EOF
}

validate_pids() {
    local pids_str="$1"
    
    # 检查是否包含逗号（多个PID）
    if [[ "$pids_str" =~ , ]]; then
        # 多个PID，按逗号分隔
        IFS=',' read -ra pid_array <<< "$pids_str"
        local valid=true
        
        for pid in "${pid_array[@]}"; do
            # 去除空格
            pid=$(echo "$pid" | xargs)
            
            if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
                log_error "进程ID必须是数字，发现无效PID: $pid"
                return 1
            fi
            
            # 检查进程是否存在
            if ! ps -p "$pid" > /dev/null 2>&1; then
                log_warning "进程ID $pid 不存在或已终止"
            fi
        done
    else
        # 单个PID，去除空格
        local pid=$(echo "$pids_str" | xargs)
        
        if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
            log_error "进程ID必须是数字: $pid"
            return 1
        fi
        
        # 检查进程是否存在
        if ! ps -p "$pid" > /dev/null 2>&1; then
            log_warning "进程ID $pid 不存在或已终止"
        fi
    fi
    
    return 0
}

validate_output_dir() {
    local dir="$1"
    
    # 如果目录已存在，检查是否可写
    if [[ -d "$dir" ]]; then
        if [[ -w "$dir" ]]; then
            log_info "输出目录已存在且可写: $dir"
            return 0
        else
            log_error "输出目录已存在但不可写: $dir"
            return 1
        fi
    fi

    # 尝试创建目录（包括父目录）
    if mkdir -p "$dir" 2>/dev/null; then
        log_info "成功创建输出目录: $dir"
        return 0
    else
        log_error "无法创建输出目录: $dir，请检查权限"
        return 1
    fi
}

validate_collect_commands() {
    local invalid_cmds=()
    local valid_cmds=()
    
    # 构建有效命令的关联数组以便快速查找
    declare -A valid_map
    for cmd in "${AVAILABLE_COMMANDS[@]}"; do
        valid_map["$cmd"]=1
    done
    
    for cmd in "$@"; do
        if [[ -n "${valid_map[$cmd]}" ]]; then
            valid_cmds+=("$cmd")
        else
            invalid_cmds+=("$cmd")
        fi
    done
    
    if [[ ${#invalid_cmds[@]} -gt 0 ]]; then
        log_error "无效的采集项目: ${invalid_cmds[*]}"
        log_error "可用的采集项目: ${AVAILABLE_COMMANDS[*]}"
        return 1
    fi
    
    # 更新SELECTED_COMMANDS为有效的命令列表
    SELECTED_COMMANDS=("${valid_cmds[@]}")
    
    return 0
}

# 解析参数
parse_arguments() {    
    # 使用 getopts 解析参数
    while getopts "d:p:o:c:t:Ch" opt; do
        case ${opt} in
            d)
                # 持续时间参数
                if [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
                    DURATION=$OPTARG
                    log_info "设置采集持续时间为: ${DURATION}秒"
                else
                    log_error "持续时间必须是数字: $OPTARG"
                    show_usage
                    exit 1
                fi
                ;;
            p)
                # 进程ID参数
                PIDS="$OPTARG"
                log_info "设置监控进程ID为: ${PIDS}"
                
                # 验证PID格式
                validate_pids "$PIDS"
                if [[ $? -ne 0 ]]; then
                    exit 1
                fi
                ;;
            o)
                # 输出目录参数
                OUTPUT_DIR="$OPTARG"
                log_info "设置输出目录为: ${OUTPUT_DIR}"
                
                # 验证并创建输出目录
                validate_output_dir "$OUTPUT_DIR"
                if [[ $? -ne 0 ]]; then
                    exit 1
                fi
                set_output_file
                ;;
            c)
                # 采集项目参数
                IFS=',' read -ra SELECTED_COMMANDS <<< "$OPTARG"
                log_info "设置采集项目为: ${SELECTED_COMMANDS[*]}"
                
                # 验证采集项目
                validate_collect_commands "${SELECTED_COMMANDS[@]}"
                if [[ $? -ne 0 ]]; then
                    exit 1
                fi
                ;;
            t)
                # 超时缓冲参数
                if [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
                    TIMEOUT_DURATION=$OPTARG
                    log_info "设置超时缓冲时间为: ${TIMEOUT_DURATION}秒"
                else
                    log_error "超时缓冲时间必须是数字: $OPTARG"
                    show_usage
                    exit 1
                fi
                ;;
            C)
                # 仅前置检查参数
                CHECK_ONLY=true
                log_info "设置仅执行前置检查模式"
                ;;
            h)
                show_usage
                exit 0
                ;;
            \?)
                log_error "无效的选项: -$OPTARG"
                show_usage
                exit 1
                ;;
            :)
                log_error "选项 -$OPTARG 需要一个参数"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # 检查必需参数
    if [[ "$CHECK_ONLY" = false ]] && [[ -z "$DURATION" ]]; then
        log_error "缺少必需参数: -d <持续时间>"
        log_info "或使用 -C 仅执行前置检查"
        show_usage
        exit 1
    fi
    
    # 如果仅前置检查，直接返回
    if [[ "$CHECK_ONLY" = true ]]; then
        # 如果未指定采集项目，使用默认项目进行前置检查
        if [[ ${#SELECTED_COMMANDS[@]} -eq 0 ]]; then
            SELECTED_COMMANDS=("${AVAILABLE_COMMANDS[@]}")
            log_info "前置检查将验证所有可用项目的依赖 (共 ${#SELECTED_COMMANDS[@]} 项)"
        fi
        return 0
    fi
    
    # 如果未指定采集项目，使用默认项目
     if [[ ${#SELECTED_COMMANDS[@]} -eq 0 ]]; then
        SELECTED_COMMANDS=("${AVAILABLE_COMMANDS[@]}")
        log_info "未指定采集项目，将采集所有可用项目 (共 ${#SELECTED_COMMANDS[@]} 项)"
        log_info "采集项目列表: ${SELECTED_COMMANDS[*]}"
    fi
    
    # 如果未指定输出目录，使用默认目录
    if [[ -z "$OUTPUT_DIR" ]]; then
        OUTPUT_DIR="profiling_data_${ARCH_TARGET}_$(date +%Y%m%d_%H%M%S)"
        log_info "未指定输出目录，使用默认目录: ${OUTPUT_DIR}"
        validate_output_dir "$OUTPUT_DIR"
        if [[ $? -ne 0 ]]; then
            exit 1
        fi
        set_output_file
    fi
}

# 日志函数
log_info() {
    echo -e "${BLUE}$1${NC}"
}

log_success() {
    echo -e "${GREEN}$1${NC}"
}

log_warning() {
    echo -e "${YELLOW}$1${NC}"
}

log_error() {
    echo -e "${RED}$1${NC}"
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "命令 $1 未找到，请根据上述提示安装后重试。"
        return 1
    fi
    return 0
}

download_and_install() {
    local package_url="$1"
    local package_name="$2"
    local cmd="$3"  # 新增：原始命令名

    log_info "开始下载 $package_name ..."

    # 使用wget下载，如果不存在则尝试curl
    if command -v wget &> /dev/null; then
        wget -O "/tmp/${package_name}.tar.gz" "$package_url"
    elif command -v curl &> /dev/null; then
        curl -L -o "/tmp/${package_name}.tar.gz" "$package_url"
    else
        log_error "未找到wget或curl下载工具，请先安装其中一个"
        return 1
    fi

    if [ $? -ne 0 ]; then
        log_error "下载 $package_name 失败，请检查网络连接或URL"
        return 1
    fi

    log_info "下载完成，开始解压安装..."

    # 创建临时目录并解压
    local temp_dir="/tmp/${package_name}_install_$(date +%s)"
    mkdir -p "$temp_dir"
    tar -xzf "/tmp/${package_name}.tar.gz" -C "$temp_dir"

    if [ $? -ne 0 ]; then
        log_error "解压 $package_name 失败"
        return 1
    fi

    # 对于devkit工具的特殊处理
    if [[ "$cmd" =~ ^(devkit|kspect|ksys)$ ]]; then
        log_info "检测到鲲鹏DevKit工具，直接导入temp_dir到PATH"

        # 查找可执行文件
        local bin_dir=""

        local executable=$(find "$temp_dir" -type f -executable -name "$cmd")
        if [ -n "$executable" ]; then
            bin_dir=$(dirname "$executable")
            log_info "找到可执行文件: $executable"
        fi

        if [ -n "$bin_dir" ]; then
            # 将bin目录添加到当前shell的PATH
            export PATH="$bin_dir:$PATH"

            # 添加到bashrc以便永久生效
            if ! grep -q "$bin_dir" ~/.bashrc 2>/dev/null; then
                echo "export PATH=\"$bin_dir:\$PATH\"" >> ~/.bashrc
                log_info "已永久添加到PATH: $bin_dir"
                log_warning "同一个session重复执行脚本，请先执行source ~/.bashrc"
            else
                log_info "PATH中已存在此目录: $bin_dir"
            fi

            log_info "DevKit工具已成功导入，可以立即使用"

            # 清理临时文件
            rm -f "/tmp/${package_name}.tar.gz"

            # 验证命令是否可用
            if command -v "$cmd" &> /dev/null; then
                log_info "命令 $cmd 已成功安装并可用"
                return 0
            else
                # 尝试查找是否有不同名称的可执行文件
                local found_cmd=$(find "$bin_dir" -type f -executable | xargs -I {} basename {} | grep -E "($cmd|devkit|ksys|kspect)" | head -1)
                if [ -n "$found_cmd" ]; then
                    log_info "请注意：工具的可执行文件名为 '$found_cmd'，而不是 '$cmd'"
                    log_info "您可以使用命令: $found_cmd 来运行工具"
                fi
            fi

            return 0
        else
            log_warn "解压目录: $temp_dir"
            log_info "未在解压目录中找到bin目录或可执行文件，请手动查看解压目录中的README或INSTALL文件进行安装"
        fi
    else
        # 非devkit工具的通用安装流程
        log_info "解压目录: $temp_dir"

        # 查找解压后的安装脚本
        local install_script=$(find "$temp_dir" -name "install.sh" -o -name "setup.sh" -o -name "install" | head -1)

        if [ -n "$install_script" ] && [ -x "$install_script" ]; then
            log_info "找到安装脚本: $install_script"
            cd "$(dirname "$install_script")" || return 1
            log_info "执行安装脚本..."

            # 尝试使用sudo，如果脚本需要root权限
            if [ -w "$install_script" ]; then
                bash "$(basename "$install_script")"
            else
                log_warn "安装脚本不可写，尝试使用sudo执行"
                sudo bash "$(basename "$install_script")"
            fi
        else
            # 查找README或INSTALL文件
            local readme_file=$(find "$temp_dir" -name "README*" -o -name "INSTALL*" -o -name "readme*" | head -1)
            if [ -n "$readme_file" ]; then
                log_info "请查看安装说明文件: $readme_file"
                head -20 "$readme_file" 2>/dev/null | grep -A 20 -i "install\|安装"
            else
                log_info "请手动查看解压目录: $temp_dir 中的内容进行安装"
            fi
        fi
    fi

    # 清理临时文件
    rm -f "/tmp/${package_name}.tar.gz"
    log_info "$package_name 安装流程完成"
    return 0
}

# 增强的命令检测函数
check_command_prefix() {
    local cmd="$1"
    local test_cmd="$2"
    if [[ -z $test_cmd ]];then
        test_cmd=$cmd
    fi

    if ! command -v "$test_cmd" &> /dev/null; then
        log_error "命令 $test_cmd 未找到"

        # 根据命令名识别对应的包
        local package_url=""
        local package_name=""

        case "$test_cmd" in
             "devkit")
                package_url="https://kunpeng-repo.obs.cn-north-4.myhuaweicloud.com/Kunpeng%20DevKit/Kunpeng%20DevKit%2026.0.RC1/DevKit-Tuner-CLI-26.0.RC1-Linux-aarch64.tar.gz"
                package_name="devkit-tuner"
                ;;
            "ksys")
                package_url="https://kunpeng-repo.obs.cn-north-4.myhuaweicloud.com/Kunpeng%20DevKit/Kunpeng%20DevKit%2026.0.RC1/ksys-26.0.RC1-Linux-${ARCH_TARGET}.tar.gz"
                package_name="devkit-ksys"
                ;;
            "kspect")
                package_url="https://kunpeng-repo.obs.cn-north-4.myhuaweicloud.com/Kunpeng%20DevKit/Kunpeng%20DevKit%2026.0.RC1/devkit-kspect-26.0.RC1-Linux-aarch64.tar.gz"
                package_name="devkit-kspect"
                ;;
            *)
                package_url=""
                package_name=""
                ;;
        esac

        if [ -n "$package_url" ]; then
            echo "是否自动下载并安装 $package_name? (Y/N)"
            read -r user_choice

            case "${user_choice^^}" in
                "Y"|"YES")
                    log_info "用户选择自动安装 $package_name"
                    download_and_install "$package_url" "$package_name" "$cmd"
                    if [ $? -eq 0 ]; then
                        # 再次检查命令是否安装成功
                        if command -v "$cmd" &> /dev/null; then
                            log_info "命令 $cmd 已成功安装"
                            return 0
                        else
                            log_info "$package_name 已安装，但可能需要重新启动shell或手动添加PATH"
                        fi
                    else
                        echo "自动安装$package_name失败, 请手动下载并安装 $package_name:"
                        echo "下载链接: $package_url"
                        echo ""
                        echo "安装步骤建议:"
                        echo "1. 下载上述链接的tar.gz包"
                        echo "2. 解压: tar -xzf 文件名.tar.gz"
                        echo "5. 将解压目录添加到PATH: export PATH=\"解压后目录:\$PATH\""
                        echo "========================================"
                        return 1
                    fi
                    ;;
                "N"|"NO"|*)
                    log_info "用户选择手动安装"
                    echo "========================================"
                    echo "请手动下载并安装 $package_name:"
                    echo "下载链接: $package_url"
                    echo ""
                    echo "安装步骤建议:"
                    echo "1. 下载上述链接的tar.gz包"
                    echo "2. 解压: tar -xzf 文件名.tar.gz"
                    echo "5. 将解压目录添加到PATH: export PATH=\"解压后目录:\$PATH\""
                    echo "========================================"
                    return 1
                    ;;
            esac
        else
            # 对于不在预设列表中的命令
            echo "是否尝试通过yum安装 $cmd? (Y/N)"
            read -r user_choice

            case "${user_choice^^}" in
                "Y"|"YES")
                    log_info "尝试通过yum安装 $cmd..."
                    if command -v yum &> /dev/null; then
                        # 检查 sudo 是否可用
                        if command -v sudo &> /dev/null; then
                            # 检查当前用户是否有 sudo 权限（非交互式）
                            if sudo -n true 2>/dev/null; then
                                sudo yum install -y "$cmd"
                                if [ $? -eq 0 ]; then
                                    log_info "$cmd 安装成功"
                                    return 0
                                else
                                    log_error "yum安装 $cmd 失败"
                                fi
                            else
                                # 没有 sudo 权限，尝试直接安装（可能已经是 root）
                                log_warning "没有 sudo 权限，尝试直接安装..."
                                yum install -y "$cmd"
                                if [ $? -eq 0 ]; then
                                    log_info "$cmd 安装成功"
                                    return 0
                                else
                                    log_error "yum安装 $cmd 失败（可能需要 root 权限）"
                                fi
                            fi
                        else
                            # sudo 命令不存在，尝试直接安装
                            log_warning "sudo 命令不可用，尝试直接安装..."
                            yum install -y "$cmd"
                            if [ $? -eq 0 ]; then
                                log_info "$cmd 安装成功"
                                return 0
                            else
                                log_error "yum安装 $cmd 失败（可能需要 root 权限）"
                            fi
                        fi
                    else
                        log_error "未找到yum包管理器"
                    fi
                    ;;
                "N"|"NO"| *)
                    log_info "用户选择手动安装"
                    echo "请手动安装 $cmd:"
                    echo "1. 可通过yum安装: sudo yum install $cmd"
                    echo "2. 或从官方源下载安装包"
                    echo "3. 若已安装，请确保已添加到PATH环境变量"
                    ;;
            esac
            return 1
        fi
    else
        log_info "命令 $cmd 已存在"
        return 0
    fi
}

check_commands() {
   log_info "开始命令前置检查"

   local needed_commands=()
   
   for selected in "${SELECTED_COMMANDS[@]}"; do
       case "$selected" in
           collect_devkit*)
               needed_commands+=("devkit" "kspect")
               ;;
           collect_ksys)
               needed_commands+=("ksys")
               ;;
           collect_hotspot_analysis|collect_syscall_analysis|collect_microarch_analysis|collect_pmu_info)
               needed_commands+=("perf")
               ;;
           collect_top_process)
               needed_commands+=("iotop")
               ;;
            collect_static_info)
               needed_commands+=("pciutils lspci" "ethtool" "gcc" "dmidecode" "numactl")
               ;;
            collect_net_metrics)
               needed_commands+=("net-tools netstat" "iputils ping" "iproute ip" "ethtool")
               ;;
            collect_sched_trace)
               needed_commands+=("taskset")
               ;;
            collect_syscall_analysis|collect_lock_trace)
               needed_commands+=("strace")
               ;;
            collect_mem_metrics)
               needed_commands+=("numactl")
               ;;
       esac
   done

   printf "%s\n" "${needed_commands[@]}" | sort -u | while read cmd; do
       check_command_prefix $cmd
   done

   check_command_prefix sysstat pidstat
   log_success "前置命令检查完成"
}

preflight_check() {
    log_info "========================================"
    log_info "开始前置依赖检查"
    log_info "========================================"
    echo ""
    
    local missing_commands=()
    local installed_commands=()
    local optional_missing=()
    
    echo -e "${BLUE}=== 基础系统命令检查 ===${NC}"
    echo ""
    
    local basic_commands=(
        "ps"
        "top"
        "free"
        "df"
        "uptime"
        "date"
        "cat"
        "grep"
        "awk"
        "sed"
        "head"
        "tail"
        "wc"
        "sort"
        "uniq"
        "find"
        "xargs"
        "mkdir"
        "rm"
        "mv"
        "cp"
        "chmod"
        "chown"
        "tar"
    )
    
    local basic_packages=(
        "ps:procps-ng"
        "top:procps-ng"
        "free:procps-ng"
        "tar:tar"
    )
    
    for cmd in "${basic_commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            echo -e "  ${GREEN}✓ $cmd${NC}"
            installed_commands+=("$cmd")
        else
            local pkg=""
            for pkg_info in "${basic_packages[@]}"; do
                if [[ "$pkg_info" =~ ^${cmd}: ]]; then
                    pkg="${pkg_info#*:}"
                    break
                fi
            done
            echo -e "  ${RED}✗ $cmd (缺失，包: ${pkg:-coreutils})${NC}"
            missing_commands+=("$cmd:${pkg:-coreutils}")
        fi
    done
    
    echo ""
    echo -e "${BLUE}=== 性能分析工具检查 (sysstat) ===${NC}"
    echo ""
    
    local sysstat_commands=(
        "mpstat"
        "vmstat"
        "pidstat"
        "iostat"
        "sar"
    )
    
    local sysstat_installed=0
    for cmd in "${sysstat_commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            sysstat_installed=$((sysstat_installed + 1))
        fi
    done
    
    if [[ $sysstat_installed -ge 3 ]]; then
        echo -e "  ${GREEN}✓ sysstat已安装 (包含: mpstat, vmstat, pidstat, iostat, sar)${NC}"
        for cmd in "${sysstat_commands[@]}"; do
            installed_commands+=("$cmd")
        done
    else
        echo -e "  ${YELLOW}○ sysstat未完整安装 (缺失: mpstat, vmstat, pidstat, iostat, sar)${NC}"
        echo -e "     ${YELLOW}安装建议: yum install -y sysstat${NC}"
        for cmd in "${sysstat_commands[@]}"; do
            if ! command -v "$cmd" &> /dev/null; then
                optional_missing+=("$cmd:sysstat")
            fi
        done
    fi
    
    echo ""
    echo -e "${BLUE}=== perf工具检查 ===${NC}"
    echo ""
    
    if command -v perf &> /dev/null; then
        local perf_version=$(perf --version 2>/dev/null | head -1 || echo "")
        echo -e "  ${GREEN}✓ perf${NC} ${perf_version}"
        installed_commands+=("perf")
    else
        echo -e "  ${YELLOW}○ perf (可选，缺失，包: perf)${NC}"
        optional_missing+=("perf:perf")
    fi
    
    echo ""
    echo -e "${BLUE}=== NUMA工具检查 ===${NC}"
    echo ""
    
    if command -v numactl &> /dev/null; then
        echo -e "  ${GREEN}✓ numactl${NC}"
        installed_commands+=("numactl")
    else
        echo -e "  ${YELLOW}○ numactl (可选，缺失，包: numactl)${NC}"
        optional_missing+=("numactl:numactl")
    fi
    
    echo ""
    echo -e "${BLUE}=== 系统信息工具检查 ===${NC}"
    echo ""
    
    local sys_info_commands=(
        "lscpu"
        "lspci"
        "dmidecode"
    )
    
    local sys_info_packages=(
        "lscpu:util-linux"
        "lspci:pciutils"
        "dmidecode:dmidecode"
    )
    
    for cmd in "${sys_info_commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            echo -e "  ${GREEN}✓ $cmd${NC}"
            installed_commands+=("$cmd")
        else
            local pkg=""
            for pkg_info in "${sys_info_packages[@]}"; do
                if [[ "$pkg_info" =~ ^${cmd}: ]]; then
                    pkg="${pkg_info#*:}"
                    break
                fi
            done
            echo -e "  ${YELLOW}○ $cmd (可选，缺失，包: $pkg)${NC}"
            optional_missing+=("$cmd:$pkg")
        fi
    done
    
    echo ""
    echo -e "${BLUE}=== 网络工具检查 ===${NC}"
    echo ""
    
    local net_commands=(
        "ip"
        "ping"
        "ethtool"
    )
    
    local net_packages=(
        "ip:iproute"
        "ping:iputils"
        "ethtool:ethtool"
    )
    
    for cmd in "${net_commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            echo -e "  ${GREEN}✓ $cmd${NC}"
            installed_commands+=("$cmd")
        else
            local pkg=""
            for pkg_info in "${net_packages[@]}"; do
                if [[ "$pkg_info" =~ ^${cmd}: ]]; then
                    pkg="${pkg_info#*:}"
                    break
                fi
            done
            echo -e "  ${YELLOW}○ $cmd (可选，缺失，包: $pkg)${NC}"
            optional_missing+=("$cmd:$pkg")
        fi
    done
    
    echo ""
    echo -e "${BLUE}=== 跟踪工具检查 ===${NC}"
    echo ""
    
    if command -v strace &> /dev/null; then
        echo -e "  ${GREEN}✓ strace${NC}"
        installed_commands+=("strace")
    else
        echo -e "  ${YELLOW}○ strace (可选，缺失，包: strace)${NC}"
        optional_missing+=("strace:strace")
    fi
    
    echo ""
    echo -e "${BLUE}=== 调度器工具检查 ===${NC}"
    echo ""
    
    if command -v taskset &> /dev/null; then
        echo -e "  ${GREEN}✓ taskset${NC}"
        installed_commands+=("taskset")
    else
        echo -e "  ${YELLOW}○ taskset (可选，缺失，包: util-linux)${NC}"
        optional_missing+=("taskset:util-linux")
    fi
    
    echo ""
    
    if [[ "${ARCH_TARGET}" = "aarch64" ]]; then
        echo -e "${BLUE}=== DevKit工具检查 (aarch64专用) ===${NC}"
        echo ""
        
        local devkit_commands=(
            "devkit"
            "ksys"
            "kspect"
        )
        
        local devkit_urls=(
            "devkit:https://kunpeng-repo.obs.cn-north-4.myhuaweicloud.com/Kunpeng%20DevKit/Kunpeng%20DevKit%2026.0.RC1/DevKit-Tuner-CLI-26.0.RC1-Linux-aarch64.tar.gz"
            "ksys:https://kunpeng-repo.obs.cn-north-4.myhuaweicloud.com/Kunpeng%20DevKit/Kunpeng%20DevKit%2026.0.RC1/ksys-26.0.RC1-Linux-aarch64.tar.gz"
            "kspect:https://kunpeng-repo.obs.cn-north-4.myhuaweicloud.com/Kunpeng%20DevKit/Kunpeng%20DevKit%2026.0.RC1/devkit-kspect-26.0.RC1-Linux-aarch64.tar.gz"
        )
        
        for cmd in "${devkit_commands[@]}"; do
            if command -v "$cmd" &> /dev/null; then
                local version=""
                case "$cmd" in
                    "devkit") version=$(devkit --version 2>/dev/null | head -1 || echo "") ;;
                    "ksys") version=$(ksys --version 2>/dev/null | head -1 || echo "") ;;
                    "kspect") version=$(kspect --version 2>/dev/null | head -1 || echo "") ;;
                esac
                echo -e "  ${GREEN}✓ $cmd${NC} ${version}"
                installed_commands+=("$cmd")
            else
                local url=""
                for url_info in "${devkit_urls[@]}"; do
                    if [[ "$url_info" =~ ^${cmd}: ]]; then
                        url="${url_info#*:}"
                        break
                    fi
                done
                echo -e "  ${YELLOW}○ $cmd (DevKit工具，缺失)${NC}"
                echo -e "     下载: $url"
                case "$cmd" in
                    "devkit") optional_missing+=("$cmd:devkit-tuner") ;;
                    "ksys") optional_missing+=("$cmd:ksys-tool") ;;
                    "kspect") optional_missing+=("$cmd:kspect-tool") ;;
                esac
            fi
        done
        
        echo ""
    fi
    
    echo ""
    echo -e "${BLUE}=== 权限检查 ===${NC}"
    echo ""
    
    if [[ $EUID -eq 0 ]]; then
        echo -e "  ${GREEN}✓ root权限${NC}"
    else
        echo -e "  ${YELLOW}○ 非root权限 (部分命令可能需要sudo)${NC}"
        
        if command -v sudo &> /dev/null; then
            if sudo -n true 2>/dev/null; then
                echo -e "  ${GREEN}✓ sudo免密权限${NC}"
            else
                echo -e "  ${YELLOW}○ sudo需要密码${NC}"
            fi
        else
            echo -e "  ${RED}✗ sudo命令缺失 (包: sudo)${NC}"
            missing_commands+=("sudo:sudo")
        fi
    fi
    
    echo ""
    echo -e "${BLUE}=== 内核功能检查 ===${NC}"
    echo ""
    
    if [[ -f "/proc/sys/kernel/perf_event_paranoid" ]]; then
        local perf_paranoid=$(cat /proc/sys/kernel/perf_event_paranoid)
        echo -e "  perf_event_paranoid: ${perf_paranoid}"
        if [[ "$perf_paranoid" -le 2 ]]; then
            echo -e "  ${GREEN}✓ perf用户态可访问${NC}"
        else
            echo -e "  ${YELLOW}○ perf需要root或调整perf_event_paranoid${NC}"
            echo -e "     建议执行: sudo sysctl -w kernel.perf_event_paranoid=1"
        fi
    else
        echo -e "  ${YELLOW}○ perf_event_paranoid不可用${NC}"
    fi
    
    if [[ -f "/proc/sys/kernel/kptr_restrict" ]]; then
        local kptr_restrict=$(cat /proc/sys/kernel/kptr_restrict)
        echo -e "  kptr_restrict: ${kptr_restrict}"
        if [[ "$kptr_restrict" -eq 0 ]]; then
            echo -e "  ${GREEN}✓ 内核符号可访问${NC}"
        else
            echo -e "  ${YELLOW}○ 内核符号受限${NC}"
            echo -e "     建议执行: sudo sysctl -w kernel.kptr_restrict=0"
        fi
    else
        echo -e "  ${YELLOW}○ kptr_restrict不可用${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}=== 系统资源检查 ===${NC}"
    echo ""
    
    local cpu_cores=$(nproc)
    local mem_total=$(free -m | awk '/Mem:/ {print $2}')
    local disk_avail=$(df -m / | awk 'NR==2 {print $4}')
    
    echo -e "  CPU核心数: ${cpu_cores}"
    echo -e "  总内存: ${mem_total} MB"
    echo -e "  根分区可用空间: ${disk_avail} MB"
    
    if [[ "$disk_avail" -lt 500 ]]; then
        echo -e "  ${RED}✗ 磁盘空间不足 (<500MB)${NC}"
    elif [[ "$disk_avail" -lt 1000 ]]; then
        echo -e "  ${YELLOW}○ 磁盘空间较低 (<1GB)${NC}"
    else
        echo -e "  ${GREEN}✓ 磁盘空间充足${NC}"
    fi
    
    echo ""
    echo "========================================"
    echo -e "${BLUE}前置检查汇总${NC}"
    echo "========================================"
    echo ""
    
    local installed_count=${#installed_commands[@]}
    local missing_count=${#missing_commands[@]}
    local optional_count=${#optional_missing[@]}
    
    echo -e "已安装命令: ${GREEN}${installed_count}${NC}"
    echo -e "必需命令缺失: ${RED}${missing_count}${NC}"
    echo -e "可选命令缺失: ${YELLOW}${optional_count}${NC}"
    echo ""
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        echo -e "${RED}必需命令缺失列表:${NC}"
        for cmd_pkg in "${missing_commands[@]}"; do
            local cmd="${cmd_pkg%%:*}"
            local pkg="${cmd_pkg#*:}"
            echo -e "  ${RED}- $cmd (包: $pkg)${NC}"
        done
        echo ""
    fi
    
    if [[ ${#optional_missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}可选命令缺失列表 (部分采集功能可能不可用):${NC}"
        
        local grouped_packages=()
        for cmd_pkg in "${optional_missing[@]}"; do
            local pkg="${cmd_pkg#*:}"
            if [[ ! " ${grouped_packages[@]} " =~ " ${pkg} " ]]; then
                grouped_packages+=("$pkg")
            fi
        done
        
        for pkg in "${grouped_packages[@]}"; do
            local cmds_in_pkg=""
            for cmd_pkg in "${optional_missing[@]}"; do
                local cmd="${cmd_pkg%%:*}"
                local p="${cmd_pkg#*:}"
                if [[ "$p" = "$pkg" ]]; then
                    cmds_in_pkg="$cmds_in_pkg $cmd"
                fi
            done
            echo -e "  ${YELLOW}包 $pkg:${cmds_in_pkg}${NC}"
        done
        echo ""
    fi
    
    echo -e "${BLUE}=== 安装建议 ===${NC}"
    echo ""
    
    local yum_packages=()
    for cmd_pkg in "${missing_commands[@]}" "${optional_missing[@]}"; do
        local pkg="${cmd_pkg#*:}"
        if [[ -n "$pkg" ]] && [[ ! "$pkg" =~ ^(DevKit|devkit-tuner|ksys-tool|kspect-tool|docker|kubernetes) ]] && [[ ! " ${yum_packages[@]} " =~ " ${pkg} " ]]; then
            yum_packages+=("$pkg")
        fi
    done
    
    if [[ ${#yum_packages[@]} -gt 0 ]]; then
        local unique_packages=$(printf "%s\n" "${yum_packages[@]}" | sort -u | tr '\n' ' ')
        echo -e "${GREEN}yum install -y ${unique_packages}${NC}"
        echo ""
    fi
    
    if [[ "${ARCH_TARGET}" = "aarch64" ]]; then
        local devkit_missing=0
        local ksys_missing=0
        local kspect_missing=0
        for cmd_pkg in "${optional_missing[@]}"; do
            if [[ "$cmd_pkg" =~ devkit-tuner ]]; then
                devkit_missing=1
            fi
            if [[ "$cmd_pkg" =~ ksys-tool ]]; then
                ksys_missing=1
            fi
            if [[ "$cmd_pkg" =~ kspect-tool ]]; then
                kspect_missing=1
            fi
        done
        
        if [[ $devkit_missing -eq 1 ]] || [[ $ksys_missing -eq 1 ]] || [[ $kspect_missing -eq 1 ]]; then
            echo -e "${BLUE}DevKit工具安装:${NC}"
            
            if [[ $devkit_missing -eq 1 ]]; then
                echo "  --- devkit ---"
                echo "  下载DevKit-Tuner-CLI:"
                echo "     wget -O DevKit-Tuner-CLI.tar.gz 'https://kunpeng-repo.obs.cn-north-4.myhuaweicloud.com/Kunpeng%20DevKit/Kunpeng%20DevKit%2026.0.RC1/DevKit-Tuner-CLI-26.0.RC1-Linux-aarch64.tar.gz'"
                echo "  解压并添加到PATH:"
                echo "     tar -xzf DevKit-Tuner-CLI.tar.gz"
                echo "     export PATH=\$PATH:解压后目录"
                echo ""
            fi
            
            if [[ $ksys_missing -eq 1 ]]; then
                echo "  --- ksys ---"
                echo "  下载ksys工具:"
                echo "     wget -O ksys.tar.gz 'https://kunpeng-repo.obs.cn-north-4.myhuaweicloud.com/Kunpeng%20DevKit/Kunpeng%20DevKit%2026.0.RC1/ksys-26.0.RC1-Linux-aarch64.tar.gz'"
                echo "  解压并添加到PATH:"
                echo "     tar -xzf ksys.tar.gz"
                echo "     export PATH=\$PATH:解压后目录"
                echo ""
            fi
            
            if [[ $kspect_missing -eq 1 ]]; then
                echo "  --- kspect ---"
                echo "  下载kspect工具:"
                echo "     wget -O kspect.tar.gz 'https://kunpeng-repo.obs.cn-north-4.myhuaweicloud.com/Kunpeng%20DevKit/Kunpeng%20DevKit%2026.0.RC1/devkit-kspect-26.0.RC1-Linux-aarch64.tar.gz'"
                echo "  解压并添加到PATH:"
                echo "     tar -xzf kspect.tar.gz"
                echo "     export PATH=\$PATH:解压后目录"
                echo ""
            fi
        fi
    fi
    
    if [[ ${#missing_commands[@]} -eq 0 ]]; then
        log_success "✓ 前置检查通过，所有必需依赖已安装"
        echo ""
        if [[ ${#optional_missing[@]} -gt 0 ]]; then
            log_warning "注意: ${optional_count}个可选工具缺失，部分采集功能可能受限"
            echo ""
            echo -e "${YELLOW}可选工具安装命令:${NC}"
            if [[ ${#yum_packages[@]} -gt 0 ]]; then
                local unique_packages=$(printf "%s\n" "${yum_packages[@]}" | sort -u | tr '\n' ' ')
                echo -e "  ${GREEN}yum install -y ${unique_packages}${NC}"
            fi
        fi
        return 0
    else
        log_error "✗ 前置检查失败，请先安装缺失的依赖"
        return 1
    fi
}

# 检查权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_warning "建议使用root权限运行此脚本以获取完整信息"
        log_warning "某些命令可能需要sudo权限"
    fi
}

# 创建输出文件头
create_header() {
    echo "================================================"
    echo "服务器数据采集报告"
    echo "采集时间: $(date)"
    echo "主机名: $(hostname)"
    echo "阶段性步骤采集持续时间: ${DURATION}秒"
    if [[ -n "$PIDS" ]]; then
        echo "监控进程ID: $PIDS"
        IFS=',' read -ra pid_array <<< "$PIDS"
        for pid in "${pid_array[@]}"; do
            pid=$(echo "$pid" | xargs)  # 去除空格
             # 获取进程信息
            if ps -p "$pid" > /dev/null 2>&1; then
                echo "进程名称: $(ps -p $pid -o comm=)"
                echo "进程命令行: $(ps -p $pid -o cmd=)"
            else
                echo "进程状态: 不存在或已终止"
            fi
        done
    fi
    echo "================================================"
    echo ""
}

collect_kspect() {
    log_info "执行：健康度检查"
    
    if ! check_command kspect; then
        log_warning "kspect命令未找到，跳过健康度检查"
        return
    fi
    # 创建临时文件
    temp_kspect_file="${KSPECT_FILE}.tmp"
    
    echo "==================== 健康度检查 ====================" > "$temp_kspect_file"
    
    local kspect_exit_code=0
    local kspect_temp_output=$(mktemp)
    local kspect_start_time=$(date +%s)
    
    # 执行 kspect，捕获输出和退出码
    kspect -s all > "$kspect_temp_output" 2>&1
    kspect_exit_code=$?
    local kspect_end_time=$(date +%s)
    local kspect_duration=$((kspect_end_time - kspect_start_time))
    
    if [ $kspect_exit_code -eq 0 ]; then
        # kspect 执行成功
        cat "$kspect_temp_output" >> "$temp_kspect_file"
        
        # 移除 ANSI 颜色代码
        sed -i 's/\x1b\[[0-9;]*m//g' "$temp_kspect_file"
        
        echo "" >> "$temp_kspect_file"
        echo "✓ kspect 执行成功 (实际运行时长=${kspect_duration}秒)" >> "$temp_kspect_file"
        echo "" >> "$temp_kspect_file"
        echo "============================================================" >> "$temp_kspect_file"
        echo "健康度检查完成" >> "$temp_kspect_file"
        echo "============================================================" >> "$temp_kspect_file"
        
        # 移动临时文件到正式文件
        mv "$temp_kspect_file" "$KSPECT_FILE"
        log_success "√ 健康度检查完成，结果保存至: $KSPECT_FILE"
        
    else
        # kspect 执行失败
        echo "错误: kspect 执行失败 (退出码=$kspect_exit_code, 运行时长=${kspect_duration}秒)" >> "$temp_kspect_file"
        echo "错误详情:" >> "$temp_kspect_file"
        cat "$kspect_temp_output" >> "$temp_kspect_file"
        echo "" >> "$temp_kspect_file"
        
        # 分析失败原因
        if [ $kspect_exit_code -eq 124 ]; then
            echo "原因: timeout 超时" >> "$temp_kspect_file"
            log_error "kspect 执行超时"
        elif grep -q "permission denied\|Permission denied" "$kspect_temp_output" 2>/dev/null; then
            echo "原因: 权限不足" >> "$temp_kspect_file"
            echo "解决方案:" >> "$temp_kspect_file"
            echo "  1. 以 root 用户运行脚本" >> "$temp_kspect_file"
            echo "  2. 检查 kspect 命令权限" >> "$temp_kspect_file"
            log_error "kspect 权限不足"
        elif grep -q "connection refused\|Connection refused" "$kspect_temp_output" 2>/dev/null; then
            echo "原因: kspect 服务连接失败" >> "$temp_kspect_file"
            echo "解决方案:" >> "$temp_kspect_file"
            echo "  1. 检查 kspect 服务是否运行" >> "$temp_kspect_file"
            echo "  2. 检查网络连接" >> "$temp_kspect_file"
            log_error "kspect 连接失败"
        elif grep -q "invalid option\|unrecognized option" "$kspect_temp_output" 2>/dev/null; then
            echo "原因: kspect 版本不支持 -s all 参数" >> "$temp_kspect_file"
            echo "解决方案:" >> "$temp_kspect_file"
            echo "  1. 检查 kspect 版本: kspect --version" >> "$temp_kspect_file"
            echo "  2. 查看支持的参数: kspect --help" >> "$temp_kspect_file"
            log_error "kspect 参数不支持"
        elif grep -q "not found\|No such file" "$kspect_temp_output" 2>/dev/null; then
            echo "原因: 依赖组件缺失" >> "$temp_kspect_file"
            log_error "kspect 依赖缺失"
        elif grep -q "timeout\|timed out" "$kspect_temp_output" 2>/dev/null; then
            echo "原因: 健康检查超时" >> "$temp_kspect_file"
            log_error "kspect 健康检查超时"
        else
            echo "原因: 未知错误" >> "$temp_kspect_file"
            log_error "kspect 执行失败 (退出码=$kspect_exit_code)"
        fi
        
        # 记录失败详情到错误日志
        if [ -n "$ERROR_LOG" ]; then
            # 移除 ANSI 颜色代码后再记录
            sed 's/\x1b\[[0-9;]*m//g' "$temp_kspect_file" >> "$ERROR_LOG" 2>/dev/null
        fi
        
        # 删除临时文件，不生成正式文件
        rm -f "$temp_kspect_file"
        log_warning "健康度检查失败，未生成 $KSPECT_FILE"
    fi
    
    # 清理临时输出文件
    rm -f "$kspect_temp_output"
}

collect_devkit_topdown() {
    log_info "执行: devkit topdown数据采集"
    
    # 标记是否有任何成功的采集
    topdown_success=false
    
    if ! check_command devkit; then
        log_warning "devkit命令未找到，跳过topdown采集"
        return
    fi
    
    # 创建临时文件
    temp_topdown_file="${TOPDOWN_FILE}.tmp"
    
    if [[ -n "$PIDS" ]]; then
        IFS=',' read -ra pid_array <<< "$PIDS"
        for single_pid in "${pid_array[@]}"; do
            single_pid=$(echo "$single_pid" | xargs)
            
            log_info "运行devkit tuner top-down，监控进程 $single_pid, 持续${DURATION}秒..."
            
            # 为每个 PID 创建临时文件（追加模式）
            if [ ! -f "$temp_topdown_file" ]; then
                echo "运行devkit tuner top-down，监控进程 $single_pid, 持续${DURATION}秒..." > "$temp_topdown_file"
            else
                echo "" >> "$temp_topdown_file"
                echo "运行devkit tuner top-down，监控进程 $single_pid, 持续${DURATION}秒..." >> "$temp_topdown_file"
            fi
            
            # 执行 devkit tuner top-down
            local devkit_output
            local devkit_exit_code=0
            local devkit_temp_output=$(mktemp)
            local devkit_start_time=$(date +%s)
            
            # 执行命令，捕获输出和退出码
            timeout $((DURATION + TIMEOUT_DURATION)) devkit tuner top-down -d "$DURATION" -p "$single_pid" > "$devkit_temp_output" 2>&1
            devkit_exit_code=$?
            local devkit_end_time=$(date +%s)
            local devkit_duration=$((devkit_end_time - devkit_start_time))
            
            if [ $devkit_exit_code -eq 0 ]; then
                # devkit 执行成功
                cat "$devkit_temp_output" >> "$temp_topdown_file"
                echo "" >> "$temp_topdown_file"
                echo "✓ devkit topdown 执行成功 (PID=$single_pid, 实际运行时长=${devkit_duration}秒)" >> "$temp_topdown_file"
                log_success "devkit topdown 数据采集成功 (PID=$single_pid)"
                topdown_success=true
            else
                # devkit 执行失败
                echo "错误: devkit topdown 执行失败 (PID=$single_pid, 退出码=$devkit_exit_code, 运行时长=${devkit_duration}秒)" >> "$temp_topdown_file"
                echo "错误详情:" >> "$temp_topdown_file"
                cat "$devkit_temp_output" >> "$temp_topdown_file"
                echo "" >> "$temp_topdown_file"
                
                # 分析失败原因
                if [ $devkit_exit_code -eq 124 ]; then
                    echo "原因: timeout 超时 (devkit 执行超过 ${DURATION}+${TIMEOUT_DURATION} 秒)" >> "$temp_topdown_file"
                elif grep -q "permission denied\|Permission denied" "$devkit_temp_output" 2>/dev/null; then
                    echo "原因: 权限不足" >> "$temp_topdown_file"
                    echo "解决方案:" >> "$temp_topdown_file"
                    echo "  1. 以 root 用户运行脚本" >> "$temp_topdown_file"
                    echo "  2. 检查进程属主和权限" >> "$temp_topdown_file"
                elif grep -q "no such process\|No such process\|invalid pid" "$devkit_temp_output" 2>/dev/null; then
                    echo "原因: 进程不存在或已退出" >> "$temp_topdown_file"
                elif grep -q "connection refused\|Connection refused" "$devkit_temp_output" 2>/dev/null; then
                    echo "原因: devkit 服务连接失败" >> "$temp_topdown_file"
                    echo "解决方案:" >> "$temp_topdown_file"
                    echo "  1. 检查 devkit 服务是否运行" >> "$temp_topdown_file"
                    echo "  2. 检查网络连接" >> "$temp_topdown_file"
                elif grep -q "not supported\|unsupported" "$devkit_temp_output" 2>/dev/null; then
                    echo "原因: 当前平台或CPU不支持 top-down 分析" >> "$temp_topdown_file"
                else
                    echo "原因: 未知错误" >> "$temp_topdown_file"
                fi
                
                log_error "devkit topdown 数据采集失败 (PID=$single_pid, 退出码=$devkit_exit_code)"
                
                # 记录失败详情到错误日志
                if [ -n "$ERROR_LOG" ]; then
                    cat "$temp_topdown_file" >> "$ERROR_LOG" 2>/dev/null
                fi
            fi
            
            # 清理临时输出文件
            rm -f "$devkit_temp_output"
        done
    else
        # 没有指定 PIDS，采集系统整体数据
        log_info "运行devkit tuner top-down，持续${DURATION}秒..."
        
        echo "运行devkit tuner top-down (系统整体)，持续${DURATION}秒..." > "$temp_topdown_file"
        
        local devkit_output
        local devkit_exit_code=0
        local devkit_temp_output=$(mktemp)
        local devkit_start_time=$(date +%s)
        
        timeout $((DURATION + TIMEOUT_DURATION)) devkit tuner top-down -d "$DURATION" > "$devkit_temp_output" 2>&1
        devkit_exit_code=$?
        local devkit_end_time=$(date +%s)
        local devkit_duration=$((devkit_end_time - devkit_start_time))
        
        if [ $devkit_exit_code -eq 0 ]; then
            cat "$devkit_temp_output" >> "$temp_topdown_file"
            echo "" >> "$temp_topdown_file"
            echo "✓ devkit topdown 执行成功 (实际运行时长=${devkit_duration}秒)" >> "$temp_topdown_file"
            log_success "devkit topdown 系统整体数据采集成功"
            topdown_success=true
        else
            echo "错误: devkit topdown 执行失败 (退出码=$devkit_exit_code, 运行时长=${devkit_duration}秒)" >> "$temp_topdown_file"
            echo "错误详情:" >> "$temp_topdown_file"
            cat "$devkit_temp_output" >> "$temp_topdown_file"
            
            if [ $devkit_exit_code -eq 124 ]; then
                echo "原因: timeout 超时" >> "$temp_topdown_file"
            elif grep -q "permission denied\|Permission denied" "$devkit_temp_output" 2>/dev/null; then
                echo "原因: 权限不足" >> "$temp_topdown_file"
            elif grep -q "not supported\|unsupported" "$devkit_temp_output" 2>/dev/null; then
                echo "原因: 当前平台或CPU不支持 top-down 分析" >> "$temp_topdown_file"
            fi
            
            log_error "devkit topdown 系统整体数据采集失败 (退出码=$devkit_exit_code)"
            
            if [ -n "$ERROR_LOG" ]; then
                cat "$temp_topdown_file" >> "$ERROR_LOG" 2>/dev/null
            fi
        fi
        
        rm -f "$devkit_temp_output"
    fi
    
    # 只有在成功执行了至少一次 devkit topdown 时才生成最终文件
    if [ "$topdown_success" = true ]; then
        echo "" >> "$temp_topdown_file"
        echo "============================================================" >> "$temp_topdown_file"
        echo "devkit topdown 数据采集完成 (PIDS=${PIDS:-system})" >> "$temp_topdown_file"
        echo "============================================================" >> "$temp_topdown_file"
        
        mv "$temp_topdown_file" "$TOPDOWN_FILE"
        log_success "√ devkit topdown 数据采集完成，结果保存至: $TOPDOWN_FILE"
    else
        # 没有成功的采集，删除临时文件
        rm -f "$temp_topdown_file"
        log_warning "devkit topdown 数据采集全部失败，未生成 $TOPDOWN_FILE"
    fi
}

collect_devkit_hotspot() {
    log_info "执行：devkit hotspot数据采集"
    
    # 标记是否有任何成功的采集
    hotspot_success=false
    
    if ! check_command devkit; then
        log_warning "devkit命令未找到，跳过hotspot采集"
        return
    fi
    
    # 创建临时文件
    temp_hotspot_file="${HOTSPOT_FILE}.tmp"
    
    if [[ -n "$PIDS" ]]; then
        IFS=',' read -ra pid_array <<< "$PIDS"
        for single_pid in "${pid_array[@]}"; do
            single_pid=$(echo "$single_pid" | xargs)
            
            log_info "运行devkit tuner hotspot，监控进程 $single_pid, 持续${DURATION}秒..."
            
            # 为每个 PID 创建临时文件（追加模式）
            if [ ! -f "$temp_hotspot_file" ]; then
                echo "运行devkit tuner hotspot，监控进程 $single_pid, 持续${DURATION}秒..." > "$temp_hotspot_file"
            else
                echo "" >> "$temp_hotspot_file"
                echo "运行devkit tuner hotspot，监控进程 $single_pid, 持续${DURATION}秒..." >> "$temp_hotspot_file"
            fi
            
            # 执行 devkit tuner hotspot
            local devkit_exit_code=0
            local devkit_temp_output=$(mktemp)
            local devkit_start_time=$(date +%s)
            
            # 执行命令，捕获输出和退出码
            timeout $((DURATION + TIMEOUT_DURATION)) devkit tuner hotspot -d "$DURATION" -p "$single_pid" > "$devkit_temp_output" 2>&1
            devkit_exit_code=$?
            local devkit_end_time=$(date +%s)
            local devkit_duration=$((devkit_end_time - devkit_start_time))
            
            if [ $devkit_exit_code -eq 0 ]; then
                # devkit 执行成功
                cat "$devkit_temp_output" >> "$temp_hotspot_file"
                echo "" >> "$temp_hotspot_file"
                echo "✓ devkit hotspot 执行成功 (PID=$single_pid, 实际运行时长=${devkit_duration}秒)" >> "$temp_hotspot_file"
                log_success "devkit hotspot 数据采集成功 (PID=$single_pid)"
                hotspot_success=true
            else
                # devkit 执行失败
                echo "错误: devkit hotspot 执行失败 (PID=$single_pid, 退出码=$devkit_exit_code, 运行时长=${devkit_duration}秒)" >> "$temp_hotspot_file"
                echo "错误详情:" >> "$temp_hotspot_file"
                cat "$devkit_temp_output" >> "$temp_hotspot_file"
                echo "" >> "$temp_hotspot_file"
                
                # 分析失败原因
                if [ $devkit_exit_code -eq 124 ]; then
                    echo "原因: timeout 超时 (devkit 执行超过 ${DURATION}+${TIMEOUT_DURATION} 秒)" >> "$temp_hotspot_file"
                    log_error "devkit hotspot 执行超时 (PID=$single_pid)"
                elif grep -q "permission denied\|Permission denied" "$devkit_temp_output" 2>/dev/null; then
                    echo "原因: 权限不足" >> "$temp_hotspot_file"
                    echo "解决方案:" >> "$temp_hotspot_file"
                    echo "  1. 以 root 用户运行脚本" >> "$temp_hotspot_file"
                    echo "  2. 检查进程属主和权限" >> "$temp_hotspot_file"
                    echo "  3. 调整 perf_event_paranoid: echo 1 > /proc/sys/kernel/perf_event_paranoid" >> "$temp_hotspot_file"
                    log_error "devkit hotspot 权限不足 (PID=$single_pid)"
                elif grep -q "no such process\|No such process\|invalid pid" "$devkit_temp_output" 2>/dev/null; then
                    echo "原因: 进程不存在或已退出" >> "$temp_hotspot_file"
                    log_error "devkit hotspot 进程不存在 (PID=$single_pid)"
                elif grep -q "connection refused\|Connection refused" "$devkit_temp_output" 2>/dev/null; then
                    echo "原因: devkit 服务连接失败" >> "$temp_hotspot_file"
                    echo "解决方案:" >> "$temp_hotspot_file"
                    echo "  1. 检查 devkit 服务是否运行" >> "$temp_hotspot_file"
                    echo "  2. 检查网络连接" >> "$temp_hotspot_file"
                    log_error "devkit hotspot 连接失败 (PID=$single_pid)"
                elif grep -q "not supported\|unsupported" "$devkit_temp_output" 2>/dev/null; then
                    echo "原因: 当前平台或CPU不支持 hotspot 分析" >> "$temp_hotspot_file"
                    log_error "devkit hotspot 平台不支持 (PID=$single_pid)"
                elif grep -q "invalid option\|unrecognized option" "$devkit_temp_output" 2>/dev/null; then
                    echo "原因: devkit 版本不支持 hotspot 子命令或参数" >> "$temp_hotspot_file"
                    echo "解决方案:" >> "$temp_hotspot_file"
                    echo "  1. 检查 devkit 版本: devkit --version" >> "$temp_hotspot_file"
                    echo "  2. 查看支持的子命令: devkit tuner --help" >> "$temp_hotspot_file"
                    log_error "devkit hotspot 子命令不支持 (PID=$single_pid)"
                else
                    echo "原因: 未知错误" >> "$temp_hotspot_file"
                    log_error "devkit hotspot 执行失败 (PID=$single_pid, 退出码=$devkit_exit_code)"
                fi
                
                # 记录失败详情到错误日志
                if [ -n "$ERROR_LOG" ]; then
                    cat "$temp_hotspot_file" >> "$ERROR_LOG" 2>/dev/null
                fi
            fi
            
            # 清理临时输出文件
            rm -f "$devkit_temp_output"
        done
    else
        # 没有指定 PIDS，采集系统整体数据
        log_info "运行devkit tuner hotspot (系统整体)，持续${DURATION}秒..."
        
        echo "运行devkit tuner hotspot (系统整体)，持续${DURATION}秒..." > "$temp_hotspot_file"
        
        local devkit_exit_code=0
        local devkit_temp_output=$(mktemp)
        local devkit_start_time=$(date +%s)
        
        timeout $((DURATION + TIMEOUT_DURATION)) devkit tuner hotspot -d "$DURATION" > "$devkit_temp_output" 2>&1
        devkit_exit_code=$?
        local devkit_end_time=$(date +%s)
        local devkit_duration=$((devkit_end_time - devkit_start_time))
        
        if [ $devkit_exit_code -eq 0 ]; then
            cat "$devkit_temp_output" >> "$temp_hotspot_file"
            echo "" >> "$temp_hotspot_file"
            echo "✓ devkit hotspot 执行成功 (实际运行时长=${devkit_duration}秒)" >> "$temp_hotspot_file"
            log_success "devkit hotspot 系统整体数据采集成功"
            hotspot_success=true
        else
            echo "错误: devkit hotspot 执行失败 (退出码=$devkit_exit_code, 运行时长=${devkit_duration}秒)" >> "$temp_hotspot_file"
            echo "错误详情:" >> "$temp_hotspot_file"
            cat "$devkit_temp_output" >> "$temp_hotspot_file"
            
            if [ $devkit_exit_code -eq 124 ]; then
                echo "原因: timeout 超时" >> "$temp_hotspot_file"
                log_error "devkit hotspot 执行超时"
            elif grep -q "permission denied\|Permission denied" "$devkit_temp_output" 2>/dev/null; then
                echo "原因: 权限不足" >> "$temp_hotspot_file"
                log_error "devkit hotspot 权限不足"
            elif grep -q "not supported\|unsupported" "$devkit_temp_output" 2>/dev/null; then
                echo "原因: 当前平台或CPU不支持 hotspot 分析" >> "$temp_hotspot_file"
                log_error "devkit hotspot 平台不支持"
            elif grep -q "invalid option\|unrecognized option" "$devkit_temp_output" 2>/dev/null; then
                echo "原因: devkit 版本不支持 hotspot 子命令" >> "$temp_hotspot_file"
                log_error "devkit hotspot 子命令不支持"
            else
                echo "原因: 未知错误" >> "$temp_hotspot_file"
                log_error "devkit hotspot 执行失败 (退出码=$devkit_exit_code)"
            fi
            
            if [ -n "$ERROR_LOG" ]; then
                cat "$temp_hotspot_file" >> "$ERROR_LOG" 2>/dev/null
            fi
        fi
        
        rm -f "$devkit_temp_output"
    fi
    
    # 只有在成功执行了至少一次 devkit hotspot 时才生成最终文件
    if [ "$hotspot_success" = true ]; then
        echo "" >> "$temp_hotspot_file"
        echo "============================================================" >> "$temp_hotspot_file"
        echo "devkit hotspot 数据采集完成 (PIDS=${PIDS:-system})" >> "$temp_hotspot_file"
        echo "============================================================" >> "$temp_hotspot_file"
        
        mv "$temp_hotspot_file" "$HOTSPOT_FILE"
        log_success "√ devkit hotspot 数据采集完成，结果保存至: $HOTSPOT_FILE"
    else
        # 没有成功的采集，删除临时文件
        rm -f "$temp_hotspot_file"
        log_warning "devkit hotspot 数据采集全部失败，未生成 $HOTSPOT_FILE"
    fi
}

collect_devkit_numafast() {
    log_info "执行：devkit numafast数据采集"
    
    # 标记是否有任何成功的采集
    numafast_success=false
    
    if ! check_command devkit; then
        log_warning "devkit命令未找到，跳过numafast采集"
        return
    fi
    
    # 创建临时文件
    temp_numafast_file="${NUMAFAST_FILE}.tmp"
    
    if [[ -n "$PIDS" ]]; then
        IFS=',' read -ra pid_array <<< "$PIDS"
        for single_pid in "${pid_array[@]}"; do
            single_pid=$(echo "$single_pid" | xargs)
            
            log_info "运行devkit tuner numafast，监控进程 $single_pid, 持续${DURATION}秒..."
            
            # 为每个 PID 创建临时文件（追加模式）
            if [ ! -f "$temp_numafast_file" ]; then
                echo "运行devkit tuner numafast，监控进程 $single_pid, 持续${DURATION}秒..." > "$temp_numafast_file"
            else
                echo "" >> "$temp_numafast_file"
                echo "运行devkit tuner numafast，监控进程 $single_pid, 持续${DURATION}秒..." >> "$temp_numafast_file"
            fi
            
            # 执行 devkit tuner numafast
            local devkit_exit_code=0
            local devkit_temp_output=$(mktemp)
            local devkit_start_time=$(date +%s)
            
            # 执行命令，捕获输出和退出码
            devkit tuner numafast -d "$DURATION" -p "$single_pid" > "$devkit_temp_output" 2>&1
            devkit_exit_code=$?
            local devkit_end_time=$(date +%s)
            local devkit_duration=$((devkit_end_time - devkit_start_time))
            
            if [ $devkit_exit_code -eq 0 ]; then
                # devkit 执行成功
                cat "$devkit_temp_output" >> "$temp_numafast_file"
                echo "" >> "$temp_numafast_file"
                echo "✓ devkit numafast 执行成功 (PID=$single_pid, 实际运行时长=${devkit_duration}秒)" >> "$temp_numafast_file"
                log_success "devkit numafast 数据采集成功 (PID=$single_pid)"
                numafast_success=true
            else
                # devkit 执行失败
                echo "错误: devkit numafast 执行失败 (PID=$single_pid, 退出码=$devkit_exit_code, 运行时长=${devkit_duration}秒)" >> "$temp_numafast_file"
                echo "错误详情:" >> "$temp_numafast_file"
                cat "$devkit_temp_output" >> "$temp_numafast_file"
                echo "" >> "$temp_numafast_file"
                
                # 分析失败原因
                if [ $devkit_exit_code -eq 124 ]; then
                    echo "原因: timeout 超时 (devkit 执行超过 ${DURATION}+${TIMEOUT_DURATION} 秒)" >> "$temp_numafast_file"
                    log_error "devkit numafast 执行超时 (PID=$single_pid)"
                elif grep -q "permission denied\|Permission denied" "$devkit_temp_output" 2>/dev/null; then
                    echo "原因: 权限不足" >> "$temp_numafast_file"
                    echo "解决方案:" >> "$temp_numafast_file"
                    echo "  1. 以 root 用户运行脚本" >> "$temp_numafast_file"
                    echo "  2. 检查进程属主和权限" >> "$temp_numafast_file"
                    log_error "devkit numafast 权限不足 (PID=$single_pid)"
                elif grep -q "no such process\|No such process\|invalid pid" "$devkit_temp_output" 2>/dev/null; then
                    echo "原因: 进程不存在或已退出" >> "$temp_numafast_file"
                    log_error "devkit numafast 进程不存在 (PID=$single_pid)"
                elif grep -q "connection refused\|Connection refused" "$devkit_temp_output" 2>/dev/null; then
                    echo "原因: devkit 服务连接失败" >> "$temp_numafast_file"
                    echo "解决方案:" >> "$temp_numafast_file"
                    echo "  1. 检查 devkit 服务是否运行" >> "$temp_numafast_file"
                    echo "  2. 检查网络连接" >> "$temp_numafast_file"
                    log_error "devkit numafast 连接失败 (PID=$single_pid)"
                elif grep -q "not supported\|unsupported" "$devkit_temp_output" 2>/dev/null; then
                    echo "原因: 当前平台或CPU不支持 numafast 分析 (可能需要 NUMA 架构)" >> "$temp_numafast_file"
                    log_error "devkit numafast 平台不支持 (PID=$single_pid)"
                elif grep -q "invalid option\|unrecognized option" "$devkit_temp_output" 2>/dev/null; then
                    echo "原因: devkit 版本不支持 numafast 子命令或参数" >> "$temp_numafast_file"
                    echo "解决方案:" >> "$temp_numafast_file"
                    echo "  1. 检查 devkit 版本: devkit --version" >> "$temp_numafast_file"
                    echo "  2. 查看支持的子命令: devkit tuner --help" >> "$temp_numafast_file"
                    log_error "devkit numafast 子命令不支持 (PID=$single_pid)"
                elif grep -q "numa not available\|NUMA not supported" "$devkit_temp_output" 2>/dev/null; then
                    echo "原因: 系统不支持 NUMA 架构" >> "$temp_numafast_file"
                    log_error "devkit numafast 需要 NUMA 支持 (PID=$single_pid)"
                else
                    echo "原因: 未知错误" >> "$temp_numafast_file"
                    log_error "devkit numafast 执行失败 (PID=$single_pid, 退出码=$devkit_exit_code)"
                fi
                
                # 记录失败详情到错误日志
                if [ -n "$ERROR_LOG" ]; then
                    cat "$temp_numafast_file" >> "$ERROR_LOG" 2>/dev/null
                fi
            fi
            
            # 清理临时输出文件
            rm -f "$devkit_temp_output"
        done
    else
        # 没有指定 PIDS，采集系统整体数据
        log_info "运行devkit tuner numafast (系统整体)，持续${DURATION}秒..."
        
        echo "运行devkit tuner numafast (系统整体)，持续${DURATION}秒..." > "$temp_numafast_file"
        
        local devkit_exit_code=0
        local devkit_temp_output=$(mktemp)
        local devkit_start_time=$(date +%s)
        
        devkit tuner numafast -d "$DURATION" > "$devkit_temp_output" 2>&1
        devkit_exit_code=$?
        local devkit_end_time=$(date +%s)
        local devkit_duration=$((devkit_end_time - devkit_start_time))
        
        if [ $devkit_exit_code -eq 0 ]; then
            cat "$devkit_temp_output" >> "$temp_numafast_file"
            echo "" >> "$temp_numafast_file"
            echo "✓ devkit numafast 执行成功 (实际运行时长=${devkit_duration}秒)" >> "$temp_numafast_file"
            log_success "devkit numafast 系统整体数据采集成功"
            numafast_success=true
        else
            echo "错误: devkit numafast 执行失败 (退出码=$devkit_exit_code, 运行时长=${devkit_duration}秒)" >> "$temp_numafast_file"
            echo "错误详情:" >> "$temp_numafast_file"
            cat "$devkit_temp_output" >> "$temp_numafast_file"
            
            if [ $devkit_exit_code -eq 124 ]; then
                echo "原因: timeout 超时" >> "$temp_numafast_file"
                log_error "devkit numafast 执行超时"
            elif grep -q "permission denied\|Permission denied" "$devkit_temp_output" 2>/dev/null; then
                echo "原因: 权限不足" >> "$temp_numafast_file"
                log_error "devkit numafast 权限不足"
            elif grep -q "not supported\|unsupported" "$devkit_temp_output" 2>/dev/null; then
                echo "原因: 当前平台不支持 numafast 分析" >> "$temp_numafast_file"
                log_error "devkit numafast 平台不支持"
            elif grep -q "invalid option\|unrecognized option" "$devkit_temp_output" 2>/dev/null; then
                echo "原因: devkit 版本不支持 numafast 子命令" >> "$temp_numafast_file"
                log_error "devkit numafast 子命令不支持"
            elif grep -q "numa not available\|NUMA not supported" "$devkit_temp_output" 2>/dev/null; then
                echo "原因: 系统不支持 NUMA 架构" >> "$temp_numafast_file"
                log_error "devkit numafast 需要 NUMA 支持"
            else
                echo "原因: 未知错误" >> "$temp_numafast_file"
                log_error "devkit numafast 执行失败 (退出码=$devkit_exit_code)"
            fi
            
            if [ -n "$ERROR_LOG" ]; then
                cat "$temp_numafast_file" >> "$ERROR_LOG" 2>/dev/null
            fi
        fi
        
        rm -f "$devkit_temp_output"
    fi
    
    # 只有在成功执行了至少一次 devkit numafast 时才生成最终文件
    if [ "$numafast_success" = true ]; then
        echo "" >> "$temp_numafast_file"
        echo "============================================================" >> "$temp_numafast_file"
        echo "devkit numafast 数据采集完成 (PIDS=${PIDS:-system})" >> "$temp_numafast_file"
        echo "============================================================" >> "$temp_numafast_file"
        
        mv "$temp_numafast_file" "$NUMAFAST_FILE"
        log_success "√ devkit numafast 数据采集完成，结果保存至: $NUMAFAST_FILE"
    else
        # 没有成功的采集，删除临时文件
        rm -f "$temp_numafast_file"
        log_warning "devkit numafast 数据采集全部失败，未生成 $NUMAFAST_FILE"
    fi
}

collect_devkit_memory() {
    log_info "执行：devkit memory数据采集"
    
    if ! check_command devkit; then
        log_warning "devkit命令未找到，跳过memory采集"
        return
    fi
    
    # 创建临时文件
    temp_memory_file="${MEMORY_FILE}.tmp"
    
    echo "运行devkit tuner memory，持续${DURATION}秒" > "$temp_memory_file"
    log_info "运行devkit tuner memory，持续${DURATION}秒..."
    
    local devkit_exit_code=0
    local devkit_temp_output=$(mktemp)
    local devkit_start_time=$(date +%s)
    
    # 执行 devkit tuner memory，捕获输出和退出码
    timeout $((DURATION + TIMEOUT_DURATION)) devkit tuner memory -d "$DURATION" > "$devkit_temp_output" 2>&1
    devkit_exit_code=$?
    local devkit_end_time=$(date +%s)
    local devkit_duration=$((devkit_end_time - devkit_start_time))
    
    if [ $devkit_exit_code -eq 0 ]; then
        # devkit 执行成功
        cat "$devkit_temp_output" >> "$temp_memory_file"
        echo "" >> "$temp_memory_file"
        echo "✓ devkit memory 执行成功 (实际运行时长=${devkit_duration}秒)" >> "$temp_memory_file"
        echo "" >> "$temp_memory_file"
        echo "============================================================" >> "$temp_memory_file"
        echo "devkit memory 数据采集完成" >> "$temp_memory_file"
        echo "============================================================" >> "$temp_memory_file"
        
        # 移动临时文件到正式文件
        mv "$temp_memory_file" "$MEMORY_FILE"
        log_success "√ devkit memory数据采集完成，结果保存至: $MEMORY_FILE"
        
    else
        # devkit 执行失败
        echo "错误: devkit memory 执行失败 (退出码=$devkit_exit_code, 运行时长=${devkit_duration}秒)" >> "$temp_memory_file"
        echo "错误详情:" >> "$temp_memory_file"
        cat "$devkit_temp_output" >> "$temp_memory_file"
        echo "" >> "$temp_memory_file"
        
        # 分析失败原因
        if [ $devkit_exit_code -eq 124 ]; then
            echo "原因: timeout 超时 (devkit 执行超过 ${DURATION}+${TIMEOUT_DURATION} 秒)" >> "$temp_memory_file"
            log_error "devkit memory 执行超时 (${DURATION}+${TIMEOUT_DURATION}秒)"
        elif grep -q "permission denied\|Permission denied" "$devkit_temp_output" 2>/dev/null; then
            echo "原因: 权限不足" >> "$temp_memory_file"
            echo "解决方案:" >> "$temp_memory_file"
            echo "  1. 以 root 用户运行脚本" >> "$temp_memory_file"
            echo "  2. 检查 devkit 命令权限" >> "$temp_memory_file"
            log_error "devkit memory 权限不足"
        elif grep -q "connection refused\|Connection refused" "$devkit_temp_output" 2>/dev/null; then
            echo "原因: devkit 服务连接失败" >> "$temp_memory_file"
            echo "解决方案:" >> "$temp_memory_file"
            echo "  1. 检查 devkit 服务是否运行" >> "$temp_memory_file"
            echo "  2. 检查网络连接" >> "$temp_memory_file"
            log_error "devkit memory 连接失败"
        elif grep -q "invalid option\|unrecognized option" "$devkit_temp_output" 2>/dev/null; then
            echo "原因: devkit 版本不支持 memory 子命令或参数" >> "$temp_memory_file"
            echo "解决方案:" >> "$temp_memory_file"
            echo "  1. 检查 devkit 版本: devkit --version" >> "$temp_memory_file"
            echo "  2. 查看支持的子命令: devkit tuner --help" >> "$temp_memory_file"
            log_error "devkit memory 子命令不支持"
        elif grep -q "not found\|No such file" "$devkit_temp_output" 2>/dev/null; then
            echo "原因: 依赖组件缺失" >> "$temp_memory_file"
            log_error "devkit memory 依赖缺失"
        else
            echo "原因: 未知错误" >> "$temp_memory_file"
            log_error "devkit memory 执行失败 (退出码=$devkit_exit_code)"
        fi
        
        # 记录失败详情到错误日志
        if [ -n "$ERROR_LOG" ]; then
            cat "$temp_memory_file" >> "$ERROR_LOG" 2>/dev/null
        fi
        
        # 删除临时文件，不生成正式文件
        rm -f "$temp_memory_file"
        log_warning "devkit memory 数据采集失败，未生成 $MEMORY_FILE"
    fi
    
    # 清理临时输出文件
    rm -f "$devkit_temp_output"
}

collect_devkit_turbostat() {
    log_info "执行：devkit turbostat数据采集"
    
    if ! check_command devkit; then
        log_warning "devkit命令未找到，跳过turbostat采集"
        return
    fi
    
    # 创建临时文件
    temp_turbostat_file="${TURBOSTAT_FILE}.tmp"
    
    echo "运行devkit tuner turbostat，持续${DURATION}秒" > "$temp_turbostat_file"
    log_info "运行devkit tuner turbostat，持续${DURATION}秒..."
    
    local devkit_exit_code=0
    local devkit_temp_output=$(mktemp)
    local devkit_start_time=$(date +%s)
    
    # 执行 devkit tuner turbostat，捕获输出和退出码
    timeout $((DURATION + TIMEOUT_DURATION)) devkit tuner turbostat -d "$DURATION" > "$devkit_temp_output" 2>&1
    devkit_exit_code=$?
    local devkit_end_time=$(date +%s)
    local devkit_duration=$((devkit_end_time - devkit_start_time))
    
    if [ $devkit_exit_code -eq 0 ]; then
        # 检查输出是否包含有效的功率数据
        local has_valid_data=false
        
        # 检查关键指标是否都是 N/A
        if grep -q "Total Server Power (W): N/A" "$devkit_temp_output" && \
           grep -q "Total CPU Power (W): N/A" "$devkit_temp_output" && \
           grep -q "Total Memory Power (W): N/A" "$devkit_temp_output" && \
           grep -q "Inlet Temperature (C): N/A" "$devkit_temp_output" && \
           grep -q "Outlet Temperature (C): N/A" "$devkit_temp_output"; then
            # 所有关键指标都是 N/A，说明没有有效数据
           has_valid_data=false
           log_warning "turbostat 输出所有功率和温度指标均为 N/A，可能硬件不支持或需要 root 权限"
        else
            # 检查是否有至少一个有效数据（非 N/A 且非空）
            if grep -q -E "(Total Server Power \(W\):|Total CPU Power \(W\):|Total Memory Power \(W\):|Inlet Temperature \(C\):|Outlet Temperature \(C\):)\s+[0-9]+" "$devkit_temp_output"; then
                has_valid_data=true
            fi
        fi
        
        # 额外检查：确保不是只有标题或空数据
        local data_lines=$(grep -c -E "(Total Server Power|Total CPU Power|Total Memory Power|Inlet Temperature|Outlet Temperature)" "$devkit_temp_output" 2>/dev/null || echo "0")
        if [ "$data_lines" -gt 0 ] && [ "$has_valid_data" = false ]; then
            # 有指标行但都是 N/A
            log_warning "turbostat 检测到功率/温度指标但数据不可用 (N/A)"
        fi
        
        if [ "$has_valid_data" = true ]; then
            # 有有效数据，写入临时文件并移动
            cat "$devkit_temp_output" >> "$temp_turbostat_file"
            echo "" >> "$temp_turbostat_file"
            echo "✓ devkit turbostat 执行成功 (实际运行时长=${devkit_duration}秒)" >> "$temp_turbostat_file"
            echo "" >> "$temp_turbostat_file"
            echo "============================================================" >> "$temp_turbostat_file"
            echo "devkit turbostat 数据采集完成" >> "$temp_turbostat_file"
            echo "============================================================" >> "$temp_turbostat_file"
            
            mv "$temp_turbostat_file" "$TURBOSTAT_FILE"
            log_success "√ devkit turbostat数据采集完成，结果保存至: $TURBOSTAT_FILE"
        else
            # 没有有效数据，删除临时文件
            rm -f "$temp_turbostat_file"
            log_warning "devkit turbostat 未检测到有效的功率/温度数据，未生成 $TURBOSTAT_FILE"
            
            # 可选：将原始输出记录到错误日志供调试
            if [ -n "$ERROR_LOG" ] && [ -f "$ERROR_LOG" ] && [ -w "$ERROR_LOG" ]; then
                {
                    echo "========================================"
                    echo "时间: $(date)"
                    echo "命令: devkit tuner turbostat -d $DURATION"
                    echo "退出码: $devkit_exit_code"
                    echo "输出内容 (无有效数据):"
                    cat "$devkit_temp_output"
                    echo "========================================"
                } >> "$ERROR_LOG" 2>/dev/null
            fi
        fi
    else
        # devkit 执行失败
        echo "错误: devkit turbostat 执行失败 (退出码=$devkit_exit_code, 运行时长=${devkit_duration}秒)" >> "$temp_turbostat_file"
        echo "错误详情:" >> "$temp_turbostat_file"
        cat "$devkit_temp_output" >> "$temp_turbostat_file"
        echo "" >> "$temp_turbostat_file"
        
        # 分析失败原因
        if [ $devkit_exit_code -eq 124 ]; then
            echo "原因: timeout 超时 (devkit 执行超过 ${DURATION}+${TIMEOUT_DURATION} 秒)" >> "$temp_turbostat_file"
            log_error "devkit turbostat 执行超时 (${DURATION}+${TIMEOUT_DURATION}秒)"
        elif grep -q "permission denied\|Permission denied" "$devkit_temp_output" 2>/dev/null; then
            echo "原因: 权限不足" >> "$temp_turbostat_file"
            echo "解决方案:" >> "$temp_turbostat_file"
            echo "  1. 以 root 用户运行脚本" >> "$temp_turbostat_file"
            echo "  2. 检查 devkit 命令权限" >> "$temp_turbostat_file"
            echo "  3. 调整 perf_event_paranoid: echo 1 > /proc/sys/kernel/perf_event_paranoid" >> "$temp_turbostat_file"
            log_error "devkit turbostat 权限不足"
        elif grep -q "connection refused\|Connection refused" "$devkit_temp_output" 2>/dev/null; then
            echo "原因: devkit 服务连接失败" >> "$temp_turbostat_file"
            echo "解决方案:" >> "$temp_turbostat_file"
            echo "  1. 检查 devkit 服务是否运行" >> "$temp_turbostat_file"
            echo "  2. 检查网络连接" >> "$temp_turbostat_file"
            log_error "devkit turbostat 连接失败"
        elif grep -q "invalid option\|unrecognized option" "$devkit_temp_output" 2>/dev/null; then
            echo "原因: devkit 版本不支持 turbostat 子命令或参数" >> "$temp_turbostat_file"
            echo "解决方案:" >> "$temp_turbostat_file"
            echo "  1. 检查 devkit 版本: devkit --version" >> "$temp_turbostat_file"
            echo "  2. 查看支持的子命令: devkit tuner --help" >> "$temp_turbostat_file"
            log_error "devkit turbostat 子命令不支持"
        elif grep -q "not supported\|unsupported" "$devkit_temp_output" 2>/dev/null; then
            echo "原因: 当前平台或CPU不支持 turbostat 分析" >> "$temp_turbostat_file"
            echo "说明: turbostat 通常需要 Intel CPU 或特定硬件支持" >> "$temp_turbostat_file"
            log_error "devkit turbostat 平台不支持"
        else
            echo "原因: 未知错误" >> "$temp_turbostat_file"
            log_error "devkit turbostat 执行失败 (退出码=$devkit_exit_code)"
        fi
        
        # 记录失败详情到错误日志
        if [ -n "$ERROR_LOG" ] && [ -f "$ERROR_LOG" ] && [ -w "$ERROR_LOG" ]; then
            {
                echo "========================================"
                echo "时间: $(date)"
                echo "命令: devkit tuner turbostat -d $DURATION"
                echo "退出码: $devkit_exit_code"
                echo "错误输出:"
                cat "$devkit_temp_output"
                echo "========================================"
            } >> "$ERROR_LOG" 2>/dev/null
        fi
        
        # 删除临时文件，不生成正式文件
        rm -f "$temp_turbostat_file"
        log_warning "devkit turbostat 数据采集失败，未生成 $TURBOSTAT_FILE"
    fi
    
    # 清理临时输出文件
    rm -f "$devkit_temp_output"
}

collect_ksys() {
    log_info "执行：devkit ksys数据采集"
    
    if ! check_command ksys; then
        log_warning "ksys命令未找到，跳过数据采集"
        return
    fi
    
    # 标记是否有任何成功的 ksys 执行
    ksys_analysis_success=false
    
    if [[ -n "$PIDS" ]]; then
        IFS=',' read -ra pid_array <<< "$PIDS"
        for single_pid in "${pid_array[@]}"; do
            single_pid=$(echo "$single_pid" | xargs)
            
            log_info "运行devkit ksys，监控进程 $single_pid, 持续${DURATION}秒..."
            
            # 为每个 PID 创建临时文件
            temp_ksys_file="${KSYS_FILE}.tmp.${single_pid}"
            
            echo "运行devkit ksys，监控进程 $single_pid, 持续${DURATION}秒..." > "$temp_ksys_file"
            
            # 执行 ksys collect
            local ksys_output
            local ksys_exit_code=0
            local ksys_start_time=$(date +%s)
            
            # 使用临时文件捕获输出，避免变量过大
            local ksys_temp_output=$(mktemp)
            
            # 执行 ksys 命令，捕获退出码
            timeout $((DURATION + TIMEOUT_DURATION)) ksys collect -d "$DURATION" -p "$single_pid" -o ${OUTPUT_DIR} > "$ksys_temp_output" 2>&1
            ksys_exit_code=$?
            local ksys_end_time=$(date +%s)
            local ksys_duration=$((ksys_end_time - ksys_start_time))
            
            if [ $ksys_exit_code -eq 0 ]; then
                # ksys 执行成功
                cat "$ksys_temp_output" >> "$temp_ksys_file"
                echo "" >> "$temp_ksys_file"
                echo "✓ ksys 执行成功 (PID=$single_pid, 实际运行时长=${ksys_duration}秒)" >> "$temp_ksys_file"
                log_success "devkit ksys 数据采集成功 (PID=$single_pid)"
                
                # 将成功的临时文件内容追加到主文件
                if [ ! -f "$KSYS_FILE" ]; then
                    cat "$temp_ksys_file" > "$KSYS_FILE"
                else
                    cat "$temp_ksys_file" >> "$KSYS_FILE"
                fi
                ksys_analysis_success=true
                rm -f "$temp_ksys_file"
            else
                # ksys 执行失败
                echo "错误: ksys 执行失败 (PID=$single_pid, 退出码=$ksys_exit_code, 运行时长=${ksys_duration}秒)" >> "$temp_ksys_file"
                echo "错误详情:" >> "$temp_ksys_file"
                cat "$ksys_temp_output" >> "$temp_ksys_file"
                echo "" >> "$temp_ksys_file"
                
                # 分析失败原因
                if [ $ksys_exit_code -eq 124 ]; then
                    echo "原因: timeout 超时 (ksys 执行超过 ${DURATION}+${TIMEOUT_DURATION} 秒)" >> "$temp_ksys_file"
                elif grep -q "permission denied\|Permission denied" "$ksys_temp_output" 2>/dev/null; then
                    echo "原因: 权限不足" >> "$temp_ksys_file"
                    echo "解决方案:" >> "$temp_ksys_file"
                    echo "  1. 以 root 用户运行脚本" >> "$temp_ksys_file"
                    echo "  2. 检查进程属主和权限" >> "$temp_ksys_file"
                elif grep -q "no such process\|No such process" "$ksys_temp_output" 2>/dev/null; then
                    echo "原因: 进程不存在或已退出" >> "$temp_ksys_file"
                elif grep -q "connection refused\|Connection refused" "$ksys_temp_output" 2>/dev/null; then
                    echo "原因: devkit 服务连接失败" >> "$temp_ksys_file"
                    echo "解决方案:" >> "$temp_ksys_file"
                    echo "  1. 检查 devkit 服务是否运行" >> "$temp_ksys_file"
                    echo "  2. 检查网络连接" >> "$temp_ksys_file"
                else
                    echo "原因: 未知错误" >> "$temp_ksys_file"
                fi
                
                log_error "devkit ksys 数据采集失败 (PID=$single_pid, 退出码=$ksys_exit_code)"
                
                # 记录失败详情到错误日志
                if [ -n "$ERROR_LOG" ]; then
                    cat "$temp_ksys_file" >> "$ERROR_LOG"
                fi
                
                rm -f "$temp_ksys_file"
            fi
            
            # 清理临时输出文件
            rm -f "$ksys_temp_output"
        done
    else
        # 没有指定 PIDS，采集系统整体数据
        log_info "运行devkit tuner ksys，持续${DURATION}秒..."
        
        temp_ksys_file="${KSYS_FILE}.tmp.system"
        
        echo "devkit ksys系统整体数据采集" > "$temp_ksys_file"
        echo "采集时长: ${DURATION}秒" >> "$temp_ksys_file"
        echo "" >> "$temp_ksys_file"
        
        local ksys_output
        local ksys_exit_code=0
        local ksys_temp_output=$(mktemp)
        local ksys_start_time=$(date +%s)
        
        timeout $((DURATION + TIMEOUT_DURATION)) ksys collect -d "$DURATION" -o ${OUTPUT_DIR} > "$ksys_temp_output" 2>&1
        ksys_exit_code=$?
        local ksys_end_time=$(date +%s)
        local ksys_duration=$((ksys_end_time - ksys_start_time))
        
        if [ $ksys_exit_code -eq 0 ]; then
            cat "$ksys_temp_output" >> "$temp_ksys_file"
            echo "" >> "$temp_ksys_file"
            echo "✓ ksys 执行成功 (实际运行时长=${ksys_duration}秒)" >> "$temp_ksys_file"
            log_success "devkit ksys 系统整体数据采集成功"
            
            # 成功则移动临时文件到正式文件
            mv "$temp_ksys_file" "$KSYS_FILE"
            ksys_analysis_success=true
        else
            echo "错误: ksys 执行失败 (退出码=$ksys_exit_code, 运行时长=${ksys_duration}秒)" >> "$temp_ksys_file"
            echo "错误详情:" >> "$temp_ksys_file"
            cat "$ksys_temp_output" >> "$temp_ksys_file"
            
            if [ $ksys_exit_code -eq 124 ]; then
                echo "原因: timeout 超时" >> "$temp_ksys_file"
            elif grep -q "permission denied\|Permission denied" "$ksys_temp_output" 2>/dev/null; then
                echo "原因: 权限不足" >> "$temp_ksys_file"
            fi
            
            log_error "devkit ksys 系统整体数据采集失败 (退出码=$ksys_exit_code)"
            
            if [ -n "$ERROR_LOG" ]; then
                cat "$temp_ksys_file" >> "$ERROR_LOG"
            fi
            
            rm -f "$temp_ksys_file"
        fi
        
        rm -f "$ksys_temp_output"
    fi
    
    # 只有在成功执行了至少一次 ksys 时才生成最终文件
    if [ "$ksys_analysis_success" = true ]; then
        echo "" >> "$KSYS_FILE"
        echo "============================================================" >> "$KSYS_FILE"
        echo "devkit ksys数据采集完成 (PIDS=${PIDS:-system})" >> "$KSYS_FILE"
        echo "============================================================" >> "$KSYS_FILE"
        log_success "√ devkit ksys数据采集完成，结果保存至: $KSYS_FILE"
    else
        # 没有成功的 ksys 执行，删除主文件（如果存在）
        if [ -f "$KSYS_FILE" ]; then
            rm -f "$KSYS_FILE"
            log_warning "所有 ksys 数据采集均失败，未生成 $KSYS_FILE"
        else
            log_warning "ksys 数据采集全部失败，未生成输出文件"
        fi
    fi
}

# =============================================================================
# 新增函数：从top-down-bottleneck脚本集成
# =============================================================================

# Phase 1: 系统环境静态信息收集
collect_static_info() {
    log_info "执行：系统环境静态信息收集"
    
    echo "============================================================" > "$STATIC_FILE"
    echo "Phase 1: System Environment Static Information Collection" >> "$STATIC_FILE"
    echo "============================================================" >> "$STATIC_FILE"
    echo "" >> "$STATIC_FILE"
    
    # ---- Hardware Specifications ----
    echo "========== Hardware Specifications ==========" >> "$STATIC_FILE"
    
    echo "--- CPU Model, Sockets, Cores, Threads, Cache ---" >> "$STATIC_FILE"
    lscpu >> "$STATIC_FILE"
    
    echo "" >> "$STATIC_FILE"
    echo "--- NUMA Topology ---" >> "$STATIC_FILE"
    numactl --hardware 2>/dev/null >> "$STATIC_FILE" || true
    
    echo "" >> "$STATIC_FILE"
    echo "--- Memory DIMM Info ---" >> "$STATIC_FILE"
    dmidecode -t memory 2>/dev/null | grep -E "Size|Speed|Type|Locator" >> "$STATIC_FILE" || true
    
    echo "" >> "$STATIC_FILE"
    echo "--- Physical Memory Summary ---" >> "$STATIC_FILE"
    cat /proc/meminfo | grep -E "MemTotal|SwapTotal|HugePages_Total|HugePages_Free" >> "$STATIC_FILE"
    
    echo "" >> "$STATIC_FILE"
    echo "--- Disk Devices and Topology (ROTA=1=HDD, ROTA=0=SSD) ---" >> "$STATIC_FILE"
    lsblk -o NAME,SIZE,TYPE,ROTA,MOUNTPOINT >> "$STATIC_FILE"
    
    echo "" >> "$STATIC_FILE"
    echo "--- SCSI Device Info ---" >> "$STATIC_FILE"
    cat /proc/scsi/scsi 2>/dev/null >> "$STATIC_FILE" || true
    
    echo "" >> "$STATIC_FILE"
    echo "--- NIC Models ---" >> "$STATIC_FILE"
    lspci | grep -i eth >> "$STATIC_FILE" || true
    
    echo "" >> "$STATIC_FILE"
    echo "--- NIC Driver and Firmware ---" >> "$STATIC_FILE"
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        echo "=== $iface ===" >> "$STATIC_FILE"
        ethtool -i "$iface" 2>/dev/null >> "$STATIC_FILE" || true
    done
    
    echo "" >> "$STATIC_FILE"
    echo "--- Hardware Model ---" >> "$STATIC_FILE"
    cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null >> "$STATIC_FILE" || true
    dmidecode -t system 2>/dev/null | grep -E "Manufacturer|Product Name|Version" >> "$STATIC_FILE" || true
    
    echo "" >> "$STATIC_FILE"
    echo "--- CPU Frequency Scaling ---" >> "$STATIC_FILE"
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null >> "$STATIC_FILE" || true
    cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null >> "$STATIC_FILE" || true
    
    # ---- Software Versions ----
    echo "" >> "$STATIC_FILE"
    echo "========== Software Versions ==========" >> "$STATIC_FILE"
    
    echo "--- OS Release ---" >> "$STATIC_FILE"
    cat /etc/os-release >> "$STATIC_FILE"
    
    echo "" >> "$STATIC_FILE"
    echo "--- Kernel Version ---" >> "$STATIC_FILE"
    uname -r >> "$STATIC_FILE" && uname -v >> "$STATIC_FILE"
    
    echo "" >> "$STATIC_FILE"
    echo "--- GCC Version ---" >> "$STATIC_FILE"
    gcc --version 2>/dev/null | head -1 >> "$STATIC_FILE" || true
    
    echo "" >> "$STATIC_FILE"
    echo "--- glibc Version ---" >> "$STATIC_FILE"
    ldd --version 2>/dev/null | head -1 >> "$STATIC_FILE" || true
    
    # ---- Kernel Boot Parameters ----
    echo "" >> "$STATIC_FILE"
    echo "========== Kernel Boot Parameters ==========" >> "$STATIC_FILE"
    
    echo "--- Kernel Command Line ---" >> "$STATIC_FILE"
    cat /proc/cmdline >> "$STATIC_FILE"
    
    echo "" >> "$STATIC_FILE"
    echo "--- Performance-Related sysctl: vm.* ---" >> "$STATIC_FILE"
    sysctl -a 2>/dev/null | grep -E "^vm\.(swappiness|dirty_ratio|dirty_background_ratio|dirty_writeback_centisecs|min_free_kbytes|vfs_cache_pressure|overcommit_memory|overcommit_ratio|nr_hugepages|zone_reclaim_mode|numa_balancing)" >> "$STATIC_FILE" || true
    
    echo "" >> "$STATIC_FILE"
    echo "--- Performance-Related sysctl: net.* ---" >> "$STATIC_FILE"
    sysctl -a 2>/dev/null | grep -E "^net\.(core\.(somaxconn|netdev_max_backlog|netdev_budget|rmem_max|wmem_max)|ipv4\.(tcp_tw_reuse|tcp_max_syn_backlog|tcp_rmem|tcp_wmem|tcp_syncookies|tcp_fin_timeout|tcp_fastopen))" >> "$STATIC_FILE" || true
    
    echo "" >> "$STATIC_FILE"
    echo "--- Performance-Related sysctl: kernel.sched*/numa/threads ---" >> "$STATIC_FILE"
    sysctl -a 2>/dev/null | grep -E "^kernel\.(sched_(min_granularity_ns|wakeup_granularity_ns|migration_cost_ns|cfs_bandwidth_slice_us|autogroup_enabled)|numa_balancing|threads-max)" >> "$STATIC_FILE" || true
    
    echo "" >> "$STATIC_FILE"
    echo "--- Performance-Related sysctl: fs.* ---" >> "$STATIC_FILE"
    sysctl -a 2>/dev/null | grep -E "^fs\.(file-max|aio-max-nr|nr_open|inotify\.)" >> "$STATIC_FILE" || true
    
    echo "" >> "$STATIC_FILE"
    echo "--- Performance-Relevant Kernel Modules ---" >> "$STATIC_FILE"
    lsmod 2>/dev/null | grep -iE "kvm|nvme|mlx|io_uring|dpdk|vfio|iommu|intel_cstate|intel_uncore|acpi_cpufreq|cpufreq|tuned" >> "$STATIC_FILE" || true
    
    echo "" >> "$STATIC_FILE"
    echo "--- Kernel Tickless / nohz / Preempt Config ---" >> "$STATIC_FILE"
    cat /boot/config-$(uname -r) 2>/dev/null | grep -E "NO_HZ|HZ_1000|PREEMPT" >> "$STATIC_FILE" || true
    
    echo "" >> "$STATIC_FILE"
    echo "--- Transparent Hugepage Status ---" >> "$STATIC_FILE"
    cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null >> "$STATIC_FILE" || true
    
    echo "" >> "$STATIC_FILE"
    echo "--- I/O Scheduler per Block Device ---" >> "$STATIC_FILE"
    for dev in $(ls /sys/block/); do
        echo "$dev: $(cat /sys/block/$dev/queue/scheduler 2>/dev/null)" >> "$STATIC_FILE"
    done || true
    
    echo "" >> "$STATIC_FILE"
    echo "--- Default IRQ Affinity ---" >> "$STATIC_FILE"
    cat /proc/irq/default_smp_affinity 2>/dev/null >> "$STATIC_FILE" || true
    
    echo "" >> "$STATIC_FILE"
    echo "============================================================" >> "$STATIC_FILE"
    echo "Phase 1: Static Information Collection Complete" >> "$STATIC_FILE"
    echo "============================================================" >> "$STATIC_FILE"
    
    log_success "√ 系统环境静态信息收集完成"
}

# Phase 2.1: 全局资源瓶颈识别
collect_global_bottleneck() {
    log_info "执行：全局资源瓶颈识别"
    
    # 标记是否有任何成功的采集
    bottleneck_success=false
    
    # 创建临时文件
    temp_bottleneck_file="${BOTTLENECK_FILE}.tmp"
    
    echo "============================================================" > "$temp_bottleneck_file"
    echo "Phase 2.1: Global Resource Bottleneck Identification" >> "$temp_bottleneck_file"
    echo "============================================================" >> "$temp_bottleneck_file"
    echo "" >> "$temp_bottleneck_file"
    
    # ---- CPU Bottleneck Indicators ----
    echo "========== CPU Bottleneck Indicators ==========" >> "$temp_bottleneck_file"
    
    # mpstat 检查
    if command -v mpstat &> /dev/null; then
        echo "--- CPU Utilization Per Core (5s sample, skip 100% idle) ---" >> "$temp_bottleneck_file"
        mpstat -P ALL 1 5 2>/dev/null | grep 'Average' | awk 'NR==1 || $3=="all" || $NF != "100.00"' >> "$temp_bottleneck_file"
        bottleneck_success=true
    else
        echo "--- CPU Utilization Per Core: mpstat not available (install sysstat) ---" >> "$temp_bottleneck_file"
        log_warning "mpstat not available, CPU utilization info skipped"
    fi
    
    echo "" >> "$temp_bottleneck_file"
    
    # loadavg 检查（总是可用）
    echo "--- Load Average vs CPU Count ---" >> "$temp_bottleneck_file"
    if [ -r /proc/loadavg ]; then
        cat /proc/loadavg >> "$temp_bottleneck_file"
        bottleneck_success=true
    else
        echo "Cannot read /proc/loadavg" >> "$temp_bottleneck_file"
    fi
    
    echo "" >> "$temp_bottleneck_file"
    
    # vmstat 检查
    echo "--- Context Switches and Interrupts (5s interval) ---" >> "$temp_bottleneck_file"
    if command -v vmstat &> /dev/null; then
        vmstat 5 2 2>/dev/null | awk 'NR<=2{print; next} NR==3{next} {print; exit}' >> "$temp_bottleneck_file"
        bottleneck_success=true
    else
        echo "vmstat not available" >> "$temp_bottleneck_file"
    fi
    
    echo "" >> "$temp_bottleneck_file"
    
    # pidstat 检查
    echo "--- Top 30 Context Switch Tasks (by cswch/s) ---" >> "$temp_bottleneck_file"
    if command -v pidstat &> /dev/null; then
        {
            echo "      UID       PID   cswch/s nvcswch/s  Command"
            pidstat -w 1 5 2>/dev/null | grep 'Average' | grep -v "UID" | sort -k4 -rn | head -30
        } >> "$temp_bottleneck_file"
        bottleneck_success=true
    else
        echo "pidstat not available (install sysstat)" >> "$temp_bottleneck_file"
    fi
    
    echo "" >> "$temp_bottleneck_file"
    
    # ---- Memory Bottleneck Indicators ----
    echo "========== Memory Bottleneck Indicators ==========" >> "$temp_bottleneck_file"
    
    # free 检查
    echo "--- Swap Usage and Pressure ---" >> "$temp_bottleneck_file"
    if command -v free &> /dev/null; then
        free -h >> "$temp_bottleneck_file"
        bottleneck_success=true
    else
        echo "free not available" >> "$temp_bottleneck_file"
    fi
    
    echo "" >> "$temp_bottleneck_file"
    
    # meminfo 检查（总是可读）
    echo "--- Key Swap Metrics ---" >> "$temp_bottleneck_file"
    if [ -r /proc/meminfo ]; then
        cat /proc/meminfo | grep -E "SwapTotal|SwapFree|SwapCached|CommitLimit|Committed_AS" >> "$temp_bottleneck_file"
        bottleneck_success=true
    else
        echo "Cannot read /proc/meminfo" >> "$temp_bottleneck_file"
    fi
    
    echo "" >> "$temp_bottleneck_file"
    
    # pidstat 内存统计检查
    echo "--- Page Faults - Top 20 by majflt/s ---" >> "$temp_bottleneck_file"
    if command -v pidstat &> /dev/null; then
        {
            echo "      UID       PID  minflt/s  majflt/s     VSZ     RSS   %MEM  Command"
            pidstat -r 1 5 2>/dev/null | grep 'Average' | grep -v "UID" | sort -k5 -rn | head -20
        } >> "$temp_bottleneck_file"
        bottleneck_success=true
    else
        echo "pidstat not available (install sysstat)" >> "$temp_bottleneck_file"
    fi
    
    echo "" >> "$temp_bottleneck_file"
    
    # slab 信息检查
    echo "--- Slab Memory Usage ---" >> "$temp_bottleneck_file"
    if [ -r /proc/meminfo ]; then
        cat /proc/meminfo | grep -E "Slab|SReclaimable|SUnreclaim" >> "$temp_bottleneck_file"
        bottleneck_success=true
    else
        echo "Cannot read /proc/meminfo" >> "$temp_bottleneck_file"
    fi
    
    echo "" >> "$temp_bottleneck_file"
    
    # ---- I/O Bottleneck Indicators ----
    echo "========== I/O Bottleneck Indicators ==========" >> "$temp_bottleneck_file"
    
    # iostat 检查
    echo "--- Disk Utilization (5s sample, skip 0% util) ---" >> "$temp_bottleneck_file"
    if command -v iostat &> /dev/null; then
        iostat -xz 5 2 2>/dev/null | awk '/^avg-cpu/{report++; if(report==2) print; next} /^Device/{if(report==2) print; next} /^$/{next} /Linux/{next} report==2 {if(/^[[:space:]]*[0-9]/){print; next} if(/^[a-z]/ && $NF+0>0){print; next}}' >> "$temp_bottleneck_file"
        bottleneck_success=true
    else
        echo "iostat not available (install sysstat)" >> "$temp_bottleneck_file"
    fi
    
    echo "" >> "$temp_bottleneck_file"
    
    # diskstats 检查
    echo "--- Queue Depth (inflight_IO, instantaneous) ---" >> "$temp_bottleneck_file"
    if [ -r /proc/diskstats ]; then
        echo "major minor device inflight_IO" >> "$temp_bottleneck_file"
        cat /proc/diskstats | awk '{print $1, $2, $3, $12}' >> "$temp_bottleneck_file"
        bottleneck_success=true
    else
        echo "Cannot read /proc/diskstats" >> "$temp_bottleneck_file"
    fi
    
    echo "" >> "$temp_bottleneck_file"

    echo "--- df -h ---" >> "$temp_bottleneck_file"
    df -h >> "$temp_bottleneck_file" 2>/dev/null

    echo "" >> "$temp_bottleneck_file"    
    # pidstat I/O 统计检查
    echo "--- Top 20 I/O Processes by kB_wr/s ---" >> "$temp_bottleneck_file"
    if command -v pidstat &> /dev/null; then
        {
            echo "      UID       PID   kB_rd/s   kB_wr/s kB_ccwr/s iodelay  Command"
            pidstat -d 1 5 2>/dev/null | grep 'Average' | grep -v "UID" | sort -k5 -rn | head -20
        } >> "$temp_bottleneck_file"
        bottleneck_success=true
    else
        echo "pidstat not available (install sysstat)" >> "$temp_bottleneck_file"
    fi
    
    echo "" >> "$temp_bottleneck_file"
    
    # ---- Network Bottleneck Indicators ----
    echo "========== Network Bottleneck Indicators ==========" >> "$temp_bottleneck_file"
    
    # sar 网络统计检查
    echo "--- Network Interface Stats (5s sample, skip idle) ---" >> "$temp_bottleneck_file"
    if command -v sar &> /dev/null; then
        sar -n DEV 1 5 2>/dev/null | grep 'Average' | awk 'NR==1 || $5+0>0 || $6+0>0' >> "$temp_bottleneck_file"
        bottleneck_success=true
    else
        echo "sar not available (install sysstat)" >> "$temp_bottleneck_file"
    fi
    
    echo "" >> "$temp_bottleneck_file"
    
    # sar 网络错误统计检查
    echo "--- Network Error Stats (skip all-zero errors) ---" >> "$temp_bottleneck_file"
    if command -v sar &> /dev/null; then
        sar -n EDEV 1 5 2>/dev/null | grep 'Average' | awk 'NR==1{print; next} {for(i=3;i<=NF;i++) if($i+0>0){print; next}}' >> "$temp_bottleneck_file"
        bottleneck_success=true
    else
        echo "sar not available (install sysstat)" >> "$temp_bottleneck_file"
    fi
    
    echo "" >> "$temp_bottleneck_file"
    
    # nstat TCP 统计检查
    echo "--- TCP Retransmissions and Drops (5s two-snapshot delta) ---" >> "$temp_bottleneck_file"
    if command -v nstat &> /dev/null; then
        nstat -az 2>/dev/null | grep -E "^(TcpOutSegs|TcpRetransSegs|TcpExtTCPLostRetransmit|TcpExtListenOverflows|TcpExtListenDrops)" | awk '{print $1,$2}' > /tmp/nstat_before.txt
        sleep 5
        nstat -az 2>/dev/null | grep -E "^(TcpOutSegs|TcpRetransSegs|TcpExtTCPLostRetransmit|TcpExtListenOverflows|TcpExtListenDrops)" | awk '{print $1,$2}' > /tmp/nstat_after.txt
        if [ -s /tmp/nstat_before.txt ] && [ -s /tmp/nstat_after.txt ]; then
            echo "counter delta rate/s" >> "$temp_bottleneck_file"
            join /tmp/nstat_before.txt /tmp/nstat_after.txt | awk -v s=5 '{printf "%-40s %8d %8.1f\n", $1, $3-$2, ($3-$2)/s}' >> "$temp_bottleneck_file"
            bottleneck_success=true
        else
            echo "nstat: insufficient data collected" >> "$temp_bottleneck_file"
        fi
        rm -f /tmp/nstat_before.txt /tmp/nstat_after.txt
    else
        echo "nstat not available (install iproute2)" >> "$temp_bottleneck_file"
    fi
    
    echo "" >> "$temp_bottleneck_file"
    
    # ss 连接检查
    echo "--- Connection Backlog ---" >> "$temp_bottleneck_file"
    if command -v ss &> /dev/null; then
        echo "TIME_WAIT connections:" >> "$temp_bottleneck_file"
        ss -tan state time-wait 2>/dev/null | wc -l >> "$temp_bottleneck_file"
        bottleneck_success=true
    else
        echo "ss not available (install iproute2)" >> "$temp_bottleneck_file"
    fi
    
    echo "" >> "$temp_bottleneck_file"
    
    # ss 端口统计检查
    echo "--- Top 10 Ports by Established Connections ---" >> "$temp_bottleneck_file"
    if command -v ss &> /dev/null; then
        {
            echo "count port"
            ss -tn state established 2>/dev/null | awk '{print $4}' | awk -F: '{print $NF}' | sort | uniq -c | sort -rn | head -10
        } >> "$temp_bottleneck_file"
        bottleneck_success=true
    else
        echo "ss not available (install iproute2)" >> "$temp_bottleneck_file"
    fi
    
    echo "" >> "$temp_bottleneck_file"
    echo "============================================================" >> "$temp_bottleneck_file"
    echo "Phase 2.1: Global Resource Bottleneck Identification Complete" >> "$temp_bottleneck_file"
    echo "============================================================" >> "$temp_bottleneck_file"
    
    # 只有在至少有一个关键采集成功时才生成最终文件
    if [ "$bottleneck_success" = true ]; then
        mv "$temp_bottleneck_file" "$BOTTLENECK_FILE"
        log_success "√ 全局资源瓶颈识别完成，结果保存至: $BOTTLENECK_FILE"
    else
        # 没有成功的采集，删除临时文件
        rm -f "$temp_bottleneck_file"
        log_warning "全局资源瓶颈识别全部失败，未生成 $BOTTLENECK_FILE"
    fi
}

# Phase 2.2: 顶级资源进程识别
collect_top_processes() {
    log_info "执行：顶级资源进程识别"
    
    # 创建临时文件
    temp_top_proc_file="${TOP_PROC_FILE}.tmp"
    
    echo "============================================================" > "$temp_top_proc_file"
    echo "Phase 2.2: Top Resource Process Identification" >> "$temp_top_proc_file"
    echo "============================================================" >> "$temp_top_proc_file"
    echo "" >> "$temp_top_proc_file"
    
    # 标记是否有任何输出
    local has_output=false
    
    # --- Top 20 CPU Processes ---
    echo "--- Top 20 CPU Processes ---" >> "$temp_top_proc_file"
    if command -v ps &> /dev/null; then
        ps aux --sort=-%cpu 2>/dev/null | head -20 >> "$temp_top_proc_file"
        has_output=true
    else
        echo "⚠ ps command not available (install procps)" >> "$temp_top_proc_file"
    fi
    
    echo "" >> "$temp_top_proc_file"
    
    # --- Top 20 Memory Processes ---
    echo "--- Top 20 Memory Processes ---" >> "$temp_top_proc_file"
    if command -v ps &> /dev/null; then
        ps aux --sort=-%mem 2>/dev/null | head -20 >> "$temp_top_proc_file"
        has_output=true
    else
        echo "⚠ ps command not available" >> "$temp_top_proc_file"
    fi
    
    echo "" >> "$temp_top_proc_file"
    
    # --- Top 20 I/O Processes by iotop (requires root) ---
    echo "--- Top 20 I/O Processes by iotop (requires root) ---" >> "$temp_top_proc_file"
    if command -v iotop &> /dev/null; then
        # 使用临时文件单独捕获 iotop 输出
        local iotop_temp=$(mktemp)
        {
            echo "    PID  PRIO  USER     DISK READ  DISK WRITE  SWAPIN      IO    COMMAND"
            iotop -oP -b -n 5 -d 1 2>/dev/null | grep -E "^\s*[0-9]" | head -20
        } > "$iotop_temp" 2>/dev/null

        # 检查是否有数据行（排除表头）
        local data_lines=$(grep -c -E "^\s*[0-9]" "$iotop_temp" 2>/dev/null)
        if [ -s "$iotop_temp" ] && [ "${data_lines:-0}" -gt 0 ]; then
            cat "$iotop_temp" >> "$temp_top_proc_file"
            has_output=true
        else
            echo "  ℹ No I/O activity detected (may need root privileges)" >> "$temp_top_proc_file"
        fi
        rm -f "$iotop_temp"
    else
        echo "⚠ iotop not available (install: apt-get install iotop / yum install iotop)" >> "$temp_top_proc_file"
    fi
    
    echo "" >> "$temp_top_proc_file"
    
    # --- Top 20 I/O Processes by pidstat (by kB_wr/s) ---
    echo "--- Top 20 I/O Processes by pidstat (by kB_wr/s) ---" >> "$temp_top_proc_file"
    if command -v pidstat &> /dev/null; then
        # 使用临时文件单独捕获 pidstat 输出
        local pidstat_temp=$(mktemp)
        {
            echo "      UID       PID   kB_rd/s   kB_wr/s kB_ccwr/s iodelay  Command"
            pidstat -d 1 5 2>/dev/null | grep 'Average' | grep -v "UID" | sort -k5 -rn | head -20
        } > "$pidstat_temp" 2>/dev/null
        
        # 检查 pidstat 临时文件中是否有数据行（排除表头）
        local pidstat_data_lines=$(grep -c -E "^\s*[0-9]" "$pidstat_temp" 2>/dev/null)
        if [ -s "$pidstat_temp" ] && [ "${pidstat_data_lines:-0}" -gt 1 ]; then
            cat "$pidstat_temp" >> "$temp_top_proc_file"
            has_output=true
        else
            echo "  ℹ No I/O activity detected" >> "$temp_top_proc_file"
        fi
        rm -f "$pidstat_temp"
    else
        echo "⚠ pidstat not available (install sysstat)" >> "$temp_top_proc_file"
    fi
    
    echo "" >> "$temp_top_proc_file"
    echo "============================================================" >> "$temp_top_proc_file"
    echo "Phase 2.2: Top Resource Process Identification Complete" >> "$temp_top_proc_file"
    echo "============================================================" >> "$temp_top_proc_file"
    
    # 只要有输出就生成文件（包括部分成功的警告信息）
    if [ "$has_output" = true ]; then
        mv "$temp_top_proc_file" "$TOP_PROC_FILE"
        log_success "√ 顶级资源进程识别完成，结果保存至: $TOP_PROC_FILE"
    else
        # 完全没有输出，删除临时文件
        rm -f "$temp_top_proc_file"
        log_warning "顶级资源进程识别全部失败，未生成 $TOP_PROC_FILE"
    fi
}

# Phase 3.1: 热点函数分析（需要PID）
collect_hotspot_analysis() {
    if [[ -z "$PIDS" ]]; then
        log_warning "未指定进程，跳过热点函数分析"
        return
    fi

    # 标记是否有任何成功的 perf 执行
    hotspot_analysis_success=false
    
    IFS=',' read -ra pid_array <<< "$PIDS"
    for single_pid in "${pid_array[@]}"; do
        single_pid=$(echo "$single_pid" | xargs)

        log_info "执行：热点函数分析 (PID=$single_pid)"
        
        # 为每个 PID 创建临时文件
        temp_hotspot_file="${HOTSPOT_ANALYSIS_FILE}.tmp.${single_pid}"
        
        echo "============================================================" > "$temp_hotspot_file"
        echo "Phase 3.1: Hotspot Function Analysis (PID=$single_pid)" >> "$temp_hotspot_file"
        echo "============================================================" >> "$temp_hotspot_file"
        echo "" >> "$temp_hotspot_file"
        
        if ! check_command perf; then
            echo "错误: perf命令未找到，跳过热点函数分析" >> "$temp_hotspot_file"
            log_error "perf命令未找到"
            
            # 记录错误到错误日志
            if [ -n "$ERROR_LOG" ]; then
                cat "$temp_hotspot_file" >> "$ERROR_LOG"
            fi
            
            rm -f "$temp_hotspot_file"
            return
        fi
                
        local perf_success=false
        local perf_data_file="/tmp/perf_phase3_${single_pid}.data"
        local perf_fg_file="/tmp/perf_phase3_${single_pid}_fg.data"
        
        # 执行 perf record (30s sampling)
        echo "--- perf record (30s sampling) ---" >> "$temp_hotspot_file"
        echo "执行命令: perf record -p $single_pid -g -o $perf_data_file -- sleep 30" >> "$temp_hotspot_file"
        
        if perf_output=$(timeout 35 perf record -p "$single_pid" -g -o "$perf_data_file" -- sleep 30 2>&1); then
            echo "✓ perf record 执行成功" >> "$temp_hotspot_file"
            echo "" >> "$temp_hotspot_file"
            
            # 生成 perf report
            echo "--- perf report ---" >> "$temp_hotspot_file"
            if perf_report=$(perf report -i "$perf_data_file" --stdio --percent-limit 1 2>&1); then
                echo "$perf_report" >> "$temp_hotspot_file"
                echo "" >> "$temp_hotspot_file"
                perf_success=true
            else
                echo "警告: perf report 生成失败" >> "$temp_hotspot_file"
                echo "错误信息: $perf_report" >> "$temp_hotspot_file"
                echo "" >> "$temp_hotspot_file"
            fi
            
            # 清理 perf.data 文件
            rm -f "$perf_data_file"
        else
            local perf_exit_code=$?
            echo "错误: perf record 执行失败 (退出码=$perf_exit_code)" >> "$temp_hotspot_file"
            echo "错误详情: $perf_output" >> "$temp_hotspot_file"
            echo "" >> "$temp_hotspot_file"
            
            # 分析失败原因
            if echo "$perf_output" | grep -q "Permission denied"; then
                echo "原因: 权限不足" >> "$temp_hotspot_file"
            elif echo "$perf_output" | grep -q "No such process"; then
                echo "原因: 进程不存在或已退出" >> "$temp_hotspot_file"
            elif [ $perf_exit_code -eq 124 ]; then
                echo "原因: 超时 (可能进程在采样期间退出了)" >> "$temp_hotspot_file"
            fi
        fi
        
        # 尝试生成火焰图（仅当第一次 perf record 成功时）
        if [ "$perf_success" = true ]; then
            echo "--- perf record for flamegraph (99Hz, 30s) ---" >> "$temp_hotspot_file"
            echo "执行命令: perf record -F 99 -p $single_pid -g -o $perf_fg_file -- sleep 30" >> "$temp_hotspot_file"
            
            if perf_fg_output=$(perf record -F 99 -p "$single_pid" -g -o "$perf_fg_file" -- sleep 30 2>&1); then
                echo "✓ perf record (flamegraph) 执行成功" >> "$temp_hotspot_file"
                echo "" >> "$temp_hotspot_file"
                echo "--- Generating flamegraph ---" >> "$temp_hotspot_file"
                
                local flamegraph_success=false
                if command -v stackcollapse-perf.pl && command -v flamegraph.pl; then
                    local flamegraph_file="$OUTPUT_DIR/hotspot_flamegraph_${single_pid}.svg"
                    if perf script -i "$perf_fg_file" 2>/dev/null | stackcollapse-perf.pl 2>/dev/null | flamegraph.pl > "$flamegraph_file" 2>/dev/null; then
                        echo "✓ Flamegraph saved to $flamegraph_file" >> "$temp_hotspot_file"
                        flamegraph_success=true
                    else
                        echo "警告: Flamegraph generation failed" >> "$temp_hotspot_file"
                    fi
                else
                    log_warning "提示: stackcollapse-perf.pl 或 flamegraph.pl 未安装，跳过火焰图生成"
                    log_warning "安装方法: git clone https://github.com/brendangregg/FlameGraph.git"
                fi
                
                # 如果火焰图生成成功，标记为真正的成功
                if [ "$flamegraph_success" = true ] || [ "$perf_success" = true ]; then
                    hotspot_analysis_success=true
                fi
                
                # 清理火焰图 perf.data 文件
                rm -f "$perf_fg_file"
            else
                echo "警告: perf record (flamegraph) 执行失败，跳过火焰图生成" >> "$temp_hotspot_file"
                echo "错误信息: $perf_fg_output" >> "$temp_hotspot_file"
                # 即使火焰图失败，如果第一次 perf record 成功也算部分成功
                if [ "$perf_success" = true ]; then
                    hotspot_analysis_success=true
                fi
            fi
        fi
        
        # 如果有任何成功的部分，将临时文件追加到主文件
        if [ "$hotspot_analysis_success" = true ]; then
            if [ ! -f "$HOTSPOT_ANALYSIS_FILE" ]; then
                cat "$temp_hotspot_file" > "$HOTSPOT_ANALYSIS_FILE"
            else
                cat "$temp_hotspot_file" >> "$HOTSPOT_ANALYSIS_FILE"
            fi
            log_success "热点函数分析成功 (PID=$single_pid)"
        else
            log_error "热点函数分析失败 (PID=$single_pid)"
            # 记录失败详情到错误日志
            if [ -n "$ERROR_LOG" ]; then
                cat "$temp_hotspot_file" >> "$ERROR_LOG"
            fi
        fi
        
        # 清理临时文件
        rm -f "$temp_hotspot_file"
        
        # 清理所有临时 perf.data 文件
        rm -f /tmp/perf_phase3_${single_pid}*.data
    done
    
    # 只有在至少成功分析了一个进程时才生成最终文件
    if [ "$hotspot_analysis_success" = true ]; then
        echo "" >> "$HOTSPOT_ANALYSIS_FILE"
        echo "============================================================" >> "$HOTSPOT_ANALYSIS_FILE"
        echo "Phase 3.1: Hotspot Function Analysis Complete (PIDS=$PIDS)" >> "$HOTSPOT_ANALYSIS_FILE"
        echo "============================================================" >> "$HOTSPOT_ANALYSIS_FILE"
        log_success "√ 热点函数分析完成，结果保存至: $HOTSPOT_ANALYSIS_FILE"
    else
        # 没有成功的分析，删除主文件（如果存在）
        if [ -f "$HOTSPOT_ANALYSIS_FILE" ]; then
            rm -f "$HOTSPOT_ANALYSIS_FILE"
            log_warning "所有热点函数分析均失败，未生成 $HOTSPOT_ANALYSIS_FILE"
        else
            log_warning "热点函数分析全部失败，未生成输出文件"
        fi
    fi
}

# Phase 3.2: 系统调用分析（需要PID）
collect_syscall_analysis() {
    if [[ -z "$PIDS" ]]; then
        log_warning "未指定进程ID，跳过系统调用分析"
        return
    fi

    # 标记是否有任何成功的 strace 执行
    syscall_analysis_success=false
    # 标记是否至少有一次尝试写入了内容
    content_written=false

    IFS=',' read -ra pid_array <<< "$PIDS"
    for single_pid in "${pid_array[@]}"; do
        single_pid=$(echo "$single_pid" | xargs)
        log_info "执行：系统调用分析 (PID=$single_pid)"
        
        # 为每个 PID 创建临时文件
        temp_syscall_file="${SYSCALL_FILE}.tmp.${single_pid}"
        
        echo "============================================================" > "$temp_syscall_file"
        echo "Phase 3.2: Syscall Analysis (PID=$single_pid)" >> "$temp_syscall_file"
        echo "============================================================" >> "$temp_syscall_file"
        echo "" >> "$temp_syscall_file"
        
        if check_command strace; then
            echo "--- strace -c: Syscall summary with counts and errors ---" >> "$temp_syscall_file"
            # 执行 strace，捕获退出码
            # 注意：-o 参数会覆盖输出文件，这里改用重定向
            local strace_output
            timeout $DURATION strace -p "$single_pid" -c -f >> "$temp_syscall_file" 2>&1
            local strace_exit_code=$?
            if [ $strace_exit_code -eq 124 ];then
                echo "" >> "$temp_syscall_file"
                echo "✓ strace 执行成功 (PID=$single_pid)" >> "$temp_syscall_file"
                syscall_analysis_success=true
                content_written=true
                log_success "系统调用分析成功 (PID=$single_pid)"
                
                # 将成功的临时文件内容追加到主文件
                if [ ! -f "$SYSCALL_FILE" ]; then
                    cat "$temp_syscall_file" > "$SYSCALL_FILE"
                else
                    cat "$temp_syscall_file" >> "$SYSCALL_FILE"
                fi
                rm -f "$temp_syscall_file"
            else
                 echo "错误: strace 执行失败 (PID=$single_pid, 退出码=$strace_exit_code)" >> "$temp_syscall_file"
                echo "错误详情:" >> "$temp_syscall_file"
                echo "$strace_output" >> "$temp_syscall_file"
                echo "" >> "$temp_syscall_file"
                
                # 分析失败原因
                if echo "$strace_output" | grep -q "Operation not permitted"; then
                    echo "原因: 权限不足" >> "$temp_syscall_file"
                    echo "解决方案:" >> "$temp_syscall_file"
                    echo "  1. 以 root 用户运行脚本" >> "$temp_syscall_file"
                    echo "  2. 或添加 SYS_PTRACE capability: --cap-add=SYS_PTRACE" >> "$temp_syscall_file"
                    echo "  3. 或调整 ptrace_scope: echo 0 > /proc/sys/kernel/yama/ptrace_scope" >> "$temp_syscall_file"
                elif echo "$strace_output" | grep -q "No such process"; then
                    echo "原因: 进程不存在或已退出" >> "$temp_syscall_file"

                else
                    echo "原因: 未知错误" >> "$temp_syscall_file"
                fi
                
                log_error "系统调用分析失败 (PID=$single_pid)"
                
                # 记录错误日志但继续处理其他 PID
                echo "============================================================" >> "$temp_syscall_file"
                echo "Phase 3.2: Syscall Analysis Failed for PID=$single_pid" >> "$temp_syscall_file"
                echo "============================================================" >> "$temp_syscall_file"
                
                # 将失败信息追加到错误日志（可选）
                cat "$temp_syscall_file"
                
                rm -f "$temp_syscall_file"
                continue
            fi
        else
            echo "错误: strace命令未找到，跳过系统调用分析" >> "$temp_syscall_file"
            log_error "strace命令未找到"
            
            # 记录错误到错误日志
            cat "$temp_syscall_file"    
            rm -f "$temp_syscall_file"
            break
        fi
    done

    # 只有在成功执行了至少一次 strace 时才生成最终文件
    if [ "$syscall_analysis_success" = true ]; then
        echo "" >> "$SYSCALL_FILE"
        echo "============================================================" >> "$SYSCALL_FILE"
        echo "Phase 3.2: Syscall Analysis Complete (PIDS=$PIDS)" >> "$SYSCALL_FILE"
        echo "============================================================" >> "$SYSCALL_FILE"
        log_success "√ 系统调用分析完成，结果保存至: $SYSCALL_FILE"
    else
        # 没有成功的 strace 执行，删除主文件（如果存在）
        if [ -f "$SYSCALL_FILE" ]; then
            rm -f "$SYSCALL_FILE"
            log_warning "所有系统调用分析均失败，未生成 $SYSCALL_FILE"
        else
            log_warning "系统调用分析全部失败，未生成输出文件"
        fi
    fi
}

# Phase 4: 微架构瓶颈分析（需要PID）
collect_microarch_analysis() {
    if [[ -z "$PIDS" ]]; then
        log_warning "未指定进程ID，跳过微架构瓶颈分析"
        return
    fi

    # 标记是否有任何成功的 perf stat 执行
    microarch_analysis_success=false
    
    IFS=',' read -ra pid_array <<< "$PIDS"
    for single_pid in "${pid_array[@]}"; do
        single_pid=$(echo "$single_pid" | xargs)
        
        log_info "执行：微架构瓶颈分析 (PID=$single_pid)"
        
        # 为每个 PID 创建临时文件
        temp_microarch_file="${MICROARCH_FILE}.tmp.${single_pid}"
        
        echo "============================================================" > "$temp_microarch_file"
        echo "Phase 4: Microarchitecture Bottleneck Analysis (PID=$single_pid)" >> "$temp_microarch_file"
        echo "============================================================" >> "$temp_microarch_file"
        echo "" >> "$temp_microarch_file"
        
        if ! check_command perf; then
            echo "错误: perf命令未找到，跳过微架构瓶颈分析" >> "$temp_microarch_file"
            log_error "perf命令未找到"
            
            # 记录错误到错误日志
            if [ -n "$ERROR_LOG" ]; then
                cat "$temp_microarch_file" >> "$ERROR_LOG"
            fi
            
            rm -f "$temp_microarch_file"
            continue
        fi  
        # 检查 perf 权限
        echo "--- Checking perf permissions ---" >> "$temp_microarch_file"
        if ! timeout 2 perf stat -p "$single_pid" -e cycles sleep 0.1 2>/dev/null; then
            echo "错误: 权限不足，无法使用 perf 分析进程 PID=$single_pid" >> "$temp_microarch_file"
            echo "" >> "$temp_microarch_file"
            echo "解决方案:" >> "$temp_microarch_file"
            echo "1. 以 root 用户运行脚本" >> "$temp_microarch_file"
            echo "2. 或调整系统设置: echo 0 > /proc/sys/kernel/perf_event_paranoid" >> "$temp_microarch_file"
            echo "3. 或在容器中添加 CAP_PERFMON 或 SYS_ADMIN capability" >> "$temp_microarch_file"
            log_error "权限不足，无法使用 perf 分析进程 PID=$single_pid"
            
            if [ -n "$ERROR_LOG" ]; then
                cat "$temp_microarch_file" >> "$ERROR_LOG"
            fi
            
            rm -f "$temp_microarch_file"
            continue
        fi
        
        # 标记当前 PID 是否有成功的分析
        local pid_analysis_success=false
        local analysis_output=""
        
        # ---- CPU Cache Analysis ----
        echo "========== CPU Cache Analysis ==========" >> "$temp_microarch_file"
        
        echo "--- Cache Miss Rates (${DURATION}s) ---" >> "$temp_microarch_file"
        if cache_output=$(timeout $((DURATION + 5)) perf stat -e cache-references,cache-misses,L1-dcache-loads,L1-dcache-load-misses,LLC-loads,LLC-load-misses -p "$single_pid" -- sleep "$DURATION" 2>&1); then
            echo "$cache_output" >> "$temp_microarch_file"
            pid_analysis_success=true
            echo "✓ Cache analysis completed" >> "$temp_microarch_file"
        else
            echo "警告: Cache analysis failed (可能需要 root 权限或硬件不支持)" >> "$temp_microarch_file"
            echo "错误信息: $cache_output" >> "$temp_microarch_file"
        fi
        echo "" >> "$temp_microarch_file"
        
        echo "--- TLB Miss Statistics (${DURATION}s, tolerate if unavailable) ---" >> "$temp_microarch_file"
        if tlb_output=$(timeout $((DURATION + 5)) perf stat -e dTLB-load-misses,iTLB-load-misses -p "$single_pid" -- sleep "$DURATION" 2>&1); then
            echo "$tlb_output" >> "$temp_microarch_file"
            pid_analysis_success=true
        else
            echo "提示: TLB analysis failed (可能硬件不支持)" >> "$temp_microarch_file"
            echo "错误信息: $tlb_output" >> "$temp_microarch_file"
        fi
        echo "" >> "$temp_microarch_file"
        
        # ---- Branch Prediction and Pipeline Analysis ----
        echo "========== Branch Prediction and Pipeline Analysis ==========" >> "$temp_microarch_file"
        
        echo "--- Branch Misprediction Rate (${DURATION}s, tolerate if unavailable) ---" >> "$temp_microarch_file"
        if branch_output=$(timeout $((DURATION + 5)) perf stat -e branches,branch-misses -p "$single_pid" -- sleep "$DURATION" 2>&1); then
            echo "$branch_output" >> "$temp_microarch_file"
            pid_analysis_success=true
        else
            echo "提示: Branch analysis failed (可能硬件不支持)" >> "$temp_microarch_file"
            echo "错误信息: $branch_output" >> "$temp_microarch_file"
        fi
        echo "" >> "$temp_microarch_file"
        
        echo "--- Pipeline Stall Analysis (${DURATION}s) ---" >> "$temp_microarch_file"
        if stall_output=$(timeout $((DURATION + 5)) perf stat -e stalled-cycles-frontend,stalled-cycles-backend,cycles,instructions -p "$single_pid" -- sleep "$DURATION" 2>&1); then
            echo "$stall_output" >> "$temp_microarch_file"
            pid_analysis_success=true
        else
            echo "警告: Pipeline stall analysis failed (可能需要 root 权限)" >> "$temp_microarch_file"
            echo "错误信息: $stall_output" >> "$temp_microarch_file"
        fi
        echo "" >> "$temp_microarch_file"
        
        # ---- Top-Down Microarchitecture Analysis ----
        echo "========== Top-Down Microarchitecture Analysis ==========" >> "$temp_microarch_file"
        
        echo "--- Portable Pipeline Metrics (${DURATION}s) ---" >> "$temp_microarch_file"
        if topdown_output=$(timeout $((DURATION + 5)) perf stat -e cycles,instructions -p "$single_pid" -- sleep "$DURATION" 2>&1); then
            echo "$topdown_output" >> "$temp_microarch_file"
            pid_analysis_success=true
        else
            echo "警告: Top-down analysis failed" >> "$temp_microarch_file"
            echo "错误信息: $topdown_output" >> "$temp_microarch_file"
        fi
        echo "" >> "$temp_microarch_file"
        
        # ---- Intel-specific Analysis (仅限 Intel/AMD CPU) ----
        if grep -q "model name.*Intel\|model name.*AMD" /proc/cpuinfo 2>/dev/null; then
            echo "========== Vendor-Specific Analysis ==========" >> "$temp_microarch_file"
            
            echo "--- Intel uops Metrics (${DURATION}s, tolerate if unavailable) ---" >> "$temp_microarch_file"
            if uops_output=$(timeout $((DURATION + 5)) perf stat -e uops_executed,uops_retired -p "$single_pid" -- sleep "$DURATION" 2>&1); then
                echo "$uops_output" >> "$temp_microarch_file"
                pid_analysis_success=true
            else
                echo "提示: uops analysis failed (可能硬件不支持或需要 root 权限)" >> "$temp_microarch_file"
                echo "错误信息: $uops_output" >> "$temp_microarch_file"
            fi
            echo "" >> "$temp_microarch_file"
            
            echo "--- Intel pmu-tools Top-Down (tolerate if not installed) ---" >> "$temp_microarch_file"
            if check_command toplev; then
                if toplev_output=$(timeout $((DURATION + 5)) toplev -p "$single_pid" --sleep "$DURATION" 2>&1); then
                    echo "$toplev_output" >> "$temp_microarch_file"
                    pid_analysis_success=true
                else
                    echo "警告: toplev analysis failed" >> "$temp_microarch_file"
                    echo "错误信息: $toplev_output" >> "$temp_microarch_file"
                fi
            else
                echo "提示: toplev 未安装，跳过高级 Top-Down 分析" >> "$temp_microarch_file"
                echo "安装方法: https://github.com/andikleen/pmu-tools" >> "$temp_microarch_file"
            fi
            echo "" >> "$temp_microarch_file"
            
            # ---- Memory Bandwidth and NUMA ----
            echo "========== Memory Bandwidth and NUMA ==========" >> "$temp_microarch_file"
            
            echo "--- NUMA Locality (${DURATION}s, tolerate if unavailable) ---" >> "$temp_microarch_file"
            if numa_output=$(timeout $((DURATION + 5)) perf stat -e node_loads,node_stores,local_loads,remote_loads -p "$single_pid" -- sleep "$DURATION" 2>&1); then
                echo "$numa_output" >> "$temp_microarch_file"
                pid_analysis_success=true
            else
                echo "提示: NUMA analysis failed (可能系统不是 NUMA 架构或硬件不支持)" >> "$temp_microarch_file"
                echo "错误信息: $numa_output" >> "$temp_microarch_file"
            fi
            echo "" >> "$temp_microarch_file"
        fi
        
        # ---- Summary of analysis for this PID ----
        echo "============================================================" >> "$temp_microarch_file"
        if [ "$pid_analysis_success" = true ]; then
            echo "✓ Microarchitecture analysis completed for PID=$single_pid" >> "$temp_microarch_file"
            log_success "微架构瓶颈分析成功 (PID=$single_pid)"
            
            # 将成功的临时文件内容追加到主文件
            if [ ! -f "$MICROARCH_FILE" ]; then
                cat "$temp_microarch_file" > "$MICROARCH_FILE"
            else
                cat "$temp_microarch_file" >> "$MICROARCH_FILE"
            fi
            microarch_analysis_success=true
        else
            echo "✗ Microarchitecture analysis failed for PID=$single_pid" >> "$temp_microarch_file"
            log_error "微架构瓶颈分析失败 (PID=$single_pid)"
            
            # 记录失败详情到错误日志
            if [ -n "$ERROR_LOG" ]; then
                cat "$temp_microarch_file" >> "$ERROR_LOG"
            fi
        fi
        echo "============================================================" >> "$temp_microarch_file"
        
        # 清理临时文件
        rm -f "$temp_microarch_file"
    done
    
    # 只有在至少成功分析了一个进程时才生成最终文件
    if [ "$microarch_analysis_success" = true ]; then
        echo "" >> "$MICROARCH_FILE"
        echo "============================================================" >> "$MICROARCH_FILE"
        echo "Phase 4: Microarchitecture Bottleneck Analysis Complete (PIDS=$PIDS)" >> "$MICROARCH_FILE"
        echo "============================================================" >> "$MICROARCH_FILE"
        log_success "√ 微架构瓶颈分析完成，结果保存至: $MICROARCH_FILE"
    else
        # 没有成功的分析，删除主文件（如果存在）
        if [ -f "$MICROARCH_FILE" ]; then
            rm -f "$MICROARCH_FILE"
            log_warning "所有微架构瓶颈分析均失败，未生成 $MICROARCH_FILE"
        else
            log_warning "微架构瓶颈分析全部失败，未生成输出文件"
        fi
    fi
}

# =============================================================================
# I/O Metrics 采集函数（整合自 collect_io_metrics.sh）
# =============================================================================
collect_io_metrics() {
    log_info "执行：I/O Metrics 深度分析"
    
    # 标记是否有任何成功的采集
    io_metrics_success=false
    
    # 创建临时文件
    temp_io_file="${IO_METRICS_FILE}.tmp"
    
    # 开始写入临时文件
    echo "============================================================" > "$temp_io_file"
    echo "Phase: I/O Metrics for Bottleneck Analysis" >> "$temp_io_file"
    echo "============================================================" >> "$temp_io_file"
    echo "采集时间: $(date)" >> "$temp_io_file"
    echo "持续时间: ${DURATION}秒" >> "$temp_io_file"
    if [[ -n "$PIDS" ]]; then
        echo "目标进程: $PIDS" >> "$temp_io_file"
    fi
    echo "" >> "$temp_io_file"
    
    # === 系统概览（总是成功）===
    echo "=== System Overview ===" >> "$temp_io_file"
    echo "Kernel: $(uname -r)" >> "$temp_io_file"
    echo "CPU Count: $(nproc)" >> "$temp_io_file"
    echo "Memory Total: $(free -h | awk '/^Mem:/{print $2}')" >> "$temp_io_file"
    echo "" >> "$temp_io_file"
    io_metrics_success=true  # 系统概览算作基础成功
    
    # === 磁盘设备 ===
    echo "=== Disk Devices ===" >> "$temp_io_file"
    if lsblk -d -n -o NAME,SIZE,TYPE 2>/dev/null | grep -E 'disk|nvme' >> "$temp_io_file" 2>/dev/null; then
        echo "✓ Disk devices collected" >> "$temp_io_file"
    else
        echo "⚠ No disk devices found or lsblk not available" >> "$temp_io_file"
    fi
    echo "" >> "$temp_io_file"
    
    # === I/O调度器和队列设置 ===
    echo "=== I/O Scheduler Configuration ===" >> "$temp_io_file"
    local scheduler_collected=false
    for dev in $(lsblk -d -n -o NAME 2>/dev/null | grep -E '^vd|^sd|^nvme' | head -5); do
        if [ -r "/sys/block/$dev/queue/scheduler" ]; then
            echo "--- /dev/$dev ---" >> "$temp_io_file"
            echo "scheduler: $(cat /sys/block/$dev/queue/scheduler 2>/dev/null | grep -o '\[.*\]' || echo 'N/A')" >> "$temp_io_file"
            echo "nr_requests: $(cat /sys/block/$dev/queue/nr_requests 2>/dev/null || echo 'N/A')" >> "$temp_io_file"
            echo "read_ahead_kb: $(cat /sys/block/$dev/queue/read_ahead_kb 2>/dev/null || echo 'N/A')" >> "$temp_io_file"
            echo "max_sectors_kb: $(cat /sys/block/$dev/queue/max_sectors_kb 2>/dev/null || echo 'N/A')" >> "$temp_io_file"
            echo "rotational: $(cat /sys/block/$dev/queue/rotational 2>/dev/null || echo 'N/A')" >> "$temp_io_file"
            echo "nomerges: $(cat /sys/block/$dev/queue/nomerges 2>/dev/null || echo 'N/A')" >> "$temp_io_file"
            scheduler_collected=true
        fi
    done
    if [ "$scheduler_collected" = false ]; then
        echo "⚠ No I/O scheduler information available (可能需要 root 权限)" >> "$temp_io_file"
    fi
    echo "" >> "$temp_io_file"
    
    # === 内存和页缓存设置 ===
    echo "=== Memory/Page Cache Settings ===" >> "$temp_io_file"
    local mem_settings_collected=false
    for setting in vfs_cache_pressure swappiness dirty_background_ratio dirty_ratio dirty_writeback_centisecs dirty_expire_centisecs min_free_kbytes; do
        if [ -r "/proc/sys/vm/$setting" ]; then
            echo "$setting: $(cat /proc/sys/vm/$setting 2>/dev/null || echo 'N/A')" >> "$temp_io_file"
            mem_settings_collected=true
        fi
    done
    if [ "$mem_settings_collected" = false ]; then
        echo "⚠ Memory settings not accessible (可能需要 root 权限)" >> "$temp_io_file"
    fi
    echo "" >> "$temp_io_file"
    
    # === 进程级IO信息（如果指定了PID）===
    local process_io_collected=false
    if [[ -n "$PIDS" ]]; then
        IFS=',' read -ra pid_array <<< "$PIDS"
        for single_pid in "${pid_array[@]}"; do
            single_pid=$(echo "$single_pid" | xargs)
            if [ -d "/proc/$single_pid" ]; then
                echo "=== Process I/O Configuration (PID $single_pid) ===" >> "$temp_io_file"
                
                # IO优先级
                echo "--- IO Priority ---" >> "$temp_io_file"
                if ionice -p $single_pid >> "$temp_io_file" 2>&1; then
                    process_io_collected=true
                else
                    echo "  ionice not available or permission denied" >> "$temp_io_file"
                fi
                
                # IO统计
                echo "--- IO Statistics ---" >> "$temp_io_file"
                if [ -f "/proc/$single_pid/io" ] && cat "/proc/$single_pid/io" >> "$temp_io_file" 2>/dev/null; then
                    process_io_collected=true
                else
                    echo "  /proc/$single_pid/io not available (可能需要 root 权限)" >> "$temp_io_file"
                fi
                
                # 文件句柄限制
                echo "--- Open Files Limit ---" >> "$temp_io_file"
                if [ -r "/proc/$single_pid/limits" ]; then
                    soft=$(awk '/Max open files/ {print $4}' /proc/$single_pid/limits 2>/dev/null)
                    hard=$(awk '/Max open files/ {print $5}' /proc/$single_pid/limits 2>/dev/null)
                    echo "  soft=$soft  hard=$hard" >> "$temp_io_file"
                    process_io_collected=true
                else
                    echo "  Cannot read process limits (可能需要 root 权限)" >> "$temp_io_file"
                fi
                
                # 打开文件数
                if [ -d "/proc/$single_pid/fd" ]; then
                    fd_count=$(ls /proc/$single_pid/fd/ 2>/dev/null | wc -l)
                    [ "$fd_count" -gt 0 ] && echo "  open_fds=$fd_count" >> "$temp_io_file"
                    process_io_collected=true
                fi
                
                echo "" >> "$temp_io_file"
            else
                echo "=== Process PID=$single_pid does not exist ===" >> "$temp_io_file"
                echo "" >> "$temp_io_file"
            fi
        done
    fi
    
    # === 系统级IO限制 ===
    echo "=== System-wide I/O Limits ===" >> "$temp_io_file"
    local system_limits_collected=false
    
    echo "--- AIO Limits ---" >> "$temp_io_file"
    if [ -r "/proc/sys/fs/aio-max-nr" ]; then
        echo "aio-max-nr: $(cat /proc/sys/fs/aio-max-nr 2>/dev/null)" >> "$temp_io_file"
        system_limits_collected=true
    else
        echo "aio-max-nr: N/A (不可访问)" >> "$temp_io_file"
    fi
    
    if [ -r "/proc/sys/fs/aio-nr" ]; then
        echo "aio-nr: $(cat /proc/sys/fs/aio-nr 2>/dev/null)" >> "$temp_io_file"
        system_limits_collected=true
    else
        echo "aio-nr: N/A (不可访问)" >> "$temp_io_file"
    fi
    
    # AIO使用率检查
    if [ -r /proc/sys/fs/aio-max-nr ] && [ -r /proc/sys/fs/aio-nr ]; then
        max=$(cat /proc/sys/fs/aio-max-nr 2>/dev/null)
        cur=$(cat /proc/sys/fs/aio-nr 2>/dev/null)
        if [ -n "$max" ] && [ -n "$cur" ] && [ "$max" -gt 0 ]; then
            pct=$((cur * 100 / max))
            [ "$pct" -gt 80 ] && echo "  WARNING: AIO usage at ${pct}%" >> "$temp_io_file"
            system_limits_collected=true
        fi
    fi
    
    echo "--- File Handle Limits ---" >> "$temp_io_file"
    if [ -r "/proc/sys/fs/file-max" ]; then
        echo "file-max: $(cat /proc/sys/fs/file-max 2>/dev/null)" >> "$temp_io_file"
        system_limits_collected=true
    fi
    
    if [ -r "/proc/sys/fs/file-nr" ]; then
        awk '{printf "file-nr:  allocated=%s  free=%s  max=%s\n", $1, $2, $3}' /proc/sys/fs/file-nr 2>/dev/null >> "$temp_io_file"
        system_limits_collected=true
    fi
    
    if [ -r "/proc/sys/fs/nr_open" ]; then
        echo "nr_open: $(cat /proc/sys/fs/nr_open 2>/dev/null)" >> "$temp_io_file"
        system_limits_collected=true
    fi
    echo "" >> "$temp_io_file"
    
    # === 开始实时数据采集 ===
    echo "=== I/O Performance Data Collection (${DURATION} seconds) ===" >> "$temp_io_file"
    
    # 临时文件
    VMSTAT_TMP="/tmp/vmstat_io_$$.txt"
    IOSTAT_TMP="/tmp/iostat_io_$$.txt"
    local realtime_collected=false
    
    # 后台采集 vmstat
    local vmstat_success=false
    if command -v vmstat &> /dev/null; then
        vmstat 1 $DURATION > "$VMSTAT_TMP" 2>&1 &
        VMSTAT_PID=$!
        vmstat_success=true
    else
        echo "⚠ vmstat command not found" >> "$temp_io_file"
    fi
    
    # 后台采集 iostat
    local iostat_success=false
    if command -v iostat &> /dev/null; then
        iostat -x 1 $DURATION > "$IOSTAT_TMP" 2>&1 &
        IOSTAT_PID=$!
        iostat_success=true
    else
        echo "⚠ iostat command not found (install sysstat package)" >> "$temp_io_file"
    fi
    
    # 等待采集完成
    if [ "$vmstat_success" = true ]; then
        wait $VMSTAT_PID 2>/dev/null
        if [ -s "$VMSTAT_TMP" ]; then
            echo "--- VMStat Analysis ---" >> "$temp_io_file"
            awk 'NR<=2 || /^[[:space:]]*[0-9]/' "$VMSTAT_TMP" | head -15 >> "$temp_io_file"
            echo "" >> "$temp_io_file"
            realtime_collected=true
            io_metrics_success=true
        else
            echo "⚠ VMStat data collection failed" >> "$temp_io_file"
        fi
    fi
    
    if [ "$iostat_success" = true ]; then
        wait $IOSTAT_PID 2>/dev/null
        if [ -s "$IOSTAT_TMP" ]; then
            echo "--- Disk Utilization Summary ---" >> "$temp_io_file"
            awk '$1 ~ /^[a-z]/ && $NF+0 > 0 {
                printf "%-10s util=%s%%  r/s=%s  w/s=%s  rKB/s=%s  wKB/s=%s  await=%s\n", $1, $NF, $2, $9, $3, $10, $5
            }' "$IOSTAT_TMP" | head -20 >> "$temp_io_file"
            echo "" >> "$temp_io_file"
            
            echo "--- I/O Pattern Analysis (Sequential vs Random) ---" >> "$temp_io_file"
            awk '$1 ~ /^[a-z]/ && (($4+0)>0 || ($5+0)>0) {
                ratio = ($4+$5)/($4+$5+$6+$7+0.1)*100
                printf "  %s: merge=%.1f%%  avg_req=%d sect  pattern=", $1, ratio, $8
                if (ratio > 30 && $8 > 32) print "SEQUENTIAL"
                else if (ratio < 10 && $8 < 16) print "RANDOM"
                else print "MIXED"
            }' "$IOSTAT_TMP" | head -10 >> "$temp_io_file"
            echo "" >> "$temp_io_file"
            realtime_collected=true
            io_metrics_success=true
        else
            echo "⚠ iostat data collection failed" >> "$temp_io_file"
        fi
    fi
    
    if [ "$realtime_collected" = false ]; then
        echo "⚠ No real-time I/O data collected (vmstat/iostat failed)" >> "$temp_io_file"
    fi
    
    # === 挂载选项 ===
    echo "=== Filesystem Mount Options ===" >> "$temp_io_file"
    if mount 2>/dev/null | grep -E '^/dev| type ext[234]| type xfs| type btrfs' | head -10 >> "$temp_io_file"; then
        io_metrics_success=true
    else
        echo "⚠ No filesystem mount information available" >> "$temp_io_file"
    fi
    echo "" >> "$temp_io_file"
    
    # === NFS挂载 ===
    echo "=== NFS/CIFS Mount Options ===" >> "$temp_io_file"
    nfs_mounts=$(mount 2>/dev/null | grep -E 'type nfs|type cifs' | head -10)
    if [ -n "$nfs_mounts" ]; then
        echo "$nfs_mounts" >> "$temp_io_file"
        io_metrics_success=true
    else
        echo "No NFS/CIFS mounts found" >> "$temp_io_file"
    fi
    echo "" >> "$temp_io_file"
    
    # === 清理临时文件 ===
    rm -f "$VMSTAT_TMP" "$IOSTAT_TMP"
    
    echo "============================================================" >> "$temp_io_file"
    echo "I/O Metrics Analysis Complete" >> "$temp_io_file"
    echo "============================================================" >> "$temp_io_file"
    
    # 只有在至少有一个关键采集成功时才生成最终文件
    if [ "$io_metrics_success" = true ]; then
        mv "$temp_io_file" "$IO_METRICS_FILE"
        log_success "√ I/O Metrics 深度分析完成，结果保存至: $IO_METRICS_FILE"
    else
        # 没有成功的采集，删除临时文件
        rm -f "$temp_io_file"
        log_warning "I/O Metrics 深度分析全部失败，未生成 $IO_METRICS_FILE"
    fi
}

# =============================================================================
# Lock Trace 采集函数（整合自 collect_lock_trace.sh）
# =============================================================================
collect_lock_trace() {
    log_info "执行：Lock Trace 深度分析"
    
    # 标记是否有任何成功的采集
    lock_trace_success=false
    
    # 创建临时文件
    temp_lock_file="${LOCK_TRACE_FILE}.tmp"
    
    # 开始写入临时文件
    echo "============================================================" > "$temp_lock_file"
    echo "Phase: Lock Trace Analysis for Bottleneck Identification" >> "$temp_lock_file"
    echo "============================================================" >> "$temp_lock_file"
    echo "采集时间: $(date)" >> "$temp_lock_file"
    echo "持续时间: ${DURATION}秒" >> "$temp_lock_file"
    if [[ -n "$PIDS" ]]; then
        echo "目标进程: $PIDS" >> "$temp_lock_file"
    fi
    echo "" >> "$temp_lock_file"
    
    # === Lock tracing 前置条件检查 ===
    echo "=== Lock Tracing Prerequisites ===" >> "$temp_lock_file"
    local prereq_success=false
    for setting in perf_event_paranoid lock_stat sched_schedstats; do
        if [ -r "/proc/sys/kernel/$setting" ]; then
            echo "$setting: $(cat /proc/sys/kernel/$setting 2>/dev/null || echo 'N/A')" >> "$temp_lock_file"
            prereq_success=true
        else
            echo "$setting: N/A (不可访问)" >> "$temp_lock_file"
        fi
    done
    if [ "$prereq_success" = true ]; then
        lock_trace_success=true
    fi
    echo "" >> "$temp_lock_file"
    
    # === 系统锁配置 ===
    echo "=== System Lock Configuration ===" >> "$temp_lock_file"
    local sysconfig_success=false
    for setting in futex_wake_mac futex_ping_latency sched_autogroup_enabled sched_child_runs_first \
                    sched_latency_ns sched_min_granularity_ns sched_wakeup_granularity_ns sched_tunable_scaling; do
        if [ -r "/proc/sys/kernel/$setting" ]; then
            echo "$setting: $(cat /proc/sys/kernel/$setting 2>/dev/null || echo 'N/A')" >> "$temp_lock_file"
            sysconfig_success=true
        fi
    done
    if [ "$sysconfig_success" = true ]; then
        lock_trace_success=true
    fi
    echo "" >> "$temp_lock_file"
    
    # === RCU 配置 ===
    echo "=== RCU Configuration ===" >> "$temp_lock_file"
    local rcu_success=false
    for setting in rcu_cpu_stall_suppress rcu_normal; do
        if [ -r "/proc/sys/kernel/$setting" ]; then
            echo "$setting: $(cat /proc/sys/kernel/$setting 2>/dev/null || echo 'N/A')" >> "$temp_lock_file"
            rcu_success=true
        fi
    done
    if [ "$rcu_success" = true ]; then
        lock_trace_success=true
    fi
    echo "" >> "$temp_lock_file"
    
    # === Lockup 检测 ===
    echo "=== Lockup Detection ===" >> "$temp_lock_file"
    local lockup_success=false
    for setting in softlockup_panic nmi_watchdog; do
        if [ -r "/proc/sys/kernel/$setting" ]; then
            echo "$setting: $(cat /proc/sys/kernel/$setting 2>/dev/null || echo 'N/A')" >> "$temp_lock_file"
            lockup_success=true
        fi
    done
    if [ "$lockup_success" = true ]; then
        lock_trace_success=true
    fi
    echo "" >> "$temp_lock_file"
    
    # === CPU 隔离 ===
    echo "=== CPU Isolation ===" >> "$temp_lock_file"
    if [ -r "/proc/cmdline" ]; then
        cmdline=$(cat /proc/cmdline 2>/dev/null)
        isolcpus=$(echo "$cmdline" | grep -o 'isolcpus=[^ ]*' || echo 'N/A')
        nohz_full=$(echo "$cmdline" | grep -o 'nohz_full=[^ ]*' || echo 'N/A')
        echo "isolcpus: $isolcpus" >> "$temp_lock_file"
        echo "nohz_full: $nohz_full" >> "$temp_lock_file"
        if [ "$isolcpus" != "N/A" ] || [ "$nohz_full" != "N/A" ]; then
            lock_trace_success=true
        fi
    else
        echo "isolcpus: N/A (无法读取 /proc/cmdline)" >> "$temp_lock_file"
        echo "nohz_full: N/A" >> "$temp_lock_file"
    fi
    echo "" >> "$temp_lock_file"
    
    # === 内核锁统计 ===
    echo "=== Kernel Lock Statistics ===" >> "$temp_lock_file"
    if [ -r "/proc/lock_stat" ] && [ -s "/proc/lock_stat" ]; then
        head -50 /proc/lock_stat >> "$temp_lock_file"
        lock_trace_success=true
    else
        echo "lock_stat: not available (enable via: echo 1 > /proc/sys/kernel/lock_stat)" >> "$temp_lock_file"
        echo "" >> "$temp_lock_file"
        echo "Note: To enable lock statistics, run as root:" >> "$temp_lock_file"
        echo "  echo 1 > /proc/sys/kernel/lock_stat" >> "$temp_lock_file"
    fi
    echo "" >> "$temp_lock_file"
    
    # === 文件锁 ===
    echo "=== File Locks ===" >> "$temp_lock_file"
    if [ -r "/proc/locks" ] && [ -s "/proc/locks" ]; then
        head -50 /proc/locks >> "$temp_lock_file"
        lock_trace_success=true
    else
        echo "locks: not available or empty" >> "$temp_lock_file"
    fi
    echo "" >> "$temp_lock_file"
    
    # === Softirq 活动 ===
    echo "=== Softirq Activity ===" >> "$temp_lock_file"
    if [ -r "/proc/softirqs" ] && [ -s "/proc/softirqs" ]; then
        head -50 /proc/softirqs >> "$temp_lock_file"
        lock_trace_success=true
    else
        echo "softirqs: not available" >> "$temp_lock_file"
    fi
    echo "" >> "$temp_lock_file"
    
    # === 目标进程信息（如果指定了PID）===
    local process_info_success=false
    if [[ -n "$PIDS" ]]; then
        IFS=',' read -ra pid_array <<< "$PIDS"
        for single_pid in "${pid_array[@]}"; do
            single_pid=$(echo "$single_pid" | xargs)
            if [ -d "/proc/$single_pid" ]; then
                echo "=== Target Process Info (PID: $single_pid) ===" >> "$temp_lock_file"
                
                echo "--- Thread Information ---" >> "$temp_lock_file"
                if ps -T -p $single_pid >> "$temp_lock_file" 2>&1; then
                    process_info_success=true
                else
                    echo "Process not found" >> "$temp_lock_file"
                fi
                
                echo "" >> "$temp_lock_file"
                echo "--- Process Status ---" >> "$temp_lock_file"
                if grep -E "State|Threads|VmRSS" "/proc/$single_pid/status" >> "$temp_lock_file" 2>/dev/null; then
                    process_info_success=true
                else
                    echo "Cannot read process status" >> "$temp_lock_file"
                fi
                
                echo "" >> "$temp_lock_file"
                echo "--- Wait Channel (wchan) ---" >> "$temp_lock_file"
                if [ -r "/proc/$single_pid/wchan" ]; then
                    echo "wchan: $(cat /proc/$single_pid/wchan 2>/dev/null || echo 'N/A')" >> "$temp_lock_file"
                    process_info_success=true
                fi
                
                echo "" >> "$temp_lock_file"
                echo "--- Kernel Stack (first 20 lines) ---" >> "$temp_lock_file"
                if [ -r "/proc/$single_pid/stack" ]; then
                    head -20 /proc/$single_pid/stack >> "$temp_lock_file" 2>/dev/null
                    process_info_success=true
                else
                    echo "Cannot read stack (need root)" >> "$temp_lock_file"
                fi
                
                echo "" >> "$temp_lock_file"
            else
                echo "=== Process PID=$single_pid does not exist ===" >> "$temp_lock_file"
                echo "" >> "$temp_lock_file"
            fi
        done
    fi
    if [ "$process_info_success" = true ]; then
        lock_trace_success=true
    fi
    
    # === 实时锁竞争检测（使用perf）===
    echo "=== Real-time Lock Contention Detection ===" >> "$temp_lock_file"
    local perf_lock_success=false
    
    if command -v perf &> /dev/null && [[ -n "$PIDS" ]]; then
        echo "--- Perf lock analysis (${DURATION} seconds) ---" >> "$temp_lock_file"
        
        # 检查perf lock子命令是否可用
        if perf lock -h &> /dev/null; then
            IFS=',' read -ra pid_array <<< "$PIDS"
            for single_pid in "${pid_array[@]}"; do
                single_pid=$(echo "$single_pid" | xargs)
                
                echo "Analyzing locks for PID $single_pid..." >> "$temp_lock_file"
                
                # 记录锁事件
                PERF_LOCK_TMP="/tmp/perf_lock_${single_pid}_$$.data"
                if timeout $DURATION perf lock record -p $single_pid -o "$PERF_LOCK_TMP" -- sleep $DURATION 2>&1 | head -20 >> "$temp_lock_file"; then
                    # 报告锁统计
                    if [ -f "$PERF_LOCK_TMP" ] && [ -s "$PERF_LOCK_TMP" ]; then
                        echo "" >> "$temp_lock_file"
                        echo "--- Lock Contention Report ---" >> "$temp_lock_file"
                        if perf lock report -i "$PERF_LOCK_TMP" --stdio 2>&1 | head -50 >> "$temp_lock_file"; then
                            perf_lock_success=true
                        fi
                        rm -f "$PERF_LOCK_TMP"
                    fi
                else
                    echo "perf lock record failed for PID $single_pid" >> "$temp_lock_file"
                fi
            done
        else
            echo "perf lock subcommand not available (need perf built with libtraceevent)" >> "$temp_lock_file"
        fi
    else
        echo "perf lock analysis skipped (perf not available or no PID specified)" >> "$temp_lock_file"
    fi
    if [ "$perf_lock_success" = true ]; then
        lock_trace_success=true
    fi
    echo "" >> "$temp_lock_file"
    
    # === 阻塞进程分析 ===
    echo "=== Blocked Processes Analysis ===" >> "$temp_lock_file"
    local blocked_success=false
    
    echo "--- Blocked Processes (D=uninterruptible, S=interruptible) ---" >> "$temp_lock_file"
    if ps -eo state,wchan:32,pid,comm 2>/dev/null | awk '/^[DS]/ {print}' | sort | uniq -c | sort -rn | head -20 >> "$temp_lock_file"; then
        blocked_success=true
    else
        echo "无法获取阻塞进程信息" >> "$temp_lock_file"
    fi
    echo "" >> "$temp_lock_file"
    
    echo "--- Wait Channel Breakdown ---" >> "$temp_lock_file"
    if ps -eo state,wchan:32 2>/dev/null | awk '/^[DS]/ {print $2}' | sort | uniq -c | sort -rn | head -20 >> "$temp_lock_file"; then
        blocked_success=true
    fi
    echo "" >> "$temp_lock_file"
    
    if [ "$blocked_success" = true ]; then
        lock_trace_success=true
    fi
    
    # === 锁持有时间分析（如果启用lock_stat）===
    if [ -r "/proc/lock_stat" ] && [ -s "/proc/lock_stat" ]; then
        echo "=== Lock Hold Time Analysis ===" >> "$temp_lock_file"
        echo "Top 10 locks by contention (hold time):" >> "$temp_lock_file"
        if awk '/->/ && /lock/ {print $1, $2, $3, $4, $5}' /proc/lock_stat 2>/dev/null | sort -k5 -rn | head -10 >> "$temp_lock_file"; then
            lock_trace_success=true
        fi
        echo "" >> "$temp_lock_file"
    fi
    
    # === Futex 竞争检测 ===
    echo "=== Futex Contention Detection ===" >> "$temp_lock_file"
    local futex_success=false
    
    if [[ -n "$PIDS" ]] && command -v strace &> /dev/null; then
        IFS=',' read -ra pid_array <<< "$PIDS"
        for single_pid in "${pid_array[@]}"; do
            single_pid=$(echo "$single_pid" | xargs)
            echo "Checking futex syscall for PID $single_pid (5s sample)..." >> "$temp_lock_file"
            if timeout ${DURATION} strace -p $single_pid -c -e trace=futex 2>&1 | grep -E "futex|% time" >> "$temp_lock_file"; then
                futex_success=true
            fi
            echo "" >> "$temp_lock_file"
        done
    else
        echo "Futex detection skipped (strace not available or no PID specified)" >> "$temp_lock_file"
    fi
    echo "" >> "$temp_lock_file"
    
    if [ "$futex_success" = true ]; then
        lock_trace_success=true
    fi
    
    # === 自旋锁统计（需要root且特定架构）===
    echo "=== Spinlock Statistics ===" >> "$temp_lock_file"
    if [ -r "/proc/lock_stat" ] && [ -s "/proc/lock_stat" ]; then
        echo "lock_stat is enabled. Current spinlock contention:" >> "$temp_lock_file"
        if grep "spinlock" /proc/lock_stat 2>/dev/null | head -20 >> "$temp_lock_file"; then
            lock_trace_success=true
        fi
    else
        echo "spinlock statistics not available (lock_stat not enabled)" >> "$temp_lock_file"
        echo "To enable: echo 1 > /proc/sys/kernel/lock_stat (requires root)" >> "$temp_lock_file"
    fi
    echo "" >> "$temp_lock_file"
    
    # === 建议和优化提示 ===
    echo "=== Recommendations and Optimization Hints ===" >> "$temp_lock_file"
    
    # 检查是否有大量阻塞进程
    blocked_count=$(ps -eo state 2>/dev/null | grep -c '^[DS]' || echo "0")
    if [ "$blocked_count" -gt 10 ] 2>/dev/null; then
        echo "⚠ WARNING: $blocked_count blocked processes detected. High lock contention possible." >> "$temp_lock_file"
        lock_trace_success=true
    fi
    
    # 检查lock_stat是否启用
    if [ ! -f /proc/lock_stat ] || [ ! -s /proc/lock_stat ]; then
        echo "💡 TIP: Enable kernel lock statistics for detailed analysis:" >> "$temp_lock_file"
        echo "   echo 1 > /proc/sys/kernel/lock_stat" >> "$temp_lock_file"
    fi
    
    # 检查perf lock功能
    if command -v perf &> /dev/null; then
        if ! perf lock -h &> /dev/null; then
            echo "💡 TIP: Rebuild perf with libtraceevent support for lock analysis" >> "$temp_lock_file"
        fi
    fi
    
    echo "" >> "$temp_lock_file"
    echo "============================================================" >> "$temp_lock_file"
    echo "Lock Trace Analysis Complete" >> "$temp_lock_file"
    echo "============================================================" >> "$temp_lock_file"
    
    # 只有在至少有一个关键采集成功时才生成最终文件
    if [ "$lock_trace_success" = true ]; then
        mv "$temp_lock_file" "$LOCK_TRACE_FILE"
        log_success "√ Lock Trace 深度分析完成，结果保存至: $LOCK_TRACE_FILE"
    else
        # 没有成功的采集，删除临时文件
        rm -f "$temp_lock_file"
        log_warning "Lock Trace 深度分析全部失败，未生成 $LOCK_TRACE_FILE"
    fi
}

# =============================================================================
# Memory Metrics 采集函数（整合自 collect_mem_metrics.sh）
# =============================================================================
collect_mem_metrics() {
    log_info "执行：Memory Metrics 深度分析"
    
    # 标记是否有任何成功的采集
    mem_metrics_success=false
    
    # 创建临时文件
    temp_mem_file="${MEM_METRICS_FILE}.tmp"
    
    # 开始写入临时文件
    echo "============================================================" > "$temp_mem_file"
    echo "Phase: Memory Metrics for Bottleneck Analysis" >> "$temp_mem_file"
    echo "============================================================" >> "$temp_mem_file"
    echo "采集时间: $(date)" >> "$temp_mem_file"
    if [[ -n "$PIDS" ]]; then
        echo "目标进程: $PIDS" >> "$temp_mem_file"
    fi
    echo "" >> "$temp_mem_file"
    
    # === 系统概览（总是成功）===
    echo "=== System Overview ===" >> "$temp_mem_file"
    echo "Kernel: $(uname -r)" >> "$temp_mem_file"
    echo "CPU Count: $(nproc)" >> "$temp_mem_file"
    echo "Memory Total: $(free -h | awk '/^Mem:/{print $2}')" >> "$temp_mem_file"
    echo "" >> "$temp_mem_file"
    mem_metrics_success=true  # 系统概览算作基础成功
    
    # === 内存压力信息 (PSI) ===
    echo "=== Memory Pressure (PSI) ===" >> "$temp_mem_file"
    if [ -f /proc/pressure/mem ] && [ -r /proc/pressure/mem ]; then
        cat /proc/pressure/mem >> "$temp_mem_file" 2>/dev/null && mem_metrics_success=true
    else
        echo "/proc/pressure/mem not available." >> "$temp_mem_file"
        echo "To enable: Add psi=1 to kernel boot params in /etc/default/grub," >> "$temp_mem_file"
        echo "           then run: grub2-mkconfig -o /boot/grub2/grub.cfg && reboot" >> "$temp_mem_file"
    fi
    echo "" >> "$temp_mem_file"
    
    # === 内存使用概况 ===
    echo "=== Memory Usage ===" >> "$temp_mem_file"
    if free -h >> "$temp_mem_file" 2>/dev/null; then
        mem_metrics_success=true
    fi
    echo "" >> "$temp_mem_file"
    
    # === VM OOM 统计 ===
    echo "=== VM OOM Stats ===" >> "$temp_mem_file"
    if [ -r /proc/vmstat ]; then
        oom_stats=$(cat /proc/vmstat 2>/dev/null | grep -E 'oom_kill|pgmajfault')
        if [ -n "$oom_stats" ]; then
            echo "$oom_stats" >> "$temp_mem_file"
            mem_metrics_success=true
        else
            echo "No OOM kills or major page faults recorded" >> "$temp_mem_file"
        fi
    else
        echo "Cannot read /proc/vmstat" >> "$temp_mem_file"
    fi
    echo "" >> "$temp_mem_file"
    
    # === Swap 配置 ===
    echo "=== Swap Configuration ===" >> "$temp_mem_file"
    if swapon -s >> "$temp_mem_file" 2>/dev/null || cat /proc/swaps >> "$temp_mem_file" 2>/dev/null; then
        mem_metrics_success=true
    else
        echo "No swap configured or cannot read swap info" >> "$temp_mem_file"
    fi
    echo "" >> "$temp_mem_file"
    
    # === Slab 信息 ===
    echo "=== Slab Info ===" >> "$temp_mem_file"
    if [ -r /proc/slabinfo ]; then
        head -30 /proc/slabinfo >> "$temp_mem_file" 2>/dev/null && mem_metrics_success=true
    else
        echo "/proc/slabinfo not readable (requires root)" >> "$temp_mem_file"
    fi
    echo "" >> "$temp_mem_file"
    
    # === Vmalloc 区域 ===
    echo "=== Vmalloc Region ===" >> "$temp_mem_file"
    if cat /proc/meminfo 2>/dev/null | grep -E "VmallocTotal|VmallocUsed" >> "$temp_mem_file"; then
        mem_metrics_success=true
    fi
    echo "" >> "$temp_mem_file"
    
    # === 内存分配/回收统计 ===
    echo "=== Memory Allocation/Reclaim Stats ===" >> "$temp_mem_file"
    if cat /proc/vmstat 2>/dev/null | grep -E "pgfault|pgmajflt|pgalloc|pgfree|pgscank|pgscand|pgsteal|pgrotated" | head -20 >> "$temp_mem_file"; then
        mem_metrics_success=true
    fi
    echo "" >> "$temp_mem_file"
    
    # === 内存详细信息 ===
    echo "=== Memory Details (meminfo) ===" >> "$temp_mem_file"
    if cat /proc/meminfo 2>/dev/null | grep -E "Active:|Inactive:|SReclaimable|SUnreclaim|Shmem:|VmallocUsed:|Committed_AS:" >> "$temp_mem_file"; then
        mem_metrics_success=true
    fi
    echo "" >> "$temp_mem_file"
    
    # === HugePages 配置 ===
    echo "=== HugePages Configuration ===" >> "$temp_mem_file"
    local hugepage_success=false
    if [ -r /proc/sys/vm/nr_hugepages ]; then
        echo "nr_hugepages: $(cat /proc/sys/vm/nr_hugepages 2>/dev/null)" >> "$temp_mem_file"
        hugepage_success=true
    fi
    if cat /proc/meminfo 2>/dev/null | grep -E "HugePages_Total|HugePages_Free|HugePages_Rsvd|Hugepagesize:" >> "$temp_mem_file"; then
        hugepage_success=true
    fi
    if [ -r /sys/kernel/mm/transparent_hugepage/enabled ]; then
        echo "transparent_hugepage: $(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)" >> "$temp_mem_file"
        hugepage_success=true
    fi
    if [ "$hugepage_success" = true ]; then
        mem_metrics_success=true
    fi
    echo "" >> "$temp_mem_file"
    
    # === OOM 配置 ===
    echo "=== OOM Configuration ===" >> "$temp_mem_file"
    local oom_config_success=false
    if [ -r /proc/sys/vm/oom_kill_allocating_task ]; then
        echo "oom_kill_allocating_task: $(cat /proc/sys/vm/oom_kill_allocating_task 2>/dev/null)" >> "$temp_mem_file"
        oom_config_success=true
    fi
    if [ -r /proc/sys/vm/oom_dump_tasks ]; then
        echo "oom_dump_tasks: $(cat /proc/sys/vm/oom_dump_tasks 2>/dev/null)" >> "$temp_mem_file"
        oom_config_success=true
    fi
    if [ "$oom_config_success" = true ]; then
        mem_metrics_success=true
    fi
    echo "" >> "$temp_mem_file"
    
    # === KSM 配置 ===
    echo "=== KSM Configuration ===" >> "$temp_mem_file"
    if [ -f /sys/kernel/mm/ksm/run ] && [ -r /sys/kernel/mm/ksm/run ]; then
        echo "ksm.run: $(cat /sys/kernel/mm/ksm/run 2>/dev/null)" >> "$temp_mem_file"
        echo "ksm.pages_shared: $(cat /sys/kernel/mm/ksm/pages_shared 2>/dev/null || echo 'N/A')" >> "$temp_mem_file"
        echo "ksm.pages_sharing: $(cat /sys/kernel/mm/ksm/pages_sharing 2>/dev/null || echo 'N/A')" >> "$temp_mem_file"
        mem_metrics_success=true
    else
        echo "KSM not available" >> "$temp_mem_file"
    fi
    echo "" >> "$temp_mem_file"
    
    # === NUMA 均衡配置 ===
    echo "=== NUMA Balancing ===" >> "$temp_mem_file"
    if [ -r /proc/sys/kernel/numa_balancing ]; then
        echo "numa_balancing: $(cat /proc/sys/kernel/numa_balancing 2>/dev/null)" >> "$temp_mem_file"
        mem_metrics_success=true
    else
        echo "numa_balancing: N/A" >> "$temp_mem_file"
    fi
    echo "" >> "$temp_mem_file"
    
    # === 内存 CGroup 限制 ===
    echo "=== Memory CGroup Limits ===" >> "$temp_mem_file"
    local cgroup_success=false
    if [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ] && [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
        echo "memory.limit_in_bytes: $(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)" >> "$temp_mem_file"
        echo "memory.soft_limit_in_bytes: $(cat /sys/fs/cgroup/memory/memory.soft_limit_in_bytes 2>/dev/null)" >> "$temp_mem_file"
        echo "memory.usage_in_bytes: $(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null)" >> "$temp_mem_file"
        cgroup_success=true
    elif [ -f /sys/fs/cgroup/memory.max ] && [ -r /sys/fs/cgroup/memory.max ]; then
        # cgroup v2
        echo "memory.max: $(cat /sys/fs/cgroup/memory.max 2>/dev/null)" >> "$temp_mem_file"
        echo "memory.current: $(cat /sys/fs/cgroup/memory.current 2>/dev/null)" >> "$temp_mem_file"
        echo "memory.low: $(cat /sys/fs/cgroup/memory.low 2>/dev/null)" >> "$temp_mem_file"
        cgroup_success=true
    else
        echo "Memory cgroup limits not available" >> "$temp_mem_file"
    fi
    if [ "$cgroup_success" = true ]; then
        mem_metrics_success=true
    fi
    echo "" >> "$temp_mem_file"
    
    # === 内存水位线 ===
    echo "=== Memory Watermarks ===" >> "$temp_mem_file"
    local watermark_success=false
    if [ -r /proc/sys/vm/watermark_scale_factor ]; then
        echo "watermark_scale_factor: $(cat /proc/sys/vm/watermark_scale_factor 2>/dev/null)" >> "$temp_mem_file"
        watermark_success=true
    fi
    if [ -r /proc/sys/vm/watermark_boost_factor ]; then
        echo "watermark_boost_factor: $(cat /proc/sys/vm/watermark_boost_factor 2>/dev/null)" >> "$temp_mem_file"
        watermark_success=true
    fi
    if [ "$watermark_success" = true ]; then
        mem_metrics_success=true
    fi
    echo "" >> "$temp_mem_file"
    
    # === 内存区域信息 ===
    echo "=== Memory Zone Info (per node) ===" >> "$temp_mem_file"
    if [ -r /proc/zoneinfo ]; then
        cat /proc/zoneinfo 2>/dev/null | grep -E "Node|zone" | head -30 >> "$temp_mem_file"
        mem_metrics_success=true
    fi
    echo "" >> "$temp_mem_file"
    
    # === jemalloc 配置检查 ===
    echo "=== jemalloc Configuration ===" >> "$temp_mem_file"
    local jemalloc_success=false
    
    # 检查目标进程是否链接jemalloc
    if [[ -n "$PIDS" ]]; then
        IFS=',' read -ra pid_array <<< "$PIDS"
        for single_pid in "${pid_array[@]}"; do
            single_pid=$(echo "$single_pid" | xargs)
            if [ -f "/proc/$single_pid/maps" ] && [ -r "/proc/$single_pid/maps" ]; then
                jemap=$(grep -i jemalloc /proc/$single_pid/maps 2>/dev/null | head -1)
                if [ -n "$jemap" ]; then
                    echo "jemalloc detected in target process (PID $single_pid):" >> "$temp_mem_file"
                    echo "$jemap" >> "$temp_mem_file"
                    jemalloc_success=true
                else
                    echo "Target process $single_pid does NOT use jemalloc" >> "$temp_mem_file"
                fi
            elif [ -n "$single_pid" ]; then
                echo "Target process /proc/$single_pid/maps not available" >> "$temp_mem_file"
            fi
        done
    else
        echo "No target PID provided; skipping process mapping check" >> "$temp_mem_file"
    fi
    
    # 显示jemalloc环境变量
    echo "" >> "$temp_mem_file"
    echo "--- jemalloc Environment Variables ---" >> "$temp_mem_file"
    echo "MALLOC_ARENA_MAX: ${MALLOC_ARENA_MAX:-not set}" >> "$temp_mem_file"
    echo "MALLOC_CONF: ${MALLOC_CONF:-not set}" >> "$temp_mem_file"
    
    # 解析MALLOC_CONF关键参数
    if [ -n "$MALLOC_CONF" ]; then
        echo "" >> "$temp_mem_file"
        echo "--- MALLOC_CONF breakdown ---" >> "$temp_mem_file"
        for key in background_thread dirty_decay_ms muzzy_decay_ms narenas percpu_arena \
                   oversize_threshold metadata_thp lg_extent_max_active_fit \
                   tcache lg_tcache_max prof prof_active stats_print; do
            val=$(echo "$MALLOC_CONF" | grep -oP "${key}:\K[^,]+" 2>/dev/null)
            if [ -n "$val" ]; then
                echo "  $key=$val" >> "$temp_mem_file"
                jemalloc_success=true
            fi
        done
    fi
    if [ "$jemalloc_success" = true ]; then
        mem_metrics_success=true
    fi
    echo "" >> "$temp_mem_file"
    
    # === NUMA 统计（系统级） ===
    echo "=== NUMA Statistics (system-wide) ===" >> "$temp_mem_file"
    if [ -r /proc/vmstat ]; then
        if cat /proc/vmstat 2>/dev/null | grep -E "numa_hit|numa_miss|numa_foreign|numa_local|numa_other" | head -20 >> "$temp_mem_file"; then
            mem_metrics_success=true
        fi
    fi
    echo "" >> "$temp_mem_file"
    
    # === NUMA 统计（进程级） ===
    local numa_proc_success=false
    if [[ -n "$PIDS" ]]; then
        IFS=',' read -ra pid_array <<< "$PIDS"
        for single_pid in "${pid_array[@]}"; do
            single_pid=$(echo "$single_pid" | xargs)
            if [ -d "/proc/$single_pid" ]; then
                echo "=== Process NUMA Memory Distribution (PID: $single_pid) ===" >> "$temp_mem_file"
                if command -v numastat &> /dev/null; then
                    if numastat -p $single_pid >> "$temp_mem_file" 2>/dev/null; then
                        numa_proc_success=true
                    else
                        echo "numastat failed" >> "$temp_mem_file"
                    fi
                elif [ -f "/proc/$single_pid/numa_maps" ] && [ -r "/proc/$single_pid/numa_maps" ]; then
                    echo "numastat not available, see /proc/$single_pid/numa_maps for details" >> "$temp_mem_file"
                    numa_proc_success=true
                else
                    echo "numastat not available" >> "$temp_mem_file"
                fi
                
                # 检查内存节点 vs CPU节点亲和性
                if [ -f "/proc/$single_pid/numa_maps" ] && [ -r "/proc/$single_pid/numa_maps" ]; then
                    dom=$(awk '{
                        for(i=1;i<=NF;i++) if($i ~ "^N[0-9]+=") {
                            split($i,a,"="); sum[a[1]]+=a[2]
                        }
                    } END {
                        for(n in sum) if(sum[n] > max) {max=sum[n]; dom=n}
                        print dom
                    }' /proc/$single_pid/numa_maps 2>/dev/null)
                    cpu_node=$(awk '$1==pid {print $NF}' pid=$single_pid /proc/$single_pid/stat 2>/dev/null)
                    numa_of_cpu="unknown"
                    if [ -n "$cpu_node" ] && command -v lscpu &> /dev/null; then
                        numa_of_cpu=$(lscpu -p=cpu,node 2>/dev/null | awk -F, -v cpu="$cpu_node" '$1==cpu {print $2}')
                    fi
                    dom_num=$(echo "$dom" | sed 's/^N//')
                    echo "" >> "$temp_mem_file"
                    echo "  Memory dominant node: ${dom_num:-?}  |  CPU node: ${numa_of_cpu:-?}  |  CPU: ${cpu_node:-?}" >> "$temp_mem_file"
                    if [ -n "$dom_num" ] && [ "$numa_of_cpu" != "unknown" ] && [ "$dom_num" != "$numa_of_cpu" ]; then
                        echo "  WARNING: memory on node $dom_num but process on node $numa_of_cpu (remote access)" >> "$temp_mem_file"
                    fi
                    numa_proc_success=true
                fi
                echo "" >> "$temp_mem_file"
            fi
        done
    fi
    if [ "$numa_proc_success" = true ]; then
        mem_metrics_success=true
    fi
    
    # === NUMA 节点布局 ===
    echo "=== NUMA Node Layout ===" >> "$temp_mem_file"
    if command -v numactl &> /dev/null; then
        if numactl --hardware >> "$temp_mem_file" 2>/dev/null; then
            mem_metrics_success=true
        fi
        echo "" >> "$temp_mem_file"
        echo "=== NUMA Current Policy ===" >> "$temp_mem_file"
        if numactl --show >> "$temp_mem_file" 2>/dev/null; then
            mem_metrics_success=true
        fi
    else
        echo "numactl not available" >> "$temp_mem_file"
    fi
    echo "" >> "$temp_mem_file"
    
    # === NUMA 节点信息 ===
    echo "=== NUMA Nodes ===" >> "$temp_mem_file"
    if command -v lscpu &> /dev/null; then
        if lscpu 2>/dev/null | grep "NUMA" >> "$temp_mem_file"; then
            mem_metrics_success=true
        fi
    else
        echo "lscpu not available" >> "$temp_mem_file"
    fi
    echo "" >> "$temp_mem_file"
    
    # === 各NUMA节点内存占用 ===
    echo "=== Memory per NUMA Node ===" >> "$temp_mem_file"
    if [ -r /proc/buddyinfo ]; then
        cat /proc/buddyinfo >> "$temp_mem_file" 2>/dev/null && mem_metrics_success=true
    else
        echo "Cannot read /proc/buddyinfo" >> "$temp_mem_file"
    fi
    echo "" >> "$temp_mem_file"
    
    # === 最近的OOM事件 ===
    echo "=== Recent OOM Events ===" >> "$temp_mem_file"
    local oom_events_success=false
    if command -v dmesg &> /dev/null; then
        oom_events=$(dmesg -T 2>/dev/null | grep -iE 'out of memory|oom kill' | tail -10)
        if [ -n "$oom_events" ]; then
            echo "$oom_events" >> "$temp_mem_file"
            oom_events_success=true
        fi
    fi
    if [ "$oom_events_success" = false ] && command -v journalctl &> /dev/null; then
        oom_events=$(journalctl -k 2>/dev/null | grep -iE 'out of memory|oom kill' | tail -10)
        if [ -n "$oom_events" ]; then
            echo "$oom_events" >> "$temp_mem_file"
            oom_events_success=true
        fi
    fi
    if [ "$oom_events_success" = false ]; then
        echo "No recent OOM events found" >> "$temp_mem_file"
    else
        mem_metrics_success=true
    fi
    echo "" >> "$temp_mem_file"
    
    # === 优化建议 ===
    echo "=== Memory Optimization Recommendations ===" >> "$temp_mem_file"
    local recommendations_success=false
    
    # 检查swap使用
    if command -v free &> /dev/null; then
        swap_used=$(free 2>/dev/null | awk '/^Swap:/ {print $3}')
        swap_total=$(free 2>/dev/null | awk '/^Swap:/ {print $2}')
        if [ -n "$swap_used" ] && [ -n "$swap_total" ] && [ "$swap_total" -gt 0 ] 2>/dev/null; then
            swap_pct=$((swap_used * 100 / swap_total))
            if [ "$swap_pct" -gt 50 ]; then
                echo "⚠ WARNING: High swap usage ($swap_pct%). Consider increasing memory or reducing memory pressure." >> "$temp_mem_file"
                recommendations_success=true
            fi
        fi
    fi
    
    # 检查OOM kill
    if [ -r /proc/vmstat ]; then
        oom_kills=$(cat /proc/vmstat 2>/dev/null | grep oom_kill | awk '{print $2}')
        if [ -n "$oom_kills" ] && [ "$oom_kills" -gt 0 ] 2>/dev/null; then
            echo "⚠ WARNING: $oom_kills OOM kills detected. System is memory constrained." >> "$temp_mem_file"
            recommendations_success=true
        fi
    fi
    
    # 检查大页使用
    if [ -r /proc/meminfo ]; then
        hugepage_total=$(cat /proc/meminfo 2>/dev/null | grep HugePages_Total | awk '{print $2}')
        if [ -n "$hugepage_total" ] && [ "$hugepage_total" -gt 0 ] 2>/dev/null; then
            hugepage_free=$(cat /proc/meminfo 2>/dev/null | grep HugePages_Free | awk '{print $2}')
            hugepage_used=$((hugepage_total - hugepage_free))
            if [ "$hugepage_used" -eq 0 ] 2>/dev/null; then
                echo "💡 TIP: HugePages configured but not used. Check application support or adjust allocation." >> "$temp_mem_file"
                recommendations_success=true
            fi
        fi
    fi
    
    # 检查NUMA平衡
    if [ -r /proc/sys/kernel/numa_balancing ]; then
        numa_balancing=$(cat /proc/sys/kernel/numa_balancing 2>/dev/null)
        if [ "$numa_balancing" = "0" ]; then
            echo "ℹ INFO: NUMA balancing is disabled. For NUMA systems, consider enabling (echo 1 > /proc/sys/kernel/numa_balancing)" >> "$temp_mem_file"
            recommendations_success=true
        fi
    fi
    
    if [ "$recommendations_success" = true ]; then
        mem_metrics_success=true
    fi

    echo "" >> "$MEM_METRICS_FILE"
    echo "=== 完整 /proc/meminfo ===" >> "$MEM_METRICS_FILE"
    cat /proc/meminfo >> "$MEM_METRICS_FILE" 2>/dev/null || echo "无法读取 /proc/meminfo" >> "$MEM_METRICS_FILE"

    echo "" >> "$MEM_METRICS_FILE"
    echo "=== 完整 /proc/vmstat ===" >> "$MEM_METRICS_FILE"
    cat /proc/vmstat >> "$MEM_METRICS_FILE" 2>/dev/null || echo "无法读取 /proc/vmstat" >> "$MEM_METRICS_FILE"
    
    echo "" >> "$MEM_METRICS_FILE"
    echo "=== 系统内存页大小 ===" >> "$MEM_METRICS_FILE"
    if command -v getconf &>/dev/null; then
        getconf PAGE_SIZE >> "$MEM_METRICS_FILE" 2>/dev/null || echo "获取失败" >> "$MEM_METRICS_FILE"
    fi

    echo "" >> "$MEM_METRICS_FILE"
    echo "=== 大页目录详情 ===" >> "$MEM_METRICS_FILE"
    if [ -d /sys/kernel/mm/hugepages ]; then
        for d in /sys/kernel/mm/hugepages/hugepages-*; do
            [ -d "$d" ] && echo "$(basename "$d"): nr_hugepages=$(cat "$d/nr_hugepages" 2>/dev/null || echo "?"), free=$(cat "$d/free_hugepages" >> "$MEM_METRICS_FILE" 2>/dev/null || echo "?")" >> "$MEM_METRICS_FILE"
        done
    else
        echo "hugepages 目录不存在" >> "$MEM_METRICS_FILE"
    fi

    echo "" >> "$MEM_METRICS_FILE"
    echo "=== NUMA 节点内存详情 ===" >> "$MEM_METRICS_FILE"
    if [ -d /sys/devices/system/node ]; then
        for node in /sys/devices/system/node/node*; do
            [ -d "$node" ] || continue
            node_name=$(basename "$node")
            echo "--- $node_name ---" >> "$MEM_METRICS_FILE"
            [ -f "$node/meminfo" ] && grep -E "MemTotal|MemFree|Active|Inactive|Dirty|Writeback|FilePages|Mapped|AnonPages|Shmem|KernelStack|PageTables" "$node/meminfo" >> "$MEM_METRICS_FILE" 2>/dev/null || echo "meminfo 不可用" >> "$MEM_METRICS_FILE"
        done
    else
        echo "NUMA 节点信息不可用" >> "$MEM_METRICS_FILE"
    fi
    
    echo "" >> "$temp_mem_file"
    echo "============================================================" >> "$temp_mem_file"
    echo "Memory Metrics Analysis Complete" >> "$temp_mem_file"
    echo "============================================================" >> "$temp_mem_file"
    
    # 只有在至少有一个关键采集成功时才生成最终文件
    if [ "$mem_metrics_success" = true ]; then
        mv "$temp_mem_file" "$MEM_METRICS_FILE"
        log_success "√ Memory Metrics 深度分析完成，结果保存至: $MEM_METRICS_FILE"
    else
        # 没有成功的采集，删除临时文件
        rm -f "$temp_mem_file"
        log_warning "Memory Metrics 深度分析全部失败，未生成 $MEM_METRICS_FILE"
    fi
}

# =============================================================================
# Network Metrics 采集函数（整合自 collect_net_metrics.sh）
# =============================================================================
collect_net_metrics() {
    log_info "执行：Network Metrics 深度分析"
    
    # 标记是否有任何成功的采集
    net_metrics_success=false
    
    # 创建临时文件
    temp_net_file="${NET_METRICS_FILE}.tmp"
    
    # 开始写入临时文件
    echo "============================================================" > "$temp_net_file"
    echo "Phase: Network Metrics for Bottleneck Analysis" >> "$temp_net_file"
    echo "============================================================" >> "$temp_net_file"
    echo "采集时间: $(date)" >> "$temp_net_file"
    echo "持续时间: ${DURATION}秒" >> "$temp_net_file"
    echo "" >> "$temp_net_file"
    
    # === 网络接口列表 ===
    echo "=== Network Interfaces ===" >> "$temp_net_file"
    if ip -br link show >> "$temp_net_file" 2>/dev/null; then
        net_metrics_success=true
    else
        echo "Cannot get network interface list" >> "$temp_net_file"
    fi
    echo "" >> "$temp_net_file"
    
    # === 网络 sysctl 配置 ===
    echo "=== Network Sysctl Configuration ===" >> "$temp_net_file"
    local sysctl_success=false
    for key in tcp_tw_reuse tcp_timestamps tcp_sack tcp_window_scaling tcp_congestion_control \
               tcp_rmem tcp_wmem tcp_mem tcp_max_syn_backlog tcp_fin_timeout ip_local_port_range \
               netdev_max_backlog netdev_budget somaxconn rmem_default rmem_max wmem_default wmem_max; do
        if [ -r "/proc/sys/net/ipv4/${key}" ] 2>/dev/null; then
            echo "${key}: $(cat /proc/sys/net/ipv4/${key} 2>/dev/null)" >> "$temp_net_file"
            sysctl_success=true
        elif [ -r "/proc/sys/net/core/${key}" ] 2>/dev/null; then
            echo "${key}: $(cat /proc/sys/net/core/${key} 2>/dev/null)" >> "$temp_net_file"
            sysctl_success=true
        else
            # 某些key可能在其他路径或不存在
            if [[ "$key" == "tcp_congestion_control" ]]; then
                if [ -r "/proc/sys/net/ipv4/tcp_congestion_control" ]; then
                    echo "${key}: $(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)" >> "$temp_net_file"
                    sysctl_success=true
                fi
            else
                echo "${key}: N/A" >> "$temp_net_file"
            fi
        fi
    done
    if [ "$sysctl_success" = true ]; then
        net_metrics_success=true
    fi
    echo "" >> "$temp_net_file"
    
    # === 网卡配置详情（仅显示UP状态的接口） ===
    echo "=== NIC Configuration ===" >> "$temp_net_file"
    local nic_config_success=false
    ACTIVE_IFACES=$(ip -br link show 2>/dev/null | awk '$2=="UP" {print $1}' | grep -v lo | head -5)
    
    if [ -z "$ACTIVE_IFACES" ]; then
        echo "No active network interfaces found (excluding lo)" >> "$temp_net_file"
    else
        for iface in $ACTIVE_IFACES; do
            echo "--- $iface ---" >> "$temp_net_file"
            
            # 链接状态和速度
            if command -v ethtool &> /dev/null; then
                echo "Link Info:" >> "$temp_net_file"
                if ethtool $iface 2>/dev/null | grep -E "Speed|Duplex|Link detected|Auto-negotiation" | sed 's/^\t*//' >> "$temp_net_file"; then
                    nic_config_success=true
                fi
                
                echo "" >> "$temp_net_file"
                echo "Driver Info:" >> "$temp_net_file"
                if ethtool -i $iface 2>/dev/null | grep -E "driver|version|firmware|bus-info" | sed 's/^[^:]*: //' | paste -sd, - >> "$temp_net_file"; then
                    nic_config_success=true
                fi
                
                echo "" >> "$temp_net_file"
                echo "[Queue/Channel Configuration]" >> "$temp_net_file"
                if ethtool -l $iface 2>/dev/null >> "$temp_net_file"; then
                    nic_config_success=true
                fi
                
                echo "" >> "$temp_net_file"
                echo "[Ring Buffer]" >> "$temp_net_file"
                if ethtool -g $iface 2>/dev/null >> "$temp_net_file"; then
                    nic_config_success=true
                fi
                
                echo "" >> "$temp_net_file"
                echo "[Coalesce Settings]" >> "$temp_net_file"
                if ethtool -c $iface 2>/dev/null >> "$temp_net_file"; then
                    nic_config_success=true
                fi
                
                echo "" >> "$temp_net_file"
                echo "[Pause Frame]" >> "$temp_net_file"
                if ethtool -a $iface 2>/dev/null >> "$temp_net_file"; then
                    nic_config_success=true
                fi
                
                echo "" >> "$temp_net_file"
                echo "[Offload Features]" >> "$temp_net_file"
                if ethtool -k $iface 2>/dev/null | head -30 >> "$temp_net_file"; then
                    nic_config_success=true
                fi
                
                # IRQ亲和性
                BUS_INFO=$(ethtool -i $iface 2>/dev/null | grep 'bus-info' | awk '{print $2}')
                if [ -n "$BUS_INFO" ]; then
                    echo "" >> "$temp_net_file"
                    echo "--- IRQ Affinity ---" >> "$temp_net_file"
                    if grep "$BUS_INFO" /proc/interrupts 2>/dev/null | while read -r line; do
                        IRQ=$(echo "$line" | awk '{print $1}' | tr -d ':')
                        AFFINITY=$(cat /proc/irq/$IRQ/smp_affinity 2>/dev/null || echo 'N/A')
                        DESC=$(echo "$line" | awk '{for(i=2;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')
                        echo "IRQ $IRQ: $AFFINITY  ($DESC)" >> "$temp_net_file"
                    done; then
                        nic_config_success=true
                    fi
                fi
            else
                echo "ethtool not available for detailed NIC info" >> "$temp_net_file"
            fi
            echo "" >> "$temp_net_file"
        done
    fi
    if [ "$nic_config_success" = true ]; then
        net_metrics_success=true
    fi
    
    # === 网络性能数据采集（sar） ===
    echo "=== Network Performance Data Collection (${DURATION} seconds) ===" >> "$temp_net_file"
    
    # 获取活跃接口（用于sar过滤）
    ACTIVE_IFACES=$(ip -br link show 2>/dev/null | awk '$2=="UP" && $1!="lo" {print $1}' | head -5 | paste -sd,)
    
    SAR_DEV_TMP="/tmp/sar_dev_$$.txt"
    SAR_EDEV_TMP="/tmp/sar_edeve_$$.txt"
    local sar_success=false
    
    if command -v sar &> /dev/null; then
        # 采集网络设备统计
        if [ -n "$ACTIVE_IFACES" ]; then
            sar -n DEV $INTERVAL $DURATION --iface="$ACTIVE_IFACES" > "$SAR_DEV_TMP" 2>&1 &
            SAR_DEV_PID=$!
            
            # 采集网络错误统计
            sar -n EDEV $INTERVAL $DURATION --iface="$ACTIVE_IFACES" > "$SAR_EDEV_TMP" 2>&1 &
            SAR_EDEV_PID=$!
            
            # 等待采集完成
            wait $SAR_DEV_PID $SAR_EDEV_PID 2>/dev/null
            
            echo "--- Network Device Stats (sar -n DEV) ---" >> "$temp_net_file"
            if [ -f "$SAR_DEV_TMP" ] && [ -s "$SAR_DEV_TMP" ]; then
                tail -n +4 "$SAR_DEV_TMP" >> "$temp_net_file"
                sar_success=true
            else
                echo "No data collected" >> "$temp_net_file"
            fi
            echo "" >> "$temp_net_file"
            
            echo "--- Network Error Stats (sar -n EDEV) ---" >> "$temp_net_file"
            if [ -f "$SAR_EDEV_TMP" ] && [ -s "$SAR_EDEV_TMP" ]; then
                tail -n +4 "$SAR_EDEV_TMP" >> "$temp_net_file"
                sar_success=true
            else
                echo "No data collected" >> "$temp_net_file"
            fi
            echo "" >> "$temp_net_file"
            
            # 清理临时文件
            rm -f "$SAR_DEV_TMP" "$SAR_EDEV_TMP"
        else
            echo "No active network interfaces for sar monitoring" >> "$temp_net_file"
            echo "" >> "$temp_net_file"
        fi
    else
        echo "sar not available (install sysstat package)" >> "$temp_net_file"
        echo "" >> "$temp_net_file"
    fi
    if [ "$sar_success" = true ]; then
        net_metrics_success=true
    fi
    
    # === 延迟测试 ===
    echo "=== Latency Tests ===" >> "$temp_net_file"
    local latency_success=false
    
    # 获取默认网关
    GATEWAY=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1)
    if [ -n "$GATEWAY" ]; then
        echo "Default gateway: $GATEWAY" >> "$temp_net_file"
        PING_GW_TMP="/tmp/ping_gw_$$.txt"
        if ping -c 5 "$GATEWAY" 2>/dev/null > "$PING_GW_TMP"; then
            if [ -s "$PING_GW_TMP" ]; then
                tail -2 "$PING_GW_TMP" >> "$temp_net_file"
                latency_success=true
            else
                echo "Gateway unreachable or ping failed" >> "$temp_net_file"
            fi
        else
            echo "Gateway ping failed" >> "$temp_net_file"
        fi
        rm -f "$PING_GW_TMP"
    else
        echo "No default gateway found" >> "$temp_net_file"
    fi
    echo "" >> "$temp_net_file"
    
    echo "--- Loopback Latency Test ---" >> "$temp_net_file"
    PING_LO_TMP="/tmp/ping_lo_$$.txt"
    if ping -c 5 127.0.0.1 2>/dev/null > "$PING_LO_TMP"; then
        if [ -s "$PING_LO_TMP" ]; then
            tail -2 "$PING_LO_TMP" >> "$temp_net_file"
            latency_success=true
        fi
    else
        echo "Loopback ping failed" >> "$temp_net_file"
    fi
    rm -f "$PING_LO_TMP"
    echo "" >> "$temp_net_file"
    
    if [ "$latency_success" = true ]; then
        net_metrics_success=true
    fi
    
    # === TCP 统计 ===
    echo "=== TCP Statistics ===" >> "$temp_net_file"
    local tcp_stats_success=false
    if command -v netstat &> /dev/null; then
        if netstat -s 2>/dev/null | sed -n '/^Tcp:/,/^$/p' | head -50 >> "$temp_net_file"; then
            tcp_stats_success=true
        else
            echo "netstat command failed" >> "$temp_net_file"
        fi
    else
        echo "netstat not available" >> "$temp_net_file"
    fi
    echo "" >> "$temp_net_file"
    if [ "$tcp_stats_success" = true ]; then
        net_metrics_success=true
    fi
    
    # === Socket 摘要 ===
    echo "=== Socket Summary ===" >> "$temp_net_file"
    local socket_summary_success=false
    if command -v ss &> /dev/null; then
        if ss -s 2>/dev/null >> "$temp_net_file"; then
            socket_summary_success=true
        fi
    else
        echo "ss not available" >> "$temp_net_file"
    fi
    echo "" >> "$temp_net_file"
    if [ "$socket_summary_success" = true ]; then
        net_metrics_success=true
    fi
    
    # === Socket 内存统计 ===
    echo "=== Socket Memory ===" >> "$temp_net_file"
    if [ -r /proc/net/sockstat ]; then
        cat /proc/net/sockstat >> "$temp_net_file" 2>/dev/null && net_metrics_success=true
    else
        echo "Cannot read /proc/net/sockstat" >> "$temp_net_file"
    fi
    echo "" >> "$temp_net_file"
    
    # === TCP 连接状态分布 ===
    echo "=== TCP Connection States Distribution ===" >> "$temp_net_file"
    local tcp_states_success=false
    if command -v ss &> /dev/null; then
        if ss -tan 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -10 >> "$temp_net_file"; then
            tcp_states_success=true
        fi
    else
        echo "ss not available" >> "$temp_net_file"
    fi
    echo "" >> "$temp_net_file"
    if [ "$tcp_states_success" = true ]; then
        net_metrics_success=true
    fi
    
    # === 网络队列统计 ===
    echo "=== Network Queue Statistics ===" >> "$temp_net_file"
    if [ -r /proc/net/netstat ]; then
        echo "--- TCP Queue Info ---" >> "$temp_net_file"
        if cat /proc/net/netstat 2>/dev/null | grep -E "TcpExt|IpExt" | head -5 >> "$temp_net_file"; then
            net_metrics_success=true
        fi
    else
        echo "Cannot read /proc/net/netstat" >> "$temp_net_file"
    fi
    echo "" >> "$temp_net_file"
    
    # === 网络优化建议 ===
    echo "=== Network Optimization Recommendations ===" >> "$temp_net_file"
    local recommendations_success=false
    
    # 检查TCP内存压力
    if [ -r /proc/sys/net/ipv4/tcp_mem ]; then
        tcp_mem=$(cat /proc/sys/net/ipv4/tcp_mem 2>/dev/null)
        if [ -n "$tcp_mem" ]; then
            low_pressure=$(echo "$tcp_mem" | awk '{print $1}')
            pressure=$(echo "$tcp_mem" | awk '{print $2}')
            if [ -n "$pressure" ] && [ -n "$low_pressure" ] && [ "$pressure" -gt "$((low_pressure * 2))" ] 2>/dev/null; then
                echo "⚠ WARNING: TCP memory under pressure. Consider increasing tcp_mem or reducing connections." >> "$temp_net_file"
                recommendations_success=true
            fi
        fi
    fi
    
    # 检查TIME_WAIT连接数
    if command -v ss &> /dev/null; then
        timewait_count=$(ss -tan 2>/dev/null | grep -c TIME-WAIT)
        if [ -n "$timewait_count" ]; then
            if [ "$timewait_count" -gt 10000 ] 2>/dev/null; then
                echo "⚠ WARNING: High number of TIME_WAIT connections ($timewait_count). Consider adjusting tcp_tw_reuse and tcp_fin_timeout." >> "$temp_net_file"
                recommendations_success=true
            elif [ "$timewait_count" -gt 5000 ] 2>/dev/null; then
                echo "ℹ INFO: Moderate TIME_WAIT connections ($timewait_count). Consider optimizing if sustained." >> "$temp_net_file"
                recommendations_success=true
            fi
        fi
    fi
    
    # 检查端口范围
    if [ -r /proc/sys/net/ipv4/ip_local_port_range ]; then
        port_range=$(cat /proc/sys/net/ipv4/ip_local_port_range 2>/dev/null)
        if [ -n "$port_range" ]; then
            start_port=$(echo "$port_range" | awk '{print $1}')
            end_port=$(echo "$port_range" | awk '{print $2}')
            total_ports=$((end_port - start_port + 1))
            if command -v ss &> /dev/null; then
                used_ports=$(ss -tan 2>/dev/null | grep -c "ESTAB\|TIME_WAIT")
                if [ -n "$used_ports" ] && [ -n "$total_ports" ] && [ "$used_ports" -gt "$((total_ports * 80 / 100))" ] 2>/dev/null; then
                    echo "⚠ WARNING: Port range nearly exhausted (${used_ports}/${total_ports} used). Consider widening ip_local_port_range." >> "$temp_net_file"
                    recommendations_success=true
                fi
            fi
        fi
    fi
    
    # 检查网卡队列配置
    if command -v ethtool &> /dev/null && [ -n "$ACTIVE_IFACES" ]; then
        for iface in $ACTIVE_IFACES; do
            combined=$(ethtool -l $iface 2>/dev/null | grep -A5 "Current" | grep Combined | awk '{print $2}')
            if [ -n "$combined" ] && [ "$combined" -eq 1 ] 2>/dev/null; then
                echo "ℹ INFO: Interface $iface has only 1 combined queue. Consider increasing for better SMP performance." >> "$temp_net_file"
                recommendations_success=true
                break
            fi
        done
    fi

    echo "" >> "$NET_METRICS_FILE"

    # 接口详细状态（ifindex, operstate, carrier, mtu, speed, duplex）
    echo "=== 接口详细状态 (/sys/class/net) ===" >> "$NET_METRICS_FILE"
    for iface_dir in /sys/class/net/*; do
        iface_name=$(basename "$iface_dir")
        ifindex=$(cat "$iface_dir/ifindex" 2>/dev/null || echo "N/A")
        operstate=$(cat "$iface_dir/operstate" 2>/dev/null || echo "N/A")
        carrier=$(cat "$iface_dir/carrier" 2>/dev/null || echo "N/A")
        mtu=$(cat "$iface_dir/mtu" 2>/dev/null || echo "N/A")
        speed=$(cat "$iface_dir/speed" 2>/dev/null || echo "N/A")
        duplex=$(cat "$iface_dir/duplex" 2>/dev/null || echo "N/A")
        echo "$iface_name: ifindex=$ifindex operstate=$operstate carrier=$carrier mtu=$mtu speed=$speed duplex=$duplex" >> "$NET_METRICS_FILE"
    done
    echo "" >> "$NET_METRICS_FILE"

    # 完整 IP 地址信息
    echo "=== ip addr show ===" >> "$NET_METRICS_FILE"
    ip addr show 2>/dev/null >> "$NET_METRICS_FILE"
    echo "" >> "$NET_METRICS_FILE"

    # 路由表
    echo "=== 路由表 (ip route show) ===" >> "$NET_METRICS_FILE"
    ip route show 2>/dev/null >> "$NET_METRICS_FILE"
    echo "" >> "$NET_METRICS_FILE"

    # ARP 表
    echo "=== ARP 表 ===" >> "$NET_METRICS_FILE"
    arp -n 2>/dev/null >> "$NET_METRICS_FILE" || cat /proc/net/arp 2>/dev/null >> "$NET_METRICS_FILE"
    echo "" >> "$NET_METRICS_FILE"

    # 完整网络统计（netstat -s）—— 已有部分 TCP 统计，这里补全整个 netstat -s
    echo "=== 网络统计 (netstat -s) 完整版 ===" >> "$NET_METRICS_FILE"
    netstat -s 2>/dev/null >> "$NET_METRICS_FILE" || { cat /proc/net/netstat 2>/dev/null >> "$NET_METRICS_FILE"; cat /proc/net/snmp 2>/dev/null >> "$NET_METRICS_FILE"; }
    echo "" >> "$NET_METRICS_FILE"

    # 监听端口详情
    echo "=== 监听端口 (ss -tlnp) ===" >> "$NET_METRICS_FILE"
    ss -tlnp 2>/dev/null >> "$NET_METRICS_FILE"
    echo "" >> "$NET_METRICS_FILE"

    # 网卡队列与 RPS 配置
    echo "=== 网卡队列与 RPS 配置 ===" >> "$NET_METRICS_FILE"
    for iface_dir in /sys/class/net/*; do
        iface_name=$(basename "$iface_dir")
        if [ "$iface_name" != "lo" ] && [ -d "$iface_dir/queues" ]; then
            rx_count=$(ls -d "$iface_dir/queues/rx-"* 2>/dev/null | wc -l)
            tx_count=$(ls -d "$iface_dir/queues/tx-"* 2>/dev/null | wc -l)
            echo "$iface_name: RX队列=$rx_count, TX队列=$tx_count" >> "$NET_METRICS_FILE"
            if [ -f "$iface_dir/queues/rx-0/rps_cpus" ]; then
                echo "  RPS cpus (rx-0): $(cat "$iface_dir/queues/rx-0/rps_cpus")" >> "$NET_METRICS_FILE"
            fi
            if [ -f "$iface_dir/queues/rx-0/rps_flow_cnt" ]; then
                echo "  RPS flow_cnt (rx-0): $(cat "$iface_dir/queues/rx-0/rps_flow_cnt")" >> "$NET_METRICS_FILE"
            fi
        fi
    done
    echo "" >> "$NET_METRICS_FILE"

    # ntuple 支持
    echo "=== 网卡 ntuple 支持 ===" >> "$NET_METRICS_FILE"
    for iface_dir in /sys/class/net/*; do
        iface_name=$(basename "$iface_dir")
        [ "$iface_name" = "lo" ] && continue
        if command -v ethtool &>/dev/null; then
            ntuple_info=$(ethtool -k "$iface_name" 2>/dev/null | grep ntuple || echo 'ntuple: unknown')
            echo "$iface_name: $ntuple_info" >> "$NET_METRICS_FILE"
        fi
    done
    echo "" >> "$NET_METRICS_FILE"

    # 网络排队规则（tc qdisc）
    echo "=== 网络排队规则 (tc qdisc show) ===" >> "$NET_METRICS_FILE"
    tc qdisc show 2>/dev/null >> "$NET_METRICS_FILE"
    echo "" >> "$NET_METRICS_FILE"

    # /proc/net/dev 原始统计
    echo "=== /proc/net/dev ===" >> "$NET_METRICS_FILE"
    cat /proc/net/dev 2>/dev/null >> "$NET_METRICS_FILE" || echo "不可用" >> "$NET_METRICS_FILE"
    echo "" >> "$NET_METRICS_FILE"

    # 常见进程名列表（辅助上下文）
    echo "=== 常见进程名列表 (Top 30) ===" >> "$NET_METRICS_FILE"
    ps -eo comm --no-headers 2>/dev/null | sort -u | head -30 >> "$NET_METRICS_FILE"
    
    if [ "$recommendations_success" = true ]; then
        net_metrics_success=true
    fi
    
    echo "" >> "$temp_net_file"
    echo "============================================================" >> "$temp_net_file"
    echo "Network Metrics Analysis Complete" >> "$temp_net_file"
    echo "============================================================" >> "$temp_net_file"
    
    # 清理临时文件
    rm -f /tmp/sar_*_$$.txt /tmp/ping_*_$$.txt
    
    # 只有在至少有一个关键采集成功时才生成最终文件
    if [ "$net_metrics_success" = true ]; then
        mv "$temp_net_file" "$NET_METRICS_FILE"
        log_success "√ Network Metrics 深度分析完成，结果保存至: $NET_METRICS_FILE"
    else
        # 没有成功的采集，删除临时文件
        rm -f "$temp_net_file"
        log_warning "Network Metrics 深度分析全部失败，未生成 $NET_METRICS_FILE"
    fi
}

# =============================================================================
# Scheduler Trace 采集函数（整合自 collect_sched_trace_metrics.sh）
# =============================================================================
collect_sched_trace() {
    log_info "执行：Scheduler Trace 深度分析"
    
    # 标记是否有任何成功的采集
    sched_trace_success=false
    
    # 创建临时文件
    temp_sched_file="${SCHED_TRACE_FILE}.tmp"
    
    # 开始写入临时文件
    echo "============================================================" > "$temp_sched_file"
    echo "Phase: Scheduler Trace for Latency and Scheduling Analysis" >> "$temp_sched_file"
    echo "============================================================" >> "$temp_sched_file"
    echo "采集时间: $(date)" >> "$temp_sched_file"
    echo "持续时间: ${DURATION}秒" >> "$temp_sched_file"
    if [[ -n "$PIDS" ]]; then
        echo "目标进程: $PIDS" >> "$temp_sched_file"
    fi
    echo "" >> "$temp_sched_file"
    
    # === 前置条件检查 ===
    echo "=== Prerequisites ===" >> "$temp_sched_file"
    local prereq_success=false
    if [ -r /proc/sys/kernel/perf_event_paranoid ]; then
        echo "perf_event_paranoid: $(cat /proc/sys/kernel/perf_event_paranoid 2>/dev/null)" >> "$temp_sched_file"
        prereq_success=true
    else
        echo "perf_event_paranoid: N/A" >> "$temp_sched_file"
    fi
    if [ -r /proc/sys/kernel/sched_schedstats ]; then
        echo "sched_schedstats: $(cat /proc/sys/kernel/sched_schedstats 2>/dev/null)" >> "$temp_sched_file"
        prereq_success=true
    else
        echo "sched_schedstats: N/A" >> "$temp_sched_file"
    fi
    if [ "$prereq_success" = true ]; then
        sched_trace_success=true
    fi
    echo "" >> "$temp_sched_file"
    
    # === 调度器配置 ===
    echo "=== Scheduler Configuration ===" >> "$temp_sched_file"
    local sched_config_success=false
    
    # sched_latency_ns / base_slice_ns
    sched_latency="N/A"
    if [ -f /proc/sys/kernel/sched_latency_ns ] && [ -r /proc/sys/kernel/sched_latency_ns ]; then
        sched_latency=$(cat /proc/sys/kernel/sched_latency_ns 2>/dev/null)
        echo "sched_latency_ns: $sched_latency" >> "$temp_sched_file"
        sched_config_success=true
    elif [ -f /sys/kernel/debug/sched/base_slice_ns ] && [ -r /sys/kernel/debug/sched/base_slice_ns ]; then
        sched_latency=$(cat /sys/kernel/debug/sched/base_slice_ns 2>/dev/null)
        echo "base_slice_ns: $sched_latency" >> "$temp_sched_file"
        sched_config_success=true
    else
        echo "sched_latency_ns (base_slice_ns): N/A" >> "$temp_sched_file"
    fi
    
    # sched_min_granularity_ns
    if [ -f /proc/sys/kernel/sched_min_granularity_ns ] && [ -r /proc/sys/kernel/sched_min_granularity_ns ]; then
        echo "sched_min_granularity_ns: $(cat /proc/sys/kernel/sched_min_granularity_ns 2>/dev/null)" >> "$temp_sched_file"
        sched_config_success=true
    else
        echo "sched_min_granularity_ns: N/A (implicit on 6.x, ~0.75 * base_slice_ns)" >> "$temp_sched_file"
    fi
    
    # sched_wakeup_granularity_ns
    if [ -f /proc/sys/kernel/sched_wakeup_granularity_ns ] && [ -r /proc/sys/kernel/sched_wakeup_granularity_ns ]; then
        echo "sched_wakeup_granularity_ns: $(cat /proc/sys/kernel/sched_wakeup_granularity_ns 2>/dev/null)" >> "$temp_sched_file"
        sched_config_success=true
    else
        echo "sched_wakeup_granularity_ns: N/A (implicit on 6.x, ~1.0 * base_slice_ns)" >> "$temp_sched_file"
    fi
    
    # sched_tunable_scaling
    if [ -f /proc/sys/kernel/sched_tunable_scaling ] && [ -r /proc/sys/kernel/sched_tunable_scaling ]; then
        echo "sched_tunable_scaling: $(cat /proc/sys/kernel/sched_tunable_scaling 2>/dev/null)" >> "$temp_sched_file"
        sched_config_success=true
    elif [ -f /sys/kernel/debug/sched/tunable_scaling ] && [ -r /sys/kernel/debug/sched/tunable_scaling ]; then
        echo "sched_tunable_scaling: $(cat /sys/kernel/debug/sched/tunable_scaling 2>/dev/null)" >> "$temp_sched_file"
        sched_config_success=true
    else
        echo "sched_tunable_scaling: N/A" >> "$temp_sched_file"
    fi
    
    # sched_migration_cost_ns
    if [ -f /proc/sys/kernel/sched_migration_cost_ns ] && [ -r /proc/sys/kernel/sched_migration_cost_ns ]; then
        echo "sched_migration_cost_ns: $(cat /proc/sys/kernel/sched_migration_cost_ns 2>/dev/null)" >> "$temp_sched_file"
        sched_config_success=true
    elif [ -f /sys/kernel/debug/sched/migration_cost_ns ] && [ -r /sys/kernel/debug/sched/migration_cost_ns ]; then
        echo "sched_migration_cost_ns: $(cat /sys/kernel/debug/sched/migration_cost_ns 2>/dev/null)" >> "$temp_sched_file"
        sched_config_success=true
    fi
    
    # 其他调度配置
    for key in sched_autogroup_enabled sched_child_runs_first sched_rt_period_us sched_rt_runtime_us; do
        if [ -r "/proc/sys/kernel/$key" ]; then
            echo "$key: $(cat /proc/sys/kernel/$key 2>/dev/null)" >> "$temp_sched_file"
            sched_config_success=true
        fi
    done
    
    # CPU隔离配置
    if [ -r /proc/cmdline ]; then
        cmdline=$(cat /proc/cmdline 2>/dev/null)
        isolcpus=$(echo "$cmdline" | grep -o 'isolcpus=[^ ]*' || echo 'N/A')
        nohz_full=$(echo "$cmdline" | grep -o 'nohz_full=[^ ]*' || echo 'N/A')
        echo "isolcpus: $isolcpus" >> "$temp_sched_file"
        echo "nohz_full: $nohz_full" >> "$temp_sched_file"
        if [ "$isolcpus" != "N/A" ] || [ "$nohz_full" != "N/A" ]; then
            sched_config_success=true
        fi
    fi
    
    if [ "$sched_config_success" = true ]; then
        sched_trace_success=true
    fi
    echo "" >> "$temp_sched_file"
    
    # === 运行队列状态 ===
    echo "=== Run Queue Status ===" >> "$temp_sched_file"
    if command -v vmstat &> /dev/null; then
        if vmstat 1 2 2>/dev/null | tail -1 | awk '{print "running:", $1, "blocked:", $2}' >> "$temp_sched_file"; then
            sched_trace_success=true
        else
            echo "vmstat command failed" >> "$temp_sched_file"
        fi
    else
        echo "vmstat not available" >> "$temp_sched_file"
    fi
    echo "" >> "$temp_sched_file"
    
    # === 目标进程信息（如果指定了PID）===
    local process_info_success=false
    if [[ -n "$PIDS" ]]; then
        IFS=',' read -ra pid_array <<< "$PIDS"
        for single_pid in "${pid_array[@]}"; do
            single_pid=$(echo "$single_pid" | xargs)
            if ps -p "$single_pid" > /dev/null 2>&1; then
                echo "=== Target Process Info (PID: $single_pid) ===" >> "$temp_sched_file"
                if ps -p $single_pid -o pid,comm,state,pri,ni,nlwp --no-headers 2>/dev/null >> "$temp_sched_file"; then
                    process_info_success=true
                fi
                
                if command -v taskset &> /dev/null; then
                    echo "CPU Affinity:" >> "$temp_sched_file"
                    if taskset -pc $single_pid >> "$temp_sched_file" 2>/dev/null; then
                        process_info_success=true
                    fi
                fi
                
                if command -v chrt &> /dev/null; then
                    policy=$(chrt -p $single_pid 2>/dev/null | grep policy | awk '{print $NF}')
                    priority=$(chrt -p $single_pid 2>/dev/null | grep priority | awk '{print $NF}')
                    if [ -n "$policy" ]; then
                        echo "Scheduler Policy: $policy" >> "$temp_sched_file"
                        echo "RT Priority: $priority" >> "$temp_sched_file"
                        process_info_success=true
                    fi
                fi
                echo "" >> "$temp_sched_file"
            fi
        done
    fi
    if [ "$process_info_success" = true ]; then
        sched_trace_success=true
    fi
    
    # === perf sched 数据采集 ===
    echo "=== Recording perf sched data (timeout ${DURATION}s) ===" >> "$temp_sched_file"
    
    # 定义要跟踪的调度事件
    PERF_EVENTS="sched:sched_switch,sched:sched_wakeup,sched:sched_wakeup_new,sched:sched_migrate_task"
    local perf_sched_success=false
    
    # 执行perf record
    if command -v perf &> /dev/null; then
        # 如果是非root用户，可能需要调整perf_event_paranoid
        if [[ $EUID -ne 0 ]]; then
            log_warning "非root用户运行perf可能限制调度事件采集"
        fi
        
        local perf_data_file="${OUTPUT_DIR}/sched_perf.data"
        local perf_record_output=$(mktemp)
        
        # 执行 perf sched record
        if perf sched record -a -e $PERF_EVENTS -o "$perf_data_file" sleep ${DURATION} 2>&1 > "$perf_record_output"; then
            if [ -f "$perf_data_file" ] && [ -s "$perf_data_file" ]; then
                PERF_SIZE=$(du -h "$perf_data_file" 2>/dev/null | cut -f1)
                echo "sched_perf.data created: $PERF_SIZE" >> "$temp_sched_file"
                echo "" >> "$temp_sched_file"
                perf_sched_success=true
                
                # === 调度延迟分析 ===
                echo "=== Scheduling Latency (sorted by max/avg delay) ===" >> "$temp_sched_file"
                if perf sched latency -i "$perf_data_file" --sort max,avg 2>&1 | head -30 >> "$temp_sched_file"; then
                    perf_sched_success=true
                fi
                echo "" >> "$temp_sched_file"
                
                echo "=== Scheduling Latency (sorted by runtime) ===" >> "$temp_sched_file"
                if perf sched latency -i "$perf_data_file" 2>&1 | head -30 >> "$temp_sched_file"; then
                    perf_sched_success=true
                fi
                echo "" >> "$temp_sched_file"
                
                echo "=== Time History (first 50 lines) ===" >> "$temp_sched_file"
                if perf sched timehist -i "$perf_data_file" 2>&1 | head -50 >> "$temp_sched_file"; then
                    perf_sched_success=true
                fi
                echo "" >> "$temp_sched_file"
                
                # === 针对目标进程的详细分析 ===
                if [[ -n "$PIDS" ]]; then
                    IFS=',' read -ra pid_array <<< "$PIDS"
                    for single_pid in "${pid_array[@]}"; do
                        single_pid=$(echo "$single_pid" | xargs)
                        
                        echo "=== Target Process Analysis (PID: $single_pid) ===" >> "$temp_sched_file"
                        
                        # 生成脚本输出
                        SCHED_SCRIPT="/tmp/perf_sched_script_${single_pid}_$$.txt"
                        if perf sched script -i "$perf_data_file" > "$SCHED_SCRIPT" 2>&1; then
                            # 调度切出事件统计
                            SWITCH_COUNT=$(grep -c "sched_switch: .*:${single_pid} \[.*\] . ==> " "$SCHED_SCRIPT" 2>/dev/null || echo "0")
                            echo "Schedule Out Events: $SWITCH_COUNT" >> "$temp_sched_file"
                            if [ "$SWITCH_COUNT" -gt 0 ] 2>/dev/null && [ "$DURATION" -gt 0 ] 2>/dev/null; then
                                FREQ=$(echo "scale=2; $SWITCH_COUNT / $DURATION" | bc 2>/dev/null)
                                if [ -n "$FREQ" ] && [ "$FREQ" != "0" ]; then
                                    echo "Frequency: ${FREQ} events/s" >> "$temp_sched_file"
                                else
                                    echo "Frequency: N/A" >> "$temp_sched_file"
                                fi
                            fi
                            echo "" >> "$temp_sched_file"
                            
                            # 抢占者分析
                            echo "=== Preemptors (processes that ran before target, top 10 cnts) ===" >> "$temp_sched_file"
                            grep "==> .*:${single_pid} \[" "$SCHED_SCRIPT" 2>/dev/null | \
                                sed 's/.*sched_switch: //' | sed 's/ ==> .*//' | awk '{print $1}' | \
                                sort | uniq -c | sort -rn | head -10 >> "$temp_sched_file"
                            echo "" >> "$temp_sched_file"
                            
                            # 后继者分析
                            echo "=== Successors (processes that ran after target, top 10 cnts) ===" >> "$temp_sched_file"
                            grep "sched_switch: .*:${single_pid} \[.*\] . ==> " "$SCHED_SCRIPT" 2>/dev/null | \
                                sed 's/.*==> //' | awk '{print $1}' | \
                                sort | uniq -c | sort -rn | head -10 >> "$temp_sched_file"
                            echo "" >> "$temp_sched_file"
                            
                            perf_sched_success=true
                        fi
                        
                        # 时间历史
                        echo "=== Time History for Target ===" >> "$temp_sched_file"
                        if perf sched timehist -i "$perf_data_file" --tid $single_pid 2>&1 | head -50 >> "$temp_sched_file"; then
                            perf_sched_success=true
                        fi
                        echo "" >> "$temp_sched_file"
                        
                        # 唤醒延迟
                        echo "=== Wakeup Latency for Target ===" >> "$temp_sched_file"
                        SCHED_TIMEHIST_TARGET="/tmp/perf_sched_timehist_${single_pid}_$$.txt"
                        if perf sched timehist -i "$perf_data_file" --tid $single_pid > "$SCHED_TIMEHIST_TARGET" 2>&1; then
                            awk 'NR>3 && NF>=6 {wait+=$4; delay+=$5; if($4>max_w) max_w=$4; if($5>max_d) max_d=$5; n++} END {if(n>0) printf "Avg wait: %.3f ms, sch_delay: %.3f ms, Max wait: %.3f ms, Max delay: %.3f ms (samples: %d)\n", wait/n, delay/n, max_w, max_d, n}' "$SCHED_TIMEHIST_TARGET" >> "$temp_sched_file"
                            perf_sched_success=true
                        fi
                        echo "" >> "$temp_sched_file"
                        
                        # 清理临时文件
                        rm -f "$SCHED_SCRIPT" "$SCHED_TIMEHIST_TARGET"
                    done
                fi
                
                # 保留perf.data文件供后续分析
                log_info "sched_perf.data 文件已保存在: ${OUTPUT_DIR}/sched_perf.data"
            else
                echo "Error: sched_perf.data not created or empty" >> "$temp_sched_file"
                log_error "sched_perf.data 创建失败"
            fi
        else
            echo "Error: perf sched record failed" >> "$temp_sched_file"
            if [ -f "$perf_record_output" ] && [ -s "$perf_record_output" ]; then
                echo "Error details:" >> "$temp_sched_file"
                cat "$perf_record_output" >> "$temp_sched_file"
            fi
            log_error "perf sched record 执行失败"
        fi
        rm -f "$perf_record_output"
    else
        echo "perf command not available" >> "$temp_sched_file"
        log_error "perf命令未找到"
    fi
    
    if [ "$perf_sched_success" = true ]; then
        sched_trace_success=true
    fi
    
    echo "" >> "$temp_sched_file"
    
    # === 调度器优化建议 ===
    echo "=== Scheduler Optimization Recommendations ===" >> "$temp_sched_file"
    local recommendations_success=false
    
    # 检查调度延迟配置
    if [ -n "$sched_latency" ] && [ "$sched_latency" -gt 8000000 ] 2>/dev/null; then
        echo "ℹ INFO: High scheduler latency (${sched_latency}ns > 8ms). Consider reducing for better responsiveness." >> "$temp_sched_file"
        recommendations_success=true
    fi
    
    # 检查RT调度配置
    if [ -r /proc/sys/kernel/sched_rt_runtime_us ]; then
        rt_runtime=$(cat /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null)
        if [ -n "$rt_runtime" ] && [ "$rt_runtime" -eq 0 ] 2>/dev/null; then
            echo "ℹ INFO: sched_rt_runtime_us=0 (RT tasks unlimited). Consider setting to 950000 to reserve 5% for SCHED_OTHER." >> "$temp_sched_file"
            recommendations_success=true
        fi
    fi
    
    # 检查CPU隔离
    if [ -r /proc/cmdline ] && grep -q "isolcpus" /proc/cmdline 2>/dev/null; then
        echo "ℹ INFO: CPU isolation detected. Ensure target process is pinned to isolated CPUs for best performance." >> "$temp_sched_file"
        recommendations_success=true
    fi
    
    # 检查nohz_full
    if [ -r /proc/cmdline ] && grep -q "nohz_full" /proc/cmdline 2>/dev/null; then
        echo "ℹ INFO: nohz_full enabled. Reduces timer interrupts on specified CPUs." >> "$temp_sched_file"
        recommendations_success=true
    fi
    
    # 检查perf权限
    if [ -r /proc/sys/kernel/perf_event_paranoid ]; then
        perf_paranoid=$(cat /proc/sys/kernel/perf_event_paranoid 2>/dev/null)
        if [ -n "$perf_paranoid" ] && [ "$perf_paranoid" -gt 1 ] 2>/dev/null; then
            echo "💡 TIP: perf_event_paranoid=${perf_paranoid} may limit profiling. Set to 1 or 0 for more data: echo 1 > /proc/sys/kernel/perf_event_paranoid" >> "$temp_sched_file"
            recommendations_success=true
        fi
    fi
    
    if [ "$recommendations_success" = true ]; then
        sched_trace_success=true
    fi
    
    echo "" >> "$temp_sched_file"
    echo "============================================================" >> "$temp_sched_file"
    echo "Scheduler Trace Analysis Complete" >> "$temp_sched_file"
    echo "============================================================" >> "$temp_sched_file"
    
    # 只有在至少有一个关键采集成功时才生成最终文件
    if [ "$sched_trace_success" = true ]; then
        mv "$temp_sched_file" "$SCHED_TRACE_FILE"
        log_success "√ Scheduler Trace 深度分析完成，结果保存至: $SCHED_TRACE_FILE"
    else
        # 没有成功的采集，删除临时文件
        rm -f "$temp_sched_file"
        log_warning "Scheduler Trace 深度分析全部失败，未生成 $SCHED_TRACE_FILE"
    fi
}

get_software() {
    log_info "开始扫描当前软件版本"
    if [ -f "${SOFTWARE_FILE}" ];then
        return
    fi
    if command -v rpm &> /dev/null; then
        # Red Hat/CentOS/Fedora/SUSE
        rpm -qa --queryformat "%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n" > "${SOFTWARE_FILE}" 2>/dev/null
    elif command -v dpkg &> /dev/null; then
        # Debian/Ubuntu
        dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' > "${SOFTWARE_FILE}" 2>/dev/null
    elif command -v apk &> /dev/null; then
    # Alpine
        apk list --installed 2>/dev/null | tail -n +2 | awk '{print $1, $2, $3}' > "${SOFTWARE_FILE}"
    else
        echo "错误: 无法识别包管理器" >&2
        return
    fi

    log_success "软件列表已保存到 ${SOFTWARE_FILE} 共计$(wc -l < ${SOFTWARE_FILE})个软件"
}

collect_cpu_detail_info() {
    log_info "执行：CPU 深度信息采集"
    > "$CPU_DETAIL_FILE"
    echo "============================================================" >> "$CPU_DETAIL_FILE"
    echo "CPU 深度信息采集" >> "$CPU_DETAIL_FILE"
    echo "采集时间: $(date)" >> "$CPU_DETAIL_FILE"
    echo "============================================================" >> "$CPU_DETAIL_FILE"
    echo "" >> "$CPU_DETAIL_FILE"

    # 1. 在线 CPU 核心列表及数量
    echo "=== 在线 CPU 核心列表 ===" >> "$CPU_DETAIL_FILE"
    if [ -f /sys/devices/system/cpu/online ]; then
        echo "CPU 在线列表: $(cat /sys/devices/system/cpu/online)" >> "$CPU_DETAIL_FILE"
        COUNT=$(tr ',' '\n' < /sys/devices/system/cpu/online | while read -r r; do
            if [[ "$r" == *-* ]]; then
                seq "${r%-*}" "${r#*-}" || true
            else
                echo "$r"
            fi
        done | wc -l)
        echo "在线CPU数量: $COUNT" >> "$CPU_DETAIL_FILE"
    else
        echo "警告: /sys/devices/system/cpu/online 不存在" >> "$CPU_DETAIL_FILE"
        echo "在线CPU数量: $(nproc)" >> "$CPU_DETAIL_FILE"
    fi
    echo "" >> "$CPU_DETAIL_FILE"

    # 2. /proc/cpuinfo
    echo "=== /proc/cpuinfo ===" >> "$CPU_DETAIL_FILE"
    cat /proc/cpuinfo >> "$CPU_DETAIL_FILE" 2>/dev/null || true
    echo "" >> "$CPU_DETAIL_FILE"

    # 3. NUMA 节点 sysfs 详情
    echo "=== NUMA 节点 sysfs 详情 ===" >> "$CPU_DETAIL_FILE"
    if [ -d /sys/devices/system/node ]; then
        for node in /sys/devices/system/node/node*; do
            if [ -d "$node" ]; then
                node_name=$(basename "$node")
                echo "--- $node_name ---" >> "$CPU_DETAIL_FILE"
                [ -f "$node/cpulist" ] && echo "CPU列表: $(cat "$node/cpulist")" >> "$CPU_DETAIL_FILE"
                [ -f "$node/distance" ] && echo "距离: $(cat "$node/distance")" >> "$CPU_DETAIL_FILE"
            fi
        done
        echo "" >> "$CPU_DETAIL_FILE"
        for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
            cpu_name=$(basename "$cpu_dir")
            if [ -f "$cpu_dir/topology/physical_package_id" ]; then
                socket_id=$(cat "$cpu_dir/topology/physical_package_id" 2>/dev/null || echo '?')
                echo "$cpu_name socket=$socket_id" >> "$CPU_DETAIL_FILE"
            fi
        done
    else
        echo "警告: /sys/devices/system/node 不存在" >> "$CPU_DETAIL_FILE"
    fi
    echo "" >> "$CPU_DETAIL_FILE"

    # 4. SMT / 超线程状态
    echo "=== SMT 超线程状态 ===" >> "$CPU_DETAIL_FILE"
    if [ -f /sys/devices/system/cpu/smt/active ]; then
        echo "SMT active: $(cat /sys/devices/system/cpu/smt/active)" >> "$CPU_DETAIL_FILE"
    else
        echo "SMT active: unknown" >> "$CPU_DETAIL_FILE"
    fi
    for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
        cpu_name=$(basename "$cpu_dir")
        if [ -f "$cpu_dir/topology/thread_siblings_list" ]; then
            siblings=$(cat "$cpu_dir/topology/thread_siblings_list" 2>/dev/null || echo '?')
            echo "$cpu_name siblings=$siblings" >> "$CPU_DETAIL_FILE"
        fi
    done
    echo "" >> "$CPU_DETAIL_FILE"

    # 5. CPU 频率信息（所有核心）
    echo "=== CPU 频率信息 ===" >> "$CPU_DETAIL_FILE"
    if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq; do
            if [ -d "$cpu" ]; then
                cpu_name=$(basename "$(dirname "$cpu")")
                echo "$cpu_name:" >> "$CPU_DETAIL_FILE"
                cat "$cpu/scaling_cur_freq" 2>/dev/null | awk '{printf "  当前频率: %s kHz\n", $1}' >> "$CPU_DETAIL_FILE" || true
                cat "$cpu/scaling_max_freq" 2>/dev/null | awk '{printf "  最大频率: %s kHz\n", $1}' >> "$CPU_DETAIL_FILE" || true
                cat "$cpu/cpuinfo_max_freq" 2>/dev/null | awk '{printf "  硬件最大频率: %s kHz\n", $1}' >> "$CPU_DETAIL_FILE" || true
                cat "$cpu/scaling_min_freq" 2>/dev/null | awk '{printf "  最小频率: %s kHz\n", $1}' >> "$CPU_DETAIL_FILE" || true
                cat "$cpu/scaling_governor" 2>/dev/null | awk '{printf "  调频策略: %s\n", $1}' >> "$CPU_DETAIL_FILE" || true
            fi
        done
    else
        echo "注意: cpufreq 不可用" >> "$CPU_DETAIL_FILE"
    fi
    echo "" >> "$CPU_DETAIL_FILE"

    # 6. CPPC 支持检查
    echo "=== 硬件 CPPC 支持 ===" >> "$CPU_DETAIL_FILE"
    if grep -qi "cppc" /proc/cpuinfo 2>/dev/null; then
        echo "yes" >> "$CPU_DETAIL_FILE"
    else
        echo "no" >> "$CPU_DETAIL_FILE"
    fi
    echo "" >> "$CPU_DETAIL_FILE"

    # 7. /proc/interrupts
    echo "=== /proc/interrupts ===" >> "$CPU_DETAIL_FILE"
    head -20 /proc/interrupts >> "$CPU_DETAIL_FILE" 2>/dev/null || true
    echo "" >> "$CPU_DETAIL_FILE"

    # 8. /proc/stat 解析
    echo "=== /proc/stat 解析 ===" >> "$CPU_DETAIL_FILE"
    awk '/cpu[0-9]+/ {
        cpu=$1; gsub(/cpu/,"",cpu);
        printf "cpu%-3d user=%-10s nice=%-10s system=%-10s idle=%-10s iowait=%-10s irq=%-8s softirq=%-8s steal=%-8s\n",cpu,$2,$3,$4,$5,$6,$7,$8,$9
    }
    /^cpu / {
        printf "cpu_total user=%-10s nice=%-10s system=%-10s idle=%-10s iowait=%-10s irq=%-8s softirq=%-8s steal=%-8s\n",$2,$3,$4,$5,$6,$7,$8,$9
    }' /proc/stat >> "$CPU_DETAIL_FILE" || true
    echo "" >> "$CPU_DETAIL_FILE"

    # 9. 多采样 /proc/stat 观测
    echo "=== /proc/stat 多采样观测 (${DURATION}秒) ===" >> "$CPU_DETAIL_FILE"
    NUM_SAMPLES=$(( DURATION / INTERVAL + 1 ))
    [ "$NUM_SAMPLES" -lt 2 ] && NUM_SAMPLES=2
    for ((i=1; i<=NUM_SAMPLES; i++)); do
        TS_EPOCH=$(date +%s.%N)
        {
            echo "=== SAMPLE $i ==="
            echo "=== TIMESTAMP $TS_EPOCH ==="
            echo "=== HOST_STAT ==="
            grep '^cpu ' /proc/stat
            echo "=== END_HOST_STAT ==="
            echo ""
        } >> "$CPU_DETAIL_FILE"
        if [ "$i" -lt "$NUM_SAMPLES" ]; then
            sleep "$INTERVAL"
        fi
    done
    echo "总轮次: $NUM_SAMPLES" >> "$CPU_DETAIL_FILE"
    echo "" >> "$CPU_DETAIL_FILE"

    log_success "√ CPU 深度信息采集完成"
}

collect_kernel_config_info() {
    log_info "执行：内核深度诊断信息采集"
    > "$KERNEL_CONFIG_FILE"
    echo "============================================================" >> "$KERNEL_CONFIG_FILE"
    echo "内核深度诊断信息采集" >> "$KERNEL_CONFIG_FILE"
    echo "采集时间: $(date)" >> "$KERNEL_CONFIG_FILE"
    echo "============================================================" >> "$KERNEL_CONFIG_FILE"
    echo "" >> "$KERNEL_CONFIG_FILE"

    # ---- 全量 sysctl -a ----
    echo "=== 全量内核参数 (sysctl -a) ===" >> "$KERNEL_CONFIG_FILE"
    if command -v sysctl &>/dev/null; then
        sysctl -a 2>/dev/null | sort >> "$KERNEL_CONFIG_FILE"
    fi
    echo "" >> "$KERNEL_CONFIG_FILE"

    # ---- 关键内核参数分组提取（补充原脚本未覆盖的类别） ----
    echo "=== 关键内核参数补充 ===" >> "$KERNEL_CONFIG_FILE"

    # 网络核心与缓冲区
    echo "--- 网络核心参数 ---" >> "$KERNEL_CONFIG_FILE"
    sysctl -a 2>/dev/null | grep -E "^net\.core\.|^net\.ipv4\.tcp_|^net\.ipv4\.udp_|^net\.ipv4\.ip_|^net\.nf" >> "$KERNEL_CONFIG_FILE" || echo "无匹配" >> "$KERNEL_CONFIG_FILE"
    echo "" >> "$KERNEL_CONFIG_FILE"

    echo "--- 网络缓冲区 ---" >> "$KERNEL_CONFIG_FILE"
    sysctl -a 2>/dev/null | grep -E "^net\.core\.(r|w)mem|^net\.core\.netdev|^net\.core\.somaxconn|^net\.core\.optmem" >> "$KERNEL_CONFIG_FILE" || echo "无匹配" >> "$KERNEL_CONFIG_FILE"
    echo "" >> "$KERNEL_CONFIG_FILE"

    # 用户命名空间
    echo "--- 用户命名空间限制 ---" >> "$KERNEL_CONFIG_FILE"
    sysctl -a 2>/dev/null | grep "^user\.max_" >> "$KERNEL_CONFIG_FILE" || echo "无匹配" >> "$KERNEL_CONFIG_FILE"
    echo "" >> "$KERNEL_CONFIG_FILE"

    # ---- 内核启动参数补充检测 ----
    echo "=== 内核启动参数特殊项 ===" >> "$KERNEL_CONFIG_FILE"
    if [ -f /proc/cmdline ]; then
        grep -qo 'xcall' /proc/cmdline 2>/dev/null && echo "xcall: yes" >> "$KERNEL_CONFIG_FILE" || echo "xcall: no" >> "$KERNEL_CONFIG_FILE"
        grep -qo 'sched_steal_node_limit' /proc/cmdline 2>/dev/null && echo "sched_steal_node_limit: yes" >> "$KERNEL_CONFIG_FILE" || echo "sched_steal_node_limit: no" >> "$KERNEL_CONFIG_FILE"
    else
        echo "/proc/cmdline 不可用" >> "$KERNEL_CONFIG_FILE"
    fi
    echo "" >> "$KERNEL_CONFIG_FILE"

    # ---- 调度特性文件 (debugfs) ----
    echo "=== 调度特性 ===" >> "$KERNEL_CONFIG_FILE"
    SCHED_FEAT=""
    [ -f /sys/kernel/debug/sched_features ] && SCHED_FEAT="/sys/kernel/debug/sched_features"
    [ -f /sys/kernel/debug/sched/features ] && SCHED_FEAT="/sys/kernel/debug/sched/features"
    if [ -n "$SCHED_FEAT" ]; then
        cat "$SCHED_FEAT" >> "$KERNEL_CONFIG_FILE" 2>/dev/null || echo "无法读取" >> "$KERNEL_CONFIG_FILE"
        [ -w "$SCHED_FEAT" ] && echo "writable" >> "$KERNEL_CONFIG_FILE" || echo "not writable" >> "$KERNEL_CONFIG_FILE"
        grep -ow 'SOFT_DOMAIN' "$SCHED_FEAT" >/dev/null 2>&1 && echo "SOFT_DOMAIN: present" >> "$KERNEL_CONFIG_FILE" || echo "SOFT_DOMAIN: NOT present" >> "$KERNEL_CONFIG_FILE"
        grep -ow 'KEEP_ON_CORE' "$SCHED_FEAT" >/dev/null 2>&1 && echo "KEEP_ON_CORE: present" >> "$KERNEL_CONFIG_FILE" || echo "KEEP_ON_CORE: NOT present" >> "$KERNEL_CONFIG_FILE"
        grep -ow 'PARAL' "$SCHED_FEAT" >/dev/null 2>&1 && echo "PARAL: present" >> "$KERNEL_CONFIG_FILE" || echo "PARAL: NOT present" >> "$KERNEL_CONFIG_FILE"
    else
        echo "调度特性文件不可用" >> "$KERNEL_CONFIG_FILE"
    fi
    echo "" >> "$KERNEL_CONFIG_FILE"

    # ---- 特殊调度参数 ----
    echo "=== 特殊调度参数 ===" >> "$KERNEL_CONFIG_FILE"
    cat /proc/sys/kernel/sched_cluster 2>/dev/null >> "$KERNEL_CONFIG_FILE" || echo "sched_cluster: not exist" >> "$KERNEL_CONFIG_FILE"
    cat /proc/sys/kernel/sched_util_ratio 2>/dev/null >> "$KERNEL_CONFIG_FILE" || echo "sched_util_ratio: not exist" >> "$KERNEL_CONFIG_FILE"
    cat /proc/sys/kernel/sched_util_low_pct 2>/dev/null >> "$KERNEL_CONFIG_FILE" || echo "sched_util_low_pct: not exist" >> "$KERNEL_CONFIG_FILE"
    if [ -f /proc/sys/kernel/sched_soft_runtime_ratio ]; then
        echo "Docker CPU Burst: yes, value=$(cat /proc/sys/kernel/sched_soft_runtime_ratio)" >> "$KERNEL_CONFIG_FILE"
    else
        echo "Docker CPU Burst: no" >> "$KERNEL_CONFIG_FILE"
    fi
    echo "" >> "$KERNEL_CONFIG_FILE"

    # ---- 完整内核模块列表 ----
    echo "=== 完整内核模块列表 (lsmod) ===" >> "$KERNEL_CONFIG_FILE"
    lsmod 2>/dev/null >> "$KERNEL_CONFIG_FILE"
    echo "" >> "$KERNEL_CONFIG_FILE"

    # ---- 内核版本与详细编译选项 ----
    echo "=== 内核版本与编译选项 ===" >> "$KERNEL_CONFIG_FILE"
    uname -a >> "$KERNEL_CONFIG_FILE"
    cat /proc/version 2>/dev/null >> "$KERNEL_CONFIG_FILE"
    KERNEL_VER=$(uname -r)
    if [ -f /boot/config-${KERNEL_VER} ]; then
        grep -E "CONFIG_IKCONFIG|CONFIG_HZ|CONFIG_PREEMPT|CONFIG_NR_CPUS|CONFIG_HUGETLB|CONFIG_TRANSPARENT|CONFIG_CGROUP|CONFIG_NAMESPACE|CONFIG_SCHED_STEAL|CONFIG_SCHED_SMT" \
            /boot/config-${KERNEL_VER} 2>/dev/null >> "$KERNEL_CONFIG_FILE"
    elif [ -f /proc/config.gz ]; then
        zcat /proc/config.gz 2>/dev/null | grep -E "CONFIG_IKCONFIG|CONFIG_HZ|CONFIG_PREEMPT|CONFIG_NR_CPUS|CONFIG_HUGETLB|CONFIG_TRANSPARENT|CONFIG_CGROUP|CONFIG_SCHED_STEAL|CONFIG_SCHED_SMT" >> "$KERNEL_CONFIG_FILE"
    else
        echo "未找到内核 config 文件" >> "$KERNEL_CONFIG_FILE"
    fi
    echo "" >> "$KERNEL_CONFIG_FILE"

    # ---- 系统诊断 ----
    echo "=== 系统诊断 ===" >> "$KERNEL_CONFIG_FILE"

    # 内核 taint
    echo "--- 内核 taint ---" >> "$KERNEL_CONFIG_FILE"
    cat /proc/sys/kernel/tainted 2>/dev/null >> "$KERNEL_CONFIG_FILE" || echo "无法读取" >> "$KERNEL_CONFIG_FILE"
    echo "(0=未污染)" >> "$KERNEL_CONFIG_FILE"
    echo "" >> "$KERNEL_CONFIG_FILE"

    # dmesg Oops/Panic
    echo "--- 内核 Oops/Panic (dmesg) ---" >> "$KERNEL_CONFIG_FILE"
    dmesg 2>/dev/null | grep -i -E "Oops|panic|BUG|Call Trace|WARNING" | tail -20 >> "$KERNEL_CONFIG_FILE"
    echo "" >> "$KERNEL_CONFIG_FILE"

    # 活跃内核线程
    echo "--- 活跃内核线程 (前20) ---" >> "$KERNEL_CONFIG_FILE"
    ps -eo pid,comm --no-headers 2>/dev/null | awk '$2 ~ /^\[.*\]$/ {print}' | head -20 >> "$KERNEL_CONFIG_FILE"
    echo "" >> "$KERNEL_CONFIG_FILE"

    # THP defrag 补充
    echo "--- 透明大页 defrag ---" >> "$KERNEL_CONFIG_FILE"
    cat /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null >> "$KERNEL_CONFIG_FILE" || echo "不可用" >> "$KERNEL_CONFIG_FILE"
    echo "THP enabled writable: $(test -w /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null && echo writable || echo 'not writable')" >> "$KERNEL_CONFIG_FILE"
    echo "" >> "$KERNEL_CONFIG_FILE"

    # ---- 内核特性与模块诊断 ----
    echo "=== 内核特性与模块诊断 ===" >> "$KERNEL_CONFIG_FILE"
    echo "--- /proc/1/xcall ---" >> "$KERNEL_CONFIG_FILE"
    test -f /proc/1/xcall && echo "exists" >> "$KERNEL_CONFIG_FILE"

    echo "--- irqbalance ---" >> "$KERNEL_CONFIG_FILE"
    # 部分系统（如某些 Debian 衍生版）服务名为 irqbalance-ng，需同时检查两个服务名
    _irq_status="unknown"
    _irq_svc="irqbalance"
    if systemctl list-unit-files irqbalance.service 2>/dev/null | grep -q 'irqbalance\.service'; then
        _irq_status=$(systemctl is-active irqbalance 2>/dev/null || echo "inactive")
        _irq_svc="irqbalance"
    elif systemctl list-unit-files irqbalance-ng.service 2>/dev/null | grep -q 'irqbalance-ng\.service'; then
        _irq_status=$(systemctl is-active irqbalance-ng 2>/dev/null || echo "inactive")
        _irq_svc="irqbalance-ng"
    fi
    echo "$_irq_status" >> "$KERNEL_CONFIG_FILE"
    echo "--- irqbalance-service ---" >> "$KERNEL_CONFIG_FILE"
    echo "$_irq_svc" >> "$KERNEL_CONFIG_FILE"

    echo "--- oenetcls ---" >> "$KERNEL_CONFIG_FILE"
    modinfo oenetcls >> "$KERNEL_CONFIG_FILE" 2>/dev/null && echo "available" >> "$KERNEL_CONFIG_FILE"

    echo "--- SMC ---" >> "$KERNEL_CONFIG_FILE"
    if lsmod 2>/dev/null | grep -qi smc; then
        echo "loaded" >> "$KERNEL_CONFIG_FILE"
        lsmod 2>/dev/null | grep -i smc >> "$KERNEL_CONFIG_FILE"
    else
        echo "not loaded" >> "$KERNEL_CONFIG_FILE"
    fi

    echo "--- ism ---" >> "$KERNEL_CONFIG_FILE"
    lsmod 2>/dev/null | grep -qi ism && echo "loaded" >> "$KERNEL_CONFIG_FILE" && lsmod 2>/dev/null | grep -i ism >> "$KERNEL_CONFIG_FILE" || echo "not loaded" >> "$KERNEL_CONFIG_FILE"

    echo "--- cpufreq_seep / oenetcls in /proc/modules ---" >> "$KERNEL_CONFIG_FILE"
    grep -E 'oenetcls|cpufreq_seep' /proc/modules 2>/dev/null >> "$KERNEL_CONFIG_FILE" || echo "(无匹配)" >> "$KERNEL_CONFIG_FILE"

    echo "--- xcall_numa 参数 ---" >> "$KERNEL_CONFIG_FILE"
    ls /proc/sys/kernel/xcall_numa* 2>/dev/null >> "$KERNEL_CONFIG_FILE" || echo "xcall_numa* not exist" >> "$KERNEL_CONFIG_FILE"

    echo "--- debugfs 挂载 ---" >> "$KERNEL_CONFIG_FILE"
    mount 2>/dev/null | grep debugfs >> "$KERNEL_CONFIG_FILE" || echo "debugfs not mounted" >> "$KERNEL_CONFIG_FILE"

    echo "--- numafast ---" >> "$KERNEL_CONFIG_FILE"
    rpm -qa 2>/dev/null | grep numafast >> "$KERNEL_CONFIG_FILE" || echo "not installed" >> "$KERNEL_CONFIG_FILE"

    echo "--- ARM SPE ---" >> "$KERNEL_CONFIG_FILE"
    perf list 2>/dev/null | grep -qi arm_spe && echo "available" >> "$KERNEL_CONFIG_FILE" || echo "not available" >> "$KERNEL_CONFIG_FILE"
    echo "" >> "$KERNEL_CONFIG_FILE"

    # ---- 其他系统诊断 ----
    echo "=== 其他系统诊断 ===" >> "$KERNEL_CONFIG_FILE"
    echo "--- /proc/filesystems ---" >> "$KERNEL_CONFIG_FILE"
    cat /proc/filesystems 2>/dev/null >> "$KERNEL_CONFIG_FILE"
    echo "" >> "$KERNEL_CONFIG_FILE"

    echo "--- SECCOMP 进程 (strict) ---" >> "$KERNEL_CONFIG_FILE"
    grep -l "Seccomp:.*2" /proc/[0-9]*/status 2>/dev/null | head -5 | while read f; do
        pid=$(echo "$f" | grep -oP '/\K\d+')
        comm=$(cat /proc/$pid/comm 2>/dev/null || echo "?")
        echo "PID=$pid COMM=$comm SECCOMP=strict" >> "$KERNEL_CONFIG_FILE"
    done
    echo "" >> "$KERNEL_CONFIG_FILE"

    echo "--- 文件描述符使用 Top5 ---" >> "$KERNEL_CONFIG_FILE"
    for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$' | head -200); do
        if [ -d "/proc/$pid/fd" ]; then
            comm=$(cat /proc/$pid/comm 2>/dev/null || echo "?")
            count=$(ls -1 /proc/$pid/fd 2>/dev/null | wc -l)
            echo "$pid $comm $count"
        fi
    done 2>/dev/null | sort -t' ' -k3 -rn | head -5 >> "$KERNEL_CONFIG_FILE"
    echo "" >> "$KERNEL_CONFIG_FILE"

    echo "--- 关键系统服务 PID ---" >> "$KERNEL_CONFIG_FILE"
    for svc in systemd sshd dmsetup auditd dbus udevd chronyd crond; do
        if command -v pgrep &>/dev/null; then
            pids=$(pgrep -x "$svc" 2>/dev/null || echo "")
            [ -n "$pids" ] && echo "$svc: PID=$pids" >> "$KERNEL_CONFIG_FILE"
        fi
    done
    echo "" >> "$KERNEL_CONFIG_FILE"

    log_success "√ 内核深度诊断信息采集完成"
}

collect_pmu_info() {
    log_info "执行：PMU 远程访问与 HHA 分析"
    > "$PMU_INFO_FILE"
    echo "============================================================" >> "$PMU_INFO_FILE"
    echo "PMU 远程访问与 HHA 分析" >> "$PMU_INFO_FILE"
    echo "采集时间: $(date)" >> "$PMU_INFO_FILE"
    echo "============================================================" >> "$PMU_INFO_FILE"
    echo "" >> "$PMU_INFO_FILE"

    # ---- 1. HHA 设备检测 ----
    echo "=== 1. HHA 设备检测 ===" >> "$PMU_INFO_FILE"
    HHA_DEVICES=$(ls -d /sys/devices/hha* 2>/dev/null || true)
    if [ -n "$HHA_DEVICES" ]; then
        echo "$HHA_DEVICES" >> "$PMU_INFO_FILE"
    else
        echo "未检测到 HHA 设备" >> "$PMU_INFO_FILE"
    fi
    echo "" >> "$PMU_INFO_FILE"

    # ---- 2. PMU 事件列表（rx_ops/rx_outer/rx_sccl/uncore） ----
    echo "=== 2. PMU 事件列表 (rx_ops/rx_outer/rx_sccl/uncore) ===" >> "$PMU_INFO_FILE"
    if command -v perf &>/dev/null; then
        set +o pipefail
        perf list 2>/dev/null | grep -iE -m 50 'hha|rx_ops|rx_outer|rx_sccl|uncore' >> "$PMU_INFO_FILE" 2>/dev/null || true
        set -o pipefail
    fi
    echo "" >> "$PMU_INFO_FILE"

    # ---- 3. perf stat 远程访问统计（使用原脚本的 DURATION 时长） ----
    echo "=== 3. perf stat 远程访问统计 (${DURATION}秒) ===" >> "$PMU_INFO_FILE"
    if command -v perf &>/dev/null; then
        RX_OPS_EVENT=$(perf list 2>/dev/null | grep -iE 'rx_ops' | head -1 | awk -F'[' '{print $1}' | awk '{print $1}')
        RX_OUTER_EVENT=$(perf list 2>/dev/null | grep -iE 'rx_outer' | head -1 | awk -F'[' '{print $1}' | awk '{print $1}')
        RX_SCCL_EVENT=$(perf list 2>/dev/null | grep -iE 'rx_sccl' | head -1 | awk -F'[' '{print $1}' | awk '{print $1}')

        if [ -n "$RX_OPS_EVENT" ] && [ -n "$RX_OUTER_EVENT" ] && [ -n "$RX_SCCL_EVENT" ]; then
            perf stat -e "$RX_OPS_EVENT" -e "$RX_OUTER_EVENT" -e "$RX_SCCL_EVENT" -a sleep "$DURATION" >>  "$PMU_INFO_FILE" 2>&1 
        else
            echo "未找到完整的 PMU 事件 (rx_ops/rx_outer/rx_sccl)" >> "$PMU_INFO_FILE"
        fi
    fi
    echo "" >> "$PMU_INFO_FILE"

    # ---- 4. 换算每秒速率与远程访问占比 ----
    echo "=== 4. 速率与远程访问占比 ===" >> "$PMU_INFO_FILE"
    if command -v perf &>/dev/null && [ -n "${RX_OPS_EVENT:-}" ]; then
        OPS_TOTAL=$(grep -E "$RX_OPS_EVENT" "$PMU_INFO_FILE" 2>/dev/null | grep -oE '[0-9,]+' | head -1 | tr -d ',' || echo "0")
        OUTER_TOTAL=$(grep -E "$RX_OUTER_EVENT" "$PMU_INFO_FILE" 2>/dev/null | grep -oE '[0-9,]+' | head -1 | tr -d ',' || echo "0")
        SCCL_TOTAL=$(grep -E "$RX_SCCL_EVENT" "$PMU_INFO_FILE" 2>/dev/null | grep -oE '[0-9,]+' | head -1 | tr -d ',' || echo "0")

        awk -v o="${OPS_TOTAL:-0}" -v x="${OUTER_TOTAL:-0}" -v s="${SCCL_TOTAL:-0}" -v d="$DURATION" \
            'BEGIN {
                if (d <= 0) d = 10
                rps = o / d
                pct = (o > 0) ? (x + s) / o * 100 : 0
                printf "ops_per_sec=%.0f remote_ratio=%.2f%%\n", rps, pct
            }' >> "$PMU_INFO_FILE"
    else
        echo "无法计算" >> "$PMU_INFO_FILE"
    fi
    echo "" >> "$PMU_INFO_FILE"

    # ---- 5. perf list 输出开头（快速预览） ----
    echo "=== 5. perf list 输出开头 ===" >> "$PMU_INFO_FILE"
    if command -v perf &>/dev/null; then
        set +o pipefail
        perf list 2>/dev/null | head -20 >> "$PMU_INFO_FILE" 2>/dev/null
        set -o pipefail
    fi
    echo "" >> "$PMU_INFO_FILE"

    log_success "√ PMU 远程访问分析完成"
}

collect_thread_poll() {
    log_info "执行：线程生命周期轮询 (${DURATION}s, 间隔${INTERVAL}s)"
    > "$PROCESS_DETAIL_INFO_FILE"
    echo "============================================================" >> "$PROCESS_DETAIL_INFO_FILE"
    echo "线程生命周期轮询采集" >> "$PROCESS_DETAIL_INFO_FILE"
    echo "采集时长: ${DURATION}s, 采样间隔: ${INTERVAL}s" >> "$PROCESS_DETAIL_INFO_FILE"
    echo "============================================================" >> "$PROCESS_DETAIL_INFO_FILE"
    echo "" >> "$PROCESS_DETAIL_INFO_FILE"

    local tmpd="${OUTPUT_DIR}/.thread_poll_tmp"
    mkdir -p "$tmpd"
    local event_log="$tmpd/events.log"
    > "$event_log"

    # 快照采集：遍历 /proc/*/task，记录 TID=xxx COMM=xxx MTIME=xxx
    collect_snapshot() {
        local ts="$1"
        local snap="$tmpd/thread_ts_${ts}.txt"
        echo "=== TIMESTAMP $ts ===" > "$snap"
        for pid_dir in /proc/[0-9]*/task; do
            [ -d "$pid_dir" ] || continue
            for tid_dir in "$pid_dir"/*; do
                [ -d "$tid_dir" ] || continue
                local tid=$(basename "$tid_dir")
                local comm=$(cat "$tid_dir/comm" 2>/dev/null || echo "?")
                local mtime=$(stat -c "%Y" "$tid_dir" 2>/dev/null || echo "0")
                echo "TID=$tid COMM=$comm MTIME=$mtime" >> "$snap"
            done
        done
        echo "$snap"
    }

    local round=0
    local start_ts=$(date +%s)

    while [ $(( $(date +%s) - start_ts )) -lt "$DURATION" ]; do
        round=$((round + 1))
        local current_ts=$(date +%s)
        local snap_file=$(collect_snapshot "$current_ts")
        local thread_count=$(grep -c '^TID=' "$snap_file" 2>/dev/null || echo 0)
        log_info "线程轮询 第${round}轮: $thread_count 线程"

        # 提取当前 TID 和 mtime
        local current_tids="$tmpd/current_tids.txt"
        awk -F'[= ]' '/^TID=/{print $2" "$6}' "$snap_file" > "$current_tids"

        if [ "$round" -gt 1 ]; then
            local prev_tids="$tmpd/prev_tids.txt"
            # 检测退出线程
            while read -r prev_tid prev_mtime; do
                local new_mtime=$(awk -v tid="$prev_tid" '$1 == tid {print $2}' "$current_tids")
                [ -z "$new_mtime" ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] THREAD_EXIT TID=$prev_tid" >> "$event_log"
            done < "$prev_tids"
            # 检测新建线程
            while read -r cur_tid cur_mtime; do
                local old_mtime=$(awk -v tid="$cur_tid" '$1 == tid {print $2}' "$prev_tids")
                [ -z "$old_mtime" ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] THREAD_CREATE TID=$cur_tid" >> "$event_log"
            done < "$current_tids"
        fi

        cp "$current_tids" "$tmpd/prev_tids.txt"

        if [ $(( $(date +%s) - start_ts )) -lt "$DURATION" ]; then
            sleep "$INTERVAL"
        fi
    done

    # 汇总统计
    local total_creates=$(grep -c "THREAD_CREATE" "$event_log" 2>/dev/null || echo 0)
    local total_exits=$(grep -c "THREAD_EXIT" "$event_log" 2>/dev/null || echo 0)
    {
        echo "=== 轮询统计 ==="
        echo "采样轮次: $round"
        echo "线程创建事件: $total_creates 次"
        echo "线程销毁事件: $total_exits 次"
        echo ""
        echo "--- 线程创建事件 (前50条) ---"
        grep "THREAD_CREATE" "$event_log" 2>/dev/null | head -50
        echo ""
        echo "--- 线程销毁事件 (前50条) ---"
        grep "THREAD_EXIT" "$event_log" 2>/dev/null | head -50
        echo ""
        echo "--- 当前线程总数 ---"
        if [ -f "$current_tids" ]; then
            wc -l < "$current_tids"
        else
            echo "无法获取"
        fi
    } >> "$PROCESS_DETAIL_INFO_FILE"

    rm -rf "$tmpd"
    log_success "√ 线程生命周期轮询完成"
}

collect_process_detail_info() {
    log_info "执行：进程/线程详细信息采集"
    > "$PROCESS_DETAIL_INFO_FILE"
    {
        echo "============================================================"
        echo "进程/线程详细信息采集"
        echo "采集时间: $(date)"
        echo "============================================================"
        echo ""

        echo "--- 系统整体进程/线程数 ---"
        echo "进程总数: $(ps -e --no-headers 2>/dev/null | wc -l)"
        echo "线程总数: $(ps -eLf --no-headers 2>/dev/null | wc -l)"
        echo ""

        echo "=== 进程状态分布 ==="
        ps -eo stat --no-headers 2>/dev/null | sed 's/\(.\).*/\1/' | sort | uniq -c | sort -rn
        echo ""

        if command -v pidstat &>/dev/null; then
            echo "=== pidstat CPU 采样 (${DURATION}秒) ==="
            pidstat -u 1 "$DURATION" 2>/dev/null || echo "pidstat -u 失败"
            echo ""

            echo "=== pidstat 内存快照 (1秒) ==="
            pidstat -r 1 1 2>/dev/null || echo "pidstat -r 失败"
            echo ""

            echo "=== pidstat I/O 快照 (1秒) ==="
            pidstat -d 1 1 2>/dev/null || echo "pidstat -d 失败"
            echo ""

            echo "=== 线程级 CPU 统计 (pidstat -t -u 1 3) ==="
            pidstat -t -u 1 3 2>/dev/null || echo "线程级 pidstat 不支持"
            echo ""
        fi

        echo "=== 线程最多的进程 (Top 10) ==="
        ps -eo pid,comm,nlwp --sort=-nlwp 2>/dev/null | head -11
        echo ""

        echo "=== Top CPU 进程线程详情 ==="
        TOP_PIDS=$(ps -eo pid --sort=-%cpu --no-headers 2>/dev/null | head -5 | tr '\n' ' ')
        for pid in $TOP_PIDS; do
            if [ -d "/proc/$pid/task" ]; then
                comm=$(cat "/proc/$pid/comm" 2>/dev/null || echo "?")
                thread_count=$(ls "/proc/$pid/task" 2>/dev/null | wc -l)
                echo "PID=$pid ($comm): $thread_count 线程"
                echo "TID 列表 (前20):"
                ls "/proc/$pid/task/" 2>/dev/null | head -20
                echo ""
            fi
        done

        echo "=== /proc/schedstat (前20行) ==="
        head -20 /proc/schedstat 2>/dev/null || echo "不可用"
        echo ""

        echo "=== 系统 PID/线程限制 ==="
        cat /proc/sys/kernel/pid_max 2>/dev/null | awk '{print "pid_max: " $1}' || echo "pid_max: 不可用"
        cat /proc/sys/kernel/threads-max 2>/dev/null | awk '{print "threads-max: " $1}' || echo "threads-max: 不可用"
        echo ""

        echo "=== 关键进程检查 ==="
        pgrep -a redis-server 2>/dev/null || echo "redis-server 未运行"
        echo ""
    } >> "$PROCESS_DETAIL_INFO_FILE"

    collect_thread_poll

    log_success "√ 进程/线程详细信息采集完成"
}

collect_system_detail_info() {
    log_info "执行：系统详细信息采集"
    > "$SYSTEM_DETAIL_INFO_FILE"
    {
        echo "============================================================"
        echo "系统详细信息"
        echo "采集时间: $(date)"
        echo "============================================================"
        echo ""

        # ---- 系统概况补充 ----
        echo "=== 系统概况补充 ==="
        echo "--- 启动时间 ---"
        uptime 2>/dev/null || echo "无法获取"
        echo ""

        echo "--- 虚拟化检测 ---"
        if command -v systemd-detect-virt &>/dev/null; then
            VIRT=$(systemd-detect-virt --vm 2>/dev/null || echo "none")
            if [ "$VIRT" = "none" ]; then
                echo "physical"
            else
                echo "vm ($VIRT)"
            fi
        else
            if [ -f /sys/class/dmi/id/product_name ]; then
                PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "unknown")
                case "$PRODUCT" in
                    *KVM*|*QEMU*|*VMware*|*VirtualBox*|*Xen*)
                        echo "vm ($PRODUCT)" ;;
                    *)
                        echo "physical (product: $PRODUCT)" ;;
                esac
            else
                echo "unknown"
            fi
        fi
        echo ""

        echo "--- 当前用户 ---"
        echo "用户: $(whoami), UID: $(id -u), root: $(if [ "$(id -u)" -eq 0 ]; then echo yes; else echo no; fi)"
        echo ""

        # ---- sar 多维度实时采集 ----
        echo "=== sar 实时采集 (${DURATION}次, 间隔${INTERVAL}s) ==="
        if command -v sar &>/dev/null; then
            local sar_tmp="${OUTPUT_DIR}/.sar_tmp"
            mkdir -p "$sar_tmp"
            local sar_pids=()

            # 定义要采集的 sar 类别（排除已采集的 DEV/EDEV）
            declare -A SAR_MAP=(
                ["cpu"]="-u ${INTERVAL} ${DURATION}"
                ["cpu_all"]="-P ALL ${INTERVAL} ${DURATION}"
                ["memory"]="-r ${INTERVAL} ${DURATION}"
                ["swap"]="-S ${INTERVAL} ${DURATION}"
                ["paging"]="-B ${INTERVAL} ${DURATION}"
                ["io"]="-b ${INTERVAL} ${DURATION}"
                ["sock"]="-n SOCK ${INTERVAL} ${DURATION}"
                ["load"]="-q ${INTERVAL} ${DURATION}"
                ["ctxsw"]="-w ${INTERVAL} ${DURATION}"
                ["task"]="-y ${INTERVAL} ${DURATION}"
                ["hugepages"]="-H ${INTERVAL} ${DURATION}"
                ["intr"]="-I SUM ${INTERVAL} ${DURATION}"
            )

            for name in "${!SAR_MAP[@]}"; do
                (
                    sar ${SAR_MAP[$name]} 2>/dev/null > "$sar_tmp/$name" || true
                ) &
                sar_pids+=($!)
            done

            for pid in "${sar_pids[@]}"; do
                wait "$pid" 2>/dev/null || true
            done

            for name in "${!SAR_MAP[@]}"; do
                echo "--- sar ${name} ---"
                if [ -s "$sar_tmp/$name" ]; then
                    cat "$sar_tmp/$name"
                else
                    echo "  (无数据)"
                fi
                echo ""
            done

            rm -rf "$sar_tmp"
        fi

        # ---- sadf 历史数据 ----
        echo "=== sadf 历史数据提取 ==="
        local sadf_day=$(date '+%d')
        local sadf_file="/var/log/sa/sa${sadf_day}"
        if command -v sadf &>/dev/null && [ -f "$sadf_file" ]; then
            echo "--- CPU 历史 (前3行) ---"
            sadf -d "$sadf_file" -- -u 2>/dev/null | head -3 || echo "无数据"
            echo ""
            echo "--- 内存历史 (前3行) ---"
            sadf -d "$sadf_file" -- -r 2>/dev/null | head -3 || echo "无数据"
            echo ""
            echo "--- /var/log/sa 今日文件 ---"
            find /var/log/sa -name "sa*" -mtime -1 2>/dev/null || echo "无"
        fi
        echo ""

        # ---- PSI 补充（cpu, io） ----
        echo "=== PSI 压力指标补充 ==="
        echo "--- /proc/pressure/cpu ---"
        cat /proc/pressure/cpu 2>/dev/null || echo "不可用"
        echo ""
        echo "--- /proc/pressure/io ---"
        cat /proc/pressure/io 2>/dev/null || echo "不可用"
        echo ""
    } >> "$SYSTEM_DETAIL_INFO_FILE"

    log_success "√ 系统详细信息采集完成"
}

collect_container_info() {
    log_info "执行：容器资源监控采集"
    > "$CONTAINER_FILE"
    {
        echo "============================================================"
        echo "容器资源监控采集"
        echo "采集时间: $(date)"
        echo "Cgroup 版本检测中..."
        echo "============================================================"
        echo ""

        # ---------- cgroup 检测 ----------
        detect_cgroup_version() {
            if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
                echo "v2"
            elif [ -f "/sys/fs/cgroup/unified/cgroup.controllers" ]; then
                echo "v2_unified_mount"
            else
                echo "v1"
            fi
        }
        get_cgroup_root() {
            if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
                echo "/sys/fs/cgroup"
            elif [ -f "/sys/fs/cgroup/unified/cgroup.controllers" ]; then
                echo "/sys/fs/cgroup/unified"
            else
                echo ""
            fi
        }
        CGROUP_VER=$(detect_cgroup_version)
        CGROUP_V2_ROOT=$(get_cgroup_root)
        echo "Cgroup 版本: $CGROUP_VER"
        [ -n "$CGROUP_V2_ROOT" ] && echo "Cgroup v2 根: $CGROUP_V2_ROOT"
        echo ""

        # ---------- 容器 ID 提取 ----------
        extract_container_id() {
            local basename="$1"
            local name="${basename%.scope}"
            if [[ "$name" == docker-* ]]; then
                name="${name#docker-}"
            elif [[ "$name" == containerd-* ]]; then
                name="${name#containerd-}"
            elif [[ "$name" == cri-containerd-* ]]; then
                name="${name#cri-containerd-}"
            elif [[ "$name" == libpod-* ]]; then
                name="${name#libpod-}"
            fi
            [ -n "$name" ] && echo "$name" || echo "$basename"
        }

        # ---------- cgroup 路径查找 ----------
        get_cgroup_path() {
            local subsys="$1"
            local cid="$2"
            local path
            if [ -n "$CGROUP_V2_ROOT" ]; then
                for scope_dir in \
                    "${CGROUP_V2_ROOT}/system.slice/${cid}" \
                    "${CGROUP_V2_ROOT}/kubepods.slice"/*/"${cid}"; do
                    if [ -d "$scope_dir" ]; then
                        echo "$scope_dir"
                        return 0
                    fi
                done
                while IFS= read -r d; do
                    if [ -d "$d" ] && [ "$(basename "$d")" = "$cid" ]; then
                        echo "$d"
                        return 0
                    fi
                done < <(find "${CGROUP_V2_ROOT}/kubepods.slice" -type d -name "$cid" 2>/dev/null)
                return 0
            fi
            local base="/sys/fs/cgroup/${subsys}"
            [ -d "$base" ] || return 0
            for path in \
                "${base}/docker/${cid}" \
                "${base}/system.slice/${cid}" \
                "${base}/kubepods/${cid}" \
                "${base}/kubepods.slice/${cid}" \
                "${base}/kubepods.slice/"*"/${cid}"; do
                if [ -d "$path" ]; then
                    echo "$path"
                    return 0
                fi
            done
            if [ -d "${base}/kubepods" ]; then
                while IFS= read -r d; do
                    if [ -d "$d" ] && [ "$(basename "$d")" = "$cid" ]; then
                        echo "$d"
                        return 0
                    fi
                done < <(find "${base}/kubepods" -mindepth 2 -maxdepth 4 -type d -name "$cid" 2>/dev/null)
            fi
            return 0
        }

        # ---------- 容器发现 ----------
        echo "=== 容器发现 ==="
        CONTAINER_IDS=()
        discover_containers() {
            local cids=()
            if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
                local base="$CGROUP_V2_ROOT"
                for scope in "$base"/system.slice/docker-*.scope \
                             "$base"/system.slice/containerd-*.scope \
                             "$base"/system.slice/libpod-*.scope; do
                    [ -d "$scope" ] || continue
                    cids+=("$(basename "$scope")")
                done
                while IFS= read -r d; do
                    [ -d "$d" ] || continue
                    cids+=("$(basename "$d")")
                done < <(find "$base/kubepods.slice" -name "*.scope" -type d 2>/dev/null)
            else
                for subsys in cpu blkio memory; do
                    local base="/sys/fs/cgroup/$subsys"
                    [ -d "$base" ] || continue
                    if [ -d "$base/docker" ]; then
                        for d in "$base/docker"/*/; do
                            [ -d "$d" ] || continue
                            cids+=("$(basename "$d")")
                        done
                    fi
                    for scope in "$base"/system.slice/docker-*.scope \
                                 "$base"/system.slice/containerd-*.scope \
                                 "$base"/system.slice/libpod-*.scope; do
                        [ -d "$scope" ] || continue
                        cids+=("$(basename "$scope")")
                    done
                    if [ -d "$base/kubepods" ]; then
                        while IFS= read -r d; do
                            [ -d "$d" ] || continue
                            cids+=("$(basename "$d")")
                        done < <(find "$base/kubepods" -mindepth 2 -maxdepth 4 -type d 2>/dev/null)
                    fi
                    for scope in "$base"/kubepods.slice/*.slice/*.scope \
                                 "$base"/kubepods.slice/*.scope; do
                        [ -d "$scope" ] || continue
                        cids+=("$(basename "$scope")")
                    done
                done
            fi
            printf '%s\n' "${cids[@]}" | sort -u
        }

        while IFS= read -r cid; do
            [ -n "$cid" ] && CONTAINER_IDS+=("$cid")
        done < <(discover_containers)

        if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
            docker_ids=$(docker ps --no-trunc -q 2>/dev/null || true)
            for dcid in $docker_ids; do
                FOUND=0
                for cid in "${CONTAINER_IDS[@]}"; do
                    pure_cid=$(extract_container_id "$cid")
                    if [ "$pure_cid" = "$dcid" ]; then
                        FOUND=1
                        break
                    fi
                done
                if [ "$FOUND" -eq 0 ]; then
                    possible_scope="docker-${dcid}.scope"
                    path_found=0
                    for subsys in cpu memory blkio; do
                        if [ -d "/sys/fs/cgroup/${subsys}/system.slice/${possible_scope}" ] || \
                           [ -d "/sys/fs/cgroup/${subsys}/docker/${dcid}" ]; then
                            path_found=1
                            break
                        fi
                    done
                    if [ "$path_found" -eq 0 ] && [ -n "$CGROUP_V2_ROOT" ]; then
                        if [ -d "${CGROUP_V2_ROOT}/system.slice/${possible_scope}" ]; then
                            path_found=1
                        fi
                    fi
                    CONTAINER_IDS+=("$possible_scope")
                fi
            done
        fi

        if [ ${#CONTAINER_IDS[@]} -gt 0 ]; then
            echo "发现 ${#CONTAINER_IDS[@]} 个容器"
            printf '%s\n' "${CONTAINER_IDS[@]}"
        else
            echo "未发现运行中的容器"
        fi
        echo ""

        # ---------- 宿主机 /proc/stat 参考 ----------
        echo "## 宿主机 /proc/stat (cpu 行)"
        cat /proc/stat | grep '^cpu '
        echo ""

        # ---------- 逐容器详细信息 ----------
        for CID in "${CONTAINER_IDS[@]}"; do
            echo "===== 容器: $CID ====="
            PURE_ID=$(extract_container_id "$CID")
            [ "$PURE_ID" != "$CID" ] && echo "（纯容器 ID: $PURE_ID）"

            CGROUP_CPU_PATH=$(get_cgroup_path cpu "$CID")
            CGROUP_MEM_PATH=$(get_cgroup_path memory "$CID")
            CGROUP_BLKIO_PATH=$(get_cgroup_path blkio "$CID")
            CGROUP_CPUSET_PATH=$(get_cgroup_path cpuset "$CID")
            CGROUP_CPUACCT_PATH=$(get_cgroup_path cpuacct "$CID")  # v1 only

            # CPU 限额
            if [ -n "$CGROUP_CPU_PATH" ]; then
                echo "## CPU 限额"
                if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
                    if [ -f "$CGROUP_CPU_PATH/cpu.max" ]; then
                        read max period < "$CGROUP_CPU_PATH/cpu.max"
                        echo "  cpu.max = $max $period"
                        if [ "$max" != "max" ] && [ "$period" -gt 0 ] 2>/dev/null; then
                            cpus=$(awk -v m="$max" -v p="$period" 'BEGIN { printf "%.2f", m/p }')
                            echo "  可用 CPU 数: $cpus"
                        else
                            echo "  可用 CPU 数: 无限制"
                        fi
                    fi
                    [ -f "$CGROUP_CPU_PATH/cpu.weight" ] && echo "  cpu.weight = $(cat "$CGROUP_CPU_PATH/cpu.weight")"
                else
                    for f in cpu.cfs_period_us cpu.cfs_quota_us cpu.cfs_burst_us cpu.shares cpu.stat; do
                        [ -f "$CGROUP_CPU_PATH/$f" ] && echo "  $f = $(cat "$CGROUP_CPU_PATH/$f")"
                    done
                    [ -f "$CGROUP_CPU_PATH/cpu.soft_domain" ] && echo "  cpu.soft_domain = $(cat "$CGROUP_CPU_PATH/cpu.soft_domain")"
                    if [ -f "$CGROUP_CPU_PATH/cpu.cfs_period_us" ] && [ -f "$CGROUP_CPU_PATH/cpu.cfs_quota_us" ]; then
                        period=$(cat "$CGROUP_CPU_PATH/cpu.cfs_period_us")
                        quota=$(cat "$CGROUP_CPU_PATH/cpu.cfs_quota_us")
                        if [ "$quota" -gt 0 ] 2>/dev/null; then
                            cpus=$(awk -v q="$quota" -v p="$period" 'BEGIN { if (p>0) printf "%.2f", q/p; else print "无限制" }')
                            echo "  可用 CPU 数: $cpus"
                        else
                            echo "  可用 CPU 数: 无限制 (quota=-1)"
                        fi
                    fi
                fi
            else
                echo "## CPU 限额 — 未找到 cgroup 路径"
            fi
            echo ""

            # CPU 累计使用
            if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
                if [ -n "$CGROUP_CPU_PATH" ] && [ -f "$CGROUP_CPU_PATH/cpu.stat" ]; then
                    echo "## CPU 累计使用 (cpu.stat)"
                    usage_usec=$(awk '/^usage_usec /{print $2}' "$CGROUP_CPU_PATH/cpu.stat" 2>/dev/null || true)
                    if [ -n "$usage_usec" ]; then
                        usage_ns=$(( usage_usec * 1000 ))
                        usage_s=$(awk -v ns="$usage_ns" 'BEGIN { printf "%.3f", ns/1000000000 }')
                        echo "  usage_usec = $usage_usec us  (≈ $usage_s s)"
                    fi
                    cat "$CGROUP_CPU_PATH/cpu.stat" 2>/dev/null || true
                fi
            else
                if [ -n "$CGROUP_CPUACCT_PATH" ]; then
                    echo "## CPU 累计使用 (cpuacct)"
                    if [ -f "$CGROUP_CPUACCT_PATH/cpuacct.usage" ]; then
                        USAGE_NS=$(cat "$CGROUP_CPUACCT_PATH/cpuacct.usage" 2>/dev/null || echo 0)
                        USAGE_S=$(awk -v ns="$USAGE_NS" 'BEGIN { printf "%.3f", ns/1000000000 }')
                        echo "  cpuacct.usage = $USAGE_NS ns ($USAGE_S s)"
                    fi
                    [ -f "$CGROUP_CPUACCT_PATH/cpuacct.usage_percpu" ] && echo "  usage_percpu (ns): $(cat "$CGROUP_CPUACCT_PATH/cpuacct.usage_percpu")"
                fi
            fi
            echo ""

            # NUMA/CPU 亲和性
            if [ -n "$CGROUP_CPUSET_PATH" ]; then
                echo "## NUMA/CPU 亲和性"
                if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
                    for f in cpuset.cpus cpuset.mems cpuset.cpus.effective cpuset.mems.effective; do
                        [ -f "$CGROUP_CPUSET_PATH/$f" ] && echo "  $f = $(cat "$CGROUP_CPUSET_PATH/$f")"
                    done
                else
                    for f in cpuset.cpus cpuset.mems cpuset.cpu_exclusive cpuset.mem_exclusive cpuset.memory_migrate cpuset.sched_relax_domain_level; do
                        [ -f "$CGROUP_CPUSET_PATH/$f" ] && echo "  $f = $(cat "$CGROUP_CPUSET_PATH/$f")"
                    done
                fi
            fi
            echo ""

            # 内存配置与使用
            if [ -n "$CGROUP_MEM_PATH" ]; then
                echo "## 内存配置与使用"
                if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
                    [ -f "$CGROUP_MEM_PATH/memory.max" ] && echo "  memory.max = $(cat "$CGROUP_MEM_PATH/memory.max")"
                    if [ -f "$CGROUP_MEM_PATH/memory.current" ]; then
                        usage=$(cat "$CGROUP_MEM_PATH/memory.current")
                        echo "  memory.current = $usage"
                        limit=$(cat "$CGROUP_MEM_PATH/memory.max" 2>/dev/null || echo "max")
                        if [ "$limit" != "max" ] && [ "$limit" -gt 0 ] 2>/dev/null; then
                            LIMIT_GB=$(awk -v l="$limit" 'BEGIN { printf "%.2f", l/1073741824 }')
                            USAGE_GB=$(awk -v u="$usage" 'BEGIN { printf "%.2f", u/1073741824 }')
                            echo "  内存限额: $LIMIT_GB GB, 使用: $USAGE_GB GB"
                        else
                            echo "  内存限额: 无限制"
                        fi
                    fi
                    [ -f "$CGROUP_MEM_PATH/memory.stat" ] && { echo "  memory.stat (前5行):"; head -5 "$CGROUP_MEM_PATH/memory.stat"; }
                else
                    for f in memory.limit_in_bytes memory.usage_in_bytes memory.max_usage_in_bytes memory.stat memory.kmem.usage_in_bytes memory.kmem.limit_in_bytes memory.oom_control; do
                        [ -f "$CGROUP_MEM_PATH/$f" ] && echo "  $f = $(cat "$CGROUP_MEM_PATH/$f" | head -5)"
                    done
                    if [ -f "$CGROUP_MEM_PATH/memory.limit_in_bytes" ] && [ -f "$CGROUP_MEM_PATH/memory.usage_in_bytes" ]; then
                        LIMIT=$(cat "$CGROUP_MEM_PATH/memory.limit_in_bytes")
                        USAGE=$(cat "$CGROUP_MEM_PATH/memory.usage_in_bytes")
                        if [ "$LIMIT" -gt 0 ] 2>/dev/null && [ "$LIMIT" != "9223372036854771712" ]; then
                            LIMIT_GB=$(awk -v l="$LIMIT" 'BEGIN { printf "%.2f", l/1073741824 }')
                            USAGE_GB=$(awk -v u="$USAGE" 'BEGIN { printf "%.2f", u/1073741824 }')
                            echo "  内存限额: $LIMIT_GB GB, 使用: $USAGE_GB GB"
                        else
                            echo "  内存限额: 无限制"
                        fi
                    fi
                fi
            fi
            echo ""

            # blkio 限速
            if [ -n "$CGROUP_BLKIO_PATH" ]; then
                echo "## blkio 限速"
                if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
                    [ -f "$CGROUP_BLKIO_PATH/io.max" ] && echo "  io.max = $(cat "$CGROUP_BLKIO_PATH/io.max")"
                else
                    for f in blkio.throttle.read_bps_device blkio.throttle.write_bps_device blkio.throttle.read_iops_device blkio.throttle.write_iops_device blkio.io_service_bytes blkio.io_serviced blkio.weight; do
                        [ -f "$CGROUP_BLKIO_PATH/$f" ] && echo "  $f = $(cat "$CGROUP_BLKIO_PATH/$f" | head -5)"
                    done
                fi
            fi
            echo ""

            # 任务列表
            if [ -n "$CGROUP_CPU_PATH" ]; then
                tasks_file=""
                [ -f "$CGROUP_CPU_PATH/cgroup.threads" ] && tasks_file="$CGROUP_CPU_PATH/cgroup.threads"
                [ -z "$tasks_file" ] && [ -f "$CGROUP_CPU_PATH/tasks" ] && tasks_file="$CGROUP_CPU_PATH/tasks"
                if [ -n "$tasks_file" ]; then
                    TASK_COUNT=$(wc -l < "$tasks_file" 2>/dev/null || echo 0)
                    echo "## 任务列表"
                    echo "  线程总数: $TASK_COUNT"
                    echo "  前20个TID映射:"
                    head -20 "$tasks_file" 2>/dev/null | while read tid; do
                        comm=$(cat "/proc/$tid/comm" 2>/dev/null || echo "?")
                        tpid=$(awk '/^Tgid:/{print $2}' "/proc/$tid/status" 2>/dev/null || echo "?")
                        echo "    TID=$tid COMM=$comm PID=$tpid"
                    done || true
                fi
            fi
            echo ""
        done

        # ---------- Docker 元数据 ----------
        if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
            echo "## Docker Daemon 信息"
            docker info 2>/dev/null | grep -E "Server Version|Storage Driver|Cgroup Driver|Cgroup Version|Total Memory|Operating System" || true
            echo ""
            for CID in "${CONTAINER_IDS[@]}"; do
                PURE_ID=$(extract_container_id "$CID")
                echo "## 容器元数据 (ID: $PURE_ID)"
                if docker inspect "$PURE_ID" >/dev/null 2>&1; then
                    docker inspect "$PURE_ID" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)[0]
name = data.get('Name', '?').lstrip('/')
s = data.get('State', {})
print(f'Name: {name}')
print(f'Image: {data.get(\"Config\", {}).get(\"Image\", \"?\")}')
print(f'Status: {s.get(\"Status\", \"?\")}')
hc = data.get('HostConfig', {})
print(f'CpuQuota: {hc.get(\"CpuQuota\", \"N/A\")}')
print(f'CpuPeriod: {hc.get(\"CpuPeriod\", \"N/A\")}')
print(f'CpuShares: {hc.get(\"CpuShares\", \"N/A\")}')
print(f'NanoCpus: {hc.get(\"NanoCpus\", \"N/A\")}')
print(f'CpusetCpus: {hc.get(\"CpusetCpus\", \"N/A\")}')
print(f'Memory: {hc.get(\"Memory\", \"N/A\")}')
" || {
                        echo "python 解析失败"
                        docker inspect "$PURE_ID" >> "$CONTAINER_FILE" 2>/dev/null || true
                    }
                fi
                echo ""
            done
        fi

        # ---------- 容器 CPU 多采样观测 ----------
        if [ ${#CONTAINER_IDS[@]} -gt 0 ]; then
            OBS_WINDOW=${DURATION:-10}
            SAMP_INT=${INTERVAL:-2}
            NUM_SAMPLES=$(( OBS_WINDOW / SAMP_INT + 1 ))
            [ "$NUM_SAMPLES" -lt 2 ] && NUM_SAMPLES=2

            echo "## 容器 CPU 多采样观测 (${OBS_WINDOW}s, ${SAMP_INT}s 间隔)"
            for ((i=1; i<=NUM_SAMPLES; i++)); do
                TS_EPOCH=$(date +%s.%N)
                echo "=== SAMPLE $i ==="
                echo "=== TIMESTAMP $TS_EPOCH ==="
                for CID in "${CONTAINER_IDS[@]}"; do
                    CGROUP_CPU_PATH=$(get_cgroup_path cpu "$CID")
                    if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
                        USAGE_NS="0"
                        PERIOD_US="0"
                        QUOTA_US="0"
                        SOFT_QUOTA=0
                        if [ -n "$CGROUP_CPU_PATH" ]; then
                            if [ -f "$CGROUP_CPU_PATH/cpu.max" ]; then
                                read max period < "$CGROUP_CPU_PATH/cpu.max" 2>/dev/null || true
                                PERIOD_US="$period"
                                QUOTA_US="$max"
                                if [ "$max" != "max" ] && [ "$period" -gt 0 ] 2>/dev/null; then
                                    if [ -f "$CGROUP_CPU_PATH/cpu.max.burst" ]; then
                                        BURST_US=$(cat "$CGROUP_CPU_PATH/cpu.max.burst" 2>/dev/null || echo 0)
                                        [ -n "$BURST_US" ] && [ "$BURST_US" -gt 0 ] 2>/dev/null && SOFT_QUOTA=1
                                    fi
                                fi
                            fi
                            if [ -f "$CGROUP_CPU_PATH/cpu.stat" ]; then
                                usec=$(awk '/^usage_usec /{print $2}' "$CGROUP_CPU_PATH/cpu.stat" 2>/dev/null || echo 0)
                                [ -n "$usec" ] && USAGE_NS=$(( usec * 1000 ))
                            fi
                        fi
                    else
                        CGROUP_CPUACCT_PATH=$(get_cgroup_path cpuacct "$CID")
                        PERIOD_US=""
                        QUOTA_US=""
                        USAGE_NS=""
                        SOFT_QUOTA=0
                        if [ -n "$CGROUP_CPU_PATH" ]; then
                            [ -f "$CGROUP_CPU_PATH/cpu.cfs_period_us" ] && PERIOD_US=$(cat "$CGROUP_CPU_PATH/cpu.cfs_period_us")
                            [ -f "$CGROUP_CPU_PATH/cpu.cfs_quota_us" ] && QUOTA_US=$(cat "$CGROUP_CPU_PATH/cpu.cfs_quota_us")
                            if [ -f "$CGROUP_CPU_PATH/cpu.soft_quota" ]; then
                                SOFT_QUOTA=$(cat "$CGROUP_CPU_PATH/cpu.soft_quota")
                            elif [ -f "$CGROUP_CPU_PATH/cpu.cfs_burst_us" ]; then
                                BURST_US=$(cat "$CGROUP_CPU_PATH/cpu.cfs_burst_us" 2>/dev/null || echo 0)
                                [ -n "$BURST_US" ] && [ "$BURST_US" -gt 0 ] 2>/dev/null && SOFT_QUOTA=1
                            fi
                        fi
                        if [ -n "$CGROUP_CPUACCT_PATH" ] && [ -f "$CGROUP_CPUACCT_PATH/cpuacct.usage" ]; then
                            USAGE_NS=$(cat "$CGROUP_CPUACCT_PATH/cpuacct.usage" 2>/dev/null || echo 0)
                        fi
                    fi
                    echo "--- CONTAINER ---"
                    echo "id=$CID"
                    echo "cfs_period_us=${PERIOD_US:-0}"
                    echo "cfs_quota_us=${QUOTA_US:-0}"
                    echo "cpuacct_usage=${USAGE_NS:-0}"
                    echo "soft_quota=$SOFT_QUOTA"
                    echo "timestamp=$TS_EPOCH"
                    echo "--- END CONTAINER ---"
                done
                echo ""
                if [ "$i" -lt "$NUM_SAMPLES" ]; then
                    sleep "$SAMP_INT"
                fi
            done
        fi
    } >> "$CONTAINER_FILE"

    log_success "√ 容器资源监控采集完成"
}

reports=(
    "devkit ksys数据报告:KSYS_FILE"
    "系统环境静态信息:STATIC_FILE"
    "全局资源瓶颈识别:BOTTLENECK_FILE"
    "顶级资源进程识别:TOP_PROC_FILE"
    "I/O Metrics 深度分析:IO_METRICS_FILE"
    "Lock Trace 深度分析:LOCK_TRACE_FILE"
    "Memory Metrics 深度分析:MEM_METRICS_FILE"
    "Network Metrics 深度分析:NET_METRICS_FILE"
    "Scheduler Trace 深度分析:SCHED_TRACE_FILE" 
    "CPU 深度信息采集:CPU_DETAIL_FILE"
    "内核深度诊断:KERNEL_CONFIG_FILE"
    "进程/线程详细信息:PROCESS_DETAIL_INFO_FILE"
    "系统详细信息:SYSTEM_DETAIL_INFO_FILE"
)

if [ ${ARCH_TARGET} = "aarch64" ];then
    reports+=(
        "devkit topdown数据报告:TOPDOWN_FILE"
        "devkit numafast数据报告:NUMAFAST_FILE"
        "devkit memory数据报告:MEMORY_FILE"
        "devkit hotspot数据报告:HOTSPOT_FILE"
        "devkit turbostat数据报告:TURBOSTAT_FILE"
        "devkit 健康度检查报告:KSPECT_FILE"
        "PMU 远程访问分析:PMU_INFO_FILE"
        "容器资源监控:CONTAINER_FILE"
    )
fi

# 条件添加
if [[ -n "$PIDS" ]]; then
    reports+=(
        "热点函数分析:HOTSPOT_ANALYSIS_FILE"
        "系统调用分析:SYSCALL_FILE"
        "微架构瓶颈分析:MICROARCH_FILE"
    )
fi

# 主函数
main() {
    # 解析参数
    parse_arguments "$@"
    
    # 如果仅执行前置检查
    if [[ "$CHECK_ONLY" = true ]]; then
        log_info "========================================"
        log_info "前置检查模式"
        log_info "========================================"
        echo ""
        
        # 检查权限
        check_root
        
        # 执行前置检查
        preflight_check
        local check_result=$?
        
        echo ""
        log_info "========================================"
        log_info "前置检查完成"
        log_info "========================================"
        
        if [[ $check_result -eq 0 ]]; then
            log_success "✓ 所有必需依赖已安装，可以开始数据采集"
            echo ""
            log_info "使用以下命令开始数据采集:"
            echo "  $0 -d <持续时间> [-p <进程ID>] [-c <采集项目>]"
            echo ""
            echo "示例:"
            echo "  $0 -d 10                  # 默认采集10秒"
            echo "  $0 -d 60 -p 1234          # 采集60秒，监控进程1234"
            exit 0
        else
            log_error "✗ 前置检查失败，请先安装缺失依赖"
            exit 1
        fi
    fi

    log_info "开始服务器数据采集..."
    log_info "阶段性步骤采集持续时间: ${DURATION}秒"
    if [[ -n "$PIDS" ]]; then
        log_info "监控进程: $PIDS"
    fi

    # 检查权限
    check_root

    # 创建输出文件头
    create_header
    check_commands

    # 第一阶段：基础数据采集
    for cmd in "${SELECTED_COMMANDS[@]}"; do
        $cmd
    done

    # 添加总结
    echo "==================== 采集总结 ===================="
    echo "数据采集完成时间: $(date)"
    echo "阶段性采集持续时间: ${DURATION}秒"
    if [[ -n "$PIDS" ]]; then
        echo "监控进程: $PIDS"
        IFS=',' read -ra pid_array <<< "$PIDS"
        for pid in "${pid_array[@]}"; do
            pid=$(echo "$pid" | xargs)  # 去除空格
            if ps -p "$pid" > /dev/null 2>&1; then
                echo "进程状态: 运行中 ($(ps -p $pid -o comm=))"
            else
                echo "进程状态: 已终止"
            fi
        done 
    fi
    echo "================================================"
    log_success "数据采集完成!"
    # 显示文件位置
    echo ""
    echo "采集完成！以下文件已生成："
    num=0
    for i in "${!reports[@]}"; do
        IFS=':' read -r desc var_name <<< "${reports[$i]}"
        file_path="${!var_name}"
        if [ -f "$file_path" ];then
            num=$((num + 1))
            echo "$num. $desc: $(pwd)/$file_path"
        fi
    done
    echo ""
    get_software
    echo ""
}

# 执行主函数
main "$@"

# 打包整个输出目录（仅数据采集模式）
if [[ "$CHECK_ONLY" = false ]] && [ -d "$OUTPUT_DIR" ]; then
    ARCHIVE_NAME="${OUTPUT_DIR}.tar.gz"
    log_info "正在打包输出目录为 ${ARCHIVE_NAME} ..."
    tar -czf "$ARCHIVE_NAME" "$OUTPUT_DIR"
    if [ $? -eq 0 ]; then
        log_success "打包完成: $(pwd)/${ARCHIVE_NAME}"
        log_info "打包文件大小: $(du -h "$ARCHIVE_NAME" | cut -f1)"
    else
        log_error "打包失败"
    fi
fi
