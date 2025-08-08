#!/usr/bin/env bash

# -------------------- 颜色定义 --------------------
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"
GRAY="\033[90m"

# -------------------- 日志输出函数 --------------------
log_info()     { echo -e "${GRAY}[$(date '+%F %T')]${RESET} ${CYAN}$1${RESET}"; }
log_success()  { echo -e "${GRAY}[$(date '+%F %T')]${RESET} ${GREEN}$1${RESET}"; }
log_warning()  { echo -e "${GRAY}[$(date '+%F %T')]${RESET} ${YELLOW}$1${RESET}"; }
log_error()    { echo -e "${GRAY}[$(date '+%F %T')]${RESET} ${RED}$1${RESET}"; }

# -------------------- 错误输出包装 --------------------
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

# -------------------- 环境变量 --------------------
SCRIPT_VERSION="${VERSION}"
USE_JUMP_HOST="${PLUGIN_USE_JUMP_HOST:-no}"
JUMP_SSH_HOST="${PLUGIN_JUMP_SSH_HOST:-}"
JUMP_SSH_USER="${PLUGIN_JUMP_SSH_USER:-}"
JUMP_SSH_PRIVATE_KEY="${PLUGIN_JUMP_SSH_PRIVATE_KEY:-}"
JUMP_SSH_PORT="${PLUGIN_JUMP_SSH_PORT:-22}"
SSH_PRIVATE_KEY="${PLUGIN_SSH_PRIVATE_KEY:-}"
SSH_HOST="${PLUGIN_SSH_HOST:-}"
SSH_USER="${PLUGIN_SSH_USER:-}"
SSH_PORT="${PLUGIN_SSH_PORT:-22}"
EXECUTE_REMOTE_SCRIPT="${PLUGIN_EXECUTE_REMOTE_SCRIPT:-no}"
COPY_SCRIPT="${PLUGIN_COPY_SCRIPT:-no}"
SOURCE_SCRIPT="${PLUGIN_SOURCE_SCRIPT:-}"
DEPLOY_SCRIPT="${PLUGIN_DEPLOY_SCRIPT:-}"
TRANSFER_FILES="${PLUGIN_TRANSFER_FILES:-yes}"
SOURCE_FILE_PATH="${PLUGIN_SOURCE_FILE_PATH:-}"
DESTINATION_PATH="${PLUGIN_DESTINATION_PATH:-}"
SERVICE_NAME="${PLUGIN_SERVICE_NAME:-}"
SERVICE_VERSION="${PLUGIN_SERVICE_VERSION:-}"

# -------------------- 基础函数 --------------------
check_param() {
  [ -z "$1" ] && log_error "Error: $2 is missing." && exit 1
}

ssh_init() {
  mkdir -p /root/.ssh && chmod 700 /root/.ssh
}

setup_ssh_key() {
  echo "$1" > "$2" && chmod 600 "$2" || {
    log_error "❌ Failed to create key file: $2"; exit 1;
  }
}

setup_ssh_config() {
  echo "$2 $1" >> /etc/hosts
  cat >>/root/.ssh/config <<END
Host $1
  HostName $2
  User $3
  Port ${5:-22}
  IdentityFile $4
  StrictHostKeyChecking no
  ServerAliveInterval 60
  ServerAliveCountMax 3
  $6
END
}

wrap_command() {
  echo "powershell -Command \"$1\""
}

check_ssh_connection() {
  for i in {1..3}; do
    run_with_error_log "ssh -o ConnectTimeout=30 remote \"echo ok > \$null\""
    [ $? -eq 0 ] && log_success "✅ SSH connection established." && return 0
    log_warning "SSH connection attempt $i failed."
    sleep 10
  done
  log_error "❌ SSH connection failed after 3 attempts." && exit 1
}

