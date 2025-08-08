#!/usr/bin/env bash

# -------------------- 颜色定义：用于美化日志输出 --------------------
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"
GRAY="\033[90m"

# -------------------- 日志函数 --------------------
log_info()    { echo -e "${GRAY}[$(date '+%F %T')]${RESET} ${CYAN}$1${RESET}"; }
log_success() { echo -e "${GRAY}[$(date '+%F %T')]${RESET} ${GREEN}$1${RESET}"; }
log_warning() { echo -e "${GRAY}[$(date '+%F %T')]${RESET} ${YELLOW}$1${RESET}"; }
log_error()   { echo -e "${GRAY}[$(date '+%F %T')]${RESET} ${RED}$1${RESET}"; }

# -------------------- 错误日志捕获 --------------------
run_with_error_log() {
  local output
  if ! output=$(eval "$1" 2>&1); then
    while IFS= read -r line; do
      clean_line=$(echo "$line" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
      [[ -z "$clean_line" ]] && continue
      echo "$clean_line" | grep -q "Permanently added" && continue
      log_error "$clean_line"
    done <<< "$output"
    return 1
  fi
}

# -------------------- 判断是否是 Windows 主机 --------------------
is_windows_host() {
  ssh remote "ver" 2>/dev/null | grep -q "Windows"
}

# -------------------- 包装命令为 PowerShell --------------------
wrap_command() {
  local raw="$1"
  if is_windows_host; then
    echo "powershell -Command \"$raw\""
  else
    echo "$raw"
  fi
}

# -------------------- SSH 和 SCP 初始化 --------------------
ssh_init() {
  mkdir -p /root/.ssh && chmod 700 /root/.ssh
}
setup_ssh_key() {
  echo "$1" > "$2" && chmod 600 "$2"
  [ ! -f "$2" ] && { log_error "无法写入 SSH key 到 $2"; exit 1; }
}
setup_ssh_config() {
  echo "$2 $1" >> /etc/hosts
  cat >> /root/.ssh/config <<EOF
Host $1
  HostName $2
  User $3
  Port ${5:-22}
  IdentityFile $4
  StrictHostKeyChecking no
  ServerAliveInterval 60
  ServerAliveCountMax 3
  $6
EOF
  chmod 600 /root/.ssh/config
}

# -------------------- 核心 SSH 流程 --------------------
check_ssh_connection() {
  for i in {1..3}; do
    run_with_error_log "ssh -o ConnectTimeout=30 remote $(wrap_command 'echo SSH OK')"
    [ $? -eq 0 ] && { log_success "SSH 连接成功"; return 0; }
    log_warning "SSH 第 $i 次连接失败，10 秒后重试..." && sleep 10
  done
  log_error "SSH 无法连接（3次失败）" && exit 1
}

transfer_file() {
  src="$1"; dst="$2"
  is_win=false
  if is_windows_host; then
    dst="$(echo "$dst" | sed 's|:|\\:|')"
    is_win=true
  fi
  dest_dir=$(dirname "$dst")
  if [ "$is_win" = true ]; then
    run_with_error_log "ssh remote $(wrap_command \"if (!(Test-Path '$dest_dir')) { New-Item -Path '$dest_dir' -ItemType Directory }\")"
  else
    run_with_error_log "ssh remote \"sudo mkdir -p '$dest_dir'\""
  fi
  run_with_error_log "scp -r \"$src\" \"remote:$dst\""
  log_success "文件传输成功: $src -> $dst"
}

execute_command() {
  cmd=$(wrap_command "$1")
  ssh remote "$cmd" || { log_error "远程命令执行失败: $1"; exit 1; }
}

# -------------------- 参数校验 --------------------
check_param() { [ -z "$1" ] && log_error "$2 缺失" && exit 1; }

# -------------------- 主流程 --------------------
main() {
  log_info "SSH Deploy 脚本启动"

  # 参数读取
  check_param "$PLUGIN_SSH_HOST" "PLUGIN_SSH_HOST"
  check_param "$PLUGIN_SSH_USER" "PLUGIN_SSH_USER"
  check_param "$PLUGIN_SSH_PRIVATE_KEY" "PLUGIN_SSH_PRIVATE_KEY"

  ssh_init
  setup_ssh_key "$PLUGIN_SSH_PRIVATE_KEY" /root/.ssh/remote.key
  setup_ssh_config remote "$PLUGIN_SSH_HOST" "$PLUGIN_SSH_USER" /root/.ssh/remote.key "$PLUGIN_SSH_PORT" ""

  check_ssh_connection

  if [ "$PLUGIN_TRANSFER_FILES" = "yes" ]; then
    check_param "$PLUGIN_SOURCE_FILE_PATH" "PLUGIN_SOURCE_FILE_PATH"
    check_param "$PLUGIN_DESTINATION_PATH" "PLUGIN_DESTINATION_PATH"
    transfer_file "$PLUGIN_SOURCE_FILE_PATH" "$PLUGIN_DESTINATION_PATH"
  fi

  if [ "$PLUGIN_EXECUTE_REMOTE_SCRIPT" = "yes" ]; then
    if [ "$PLUGIN_COPY_SCRIPT" = "yes" ]; then
      check_param "$PLUGIN_SOURCE_SCRIPT" "PLUGIN_SOURCE_SCRIPT"
      check_param "$PLUGIN_DEPLOY_SCRIPT" "PLUGIN_DEPLOY_SCRIPT"
      transfer_file "$PLUGIN_SOURCE_SCRIPT" "$PLUGIN_DEPLOY_SCRIPT"
    fi
    execute_command "$PLUGIN_DEPLOY_SCRIPT $PLUGIN_SERVICE_NAME $PLUGIN_SERVICE_VERSION"
  fi

  log_success "脚本执行完成"
}

main