check_unsafe_path() {
  local level=$(echo "$1" | awk -F/ 'NF>=3 {print "/" $2 "/" $3}')
  case "$level" in
    /data/* | /opt/* | /home/* | /workspace/* | /app/* | /mnt/* | /var/www | /srv/* | /usr/local)
      ;;
    *) log_error "❌ Unsafe path: $level" && exit 1;;
  esac
}

set_owner() {
  local second_level=$(echo "$1" | awk -F/ 'NF>=3 {print "/" $2 "/" $3}')
  local cmd
  cmd=$(wrap_command "if (!(Test-Path '$second_level')) { New-Item -Path '$second_level' -ItemType Directory }")
  run_with_error_log "ssh remote \"$cmd\""
  run_with_error_log "ssh remote \"powershell -Command \"Set-Acl -Path '$second_level' -AclObject (Get-Acl '$second_level')\"\""
}

transfer_file() {
  local source="$1" destination="$2"
  check_unsafe_path "$destination"
  [[ -d "$source" ]] && isdir=true || isdir=false
  [[ "$destination" =~ /$ ]] && destination="$destination$(basename "$source")"
  local dest_dir=$(dirname "$destination")

  local mkdir_cmd
  mkdir_cmd=$(wrap_command "if (!(Test-Path '$dest_dir')) { New-Item -Path '$dest_dir' -ItemType Directory }")
  run_with_error_log "ssh remote \"$mkdir_cmd\""
  set_owner "$dest_dir"

  if [ "$isdir" == true ]; then
    run_with_error_log "scp -r \"$source\" remote:\"$destination\""
  else
    run_with_error_log "scp \"$source\" remote:\"$destination\""
  fi
  log_success "✅ Transferred $source to $destination"
}

execute_command() {
  run_with_error_log "ssh remote \"powershell -Command \"$1\"\""
}

execute_deployment() {
  local cmd="${DEPLOY_SCRIPT}"
  [[ -n "$SERVICE_NAME" && -n "$SERVICE_VERSION" ]] && cmd="$cmd $SERVICE_NAME $SERVICE_VERSION"
  cmd=$(wrap_command "$cmd")
  execute_command "$cmd"
}

main() {
  log_info "🔧 Script Version: ${SCRIPT_VERSION}"
  ssh_init

  if [ "$USE_JUMP_HOST" == "yes" ]; then
    check_param "$JUMP_SSH_HOST" "Jump SSH host"
    check_param "$JUMP_SSH_USER" "Jump SSH user"
    check_param "$JUMP_SSH_PRIVATE_KEY" "Jump SSH key"
    setup_ssh_key "$JUMP_SSH_PRIVATE_KEY" /root/.ssh/jump.key
    setup_ssh_key "$SSH_PRIVATE_KEY" /root/.ssh/remote.key
    setup_ssh_config "jump" "$JUMP_SSH_HOST" "$JUMP_SSH_USER" /root/.ssh/jump.key "$JUMP_SSH_PORT"
    setup_ssh_config "remote" "$SSH_HOST" "$SSH_USER" /root/.ssh/remote.key "$SSH_PORT" "ProxyJump jump"
  else
    setup_ssh_key "$SSH_PRIVATE_KEY" /root/.ssh/remote.key
    setup_ssh_config "remote" "$SSH_HOST" "$SSH_USER" /root/.ssh/remote.key "$SSH_PORT"
  fi

  chmod 600 /root/.ssh/config
  check_ssh_connection

  if [ "$TRANSFER_FILES" == "yes" ]; then
    check_param "$SOURCE_FILE_PATH" "Source file path"
    check_param "$DESTINATION_PATH" "Destination path"
    transfer_file "$SOURCE_FILE_PATH" "$DESTINATION_PATH"
  fi

  if [ "$EXECUTE_REMOTE_SCRIPT" == "yes" ]; then
    if [ "$COPY_SCRIPT" == "yes" ]; then
      check_param "$SOURCE_SCRIPT" "Source script"
      check_param "$DEPLOY_SCRIPT" "Deploy script"
      transfer_file "$SOURCE_SCRIPT" "$DEPLOY_SCRIPT"
    fi
    execute_deployment
  fi
}

main
