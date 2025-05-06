#!/usr/bin/env bash

# -------------------- 颜色定义：用于美化日志输出 --------------------
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"
GRAY="\033[90m"

# -------------------- 日志函数 --------------------
log_info() {
  echo -e "${GRAY}[$(date '+%F %T')]${RESET} ${CYAN}$1${RESET}"
}

log_success() {
  echo -e "${GRAY}[$(date '+%F %T')]${RESET} ${GREEN}$1${RESET}"
}

log_warning() {
  echo -e "${GRAY}[$(date '+%F %T')]${RESET} ${YELLOW}$1${RESET}"
}

log_error() {
  echo -e "${GRAY}[$(date '+%F %T')]${RESET} ${RED}$1${RESET}"
}

# -------------------- 环境变量读取（CI 平台传入） --------------------
SCRIPT_VERSION="${VERSION}"
USE_SCREEN="${PLUGIN_USE_SCREEN:-no}"                       # 是否使用 screen 执行远程命令
USE_JUMP_HOST="${PLUGIN_USE_JUMP_HOST:-no}"                 # 是否使用跳板机
JUMP_SSH_HOST="${PLUGIN_JUMP_SSH_HOST:-}"                   # 跳板机 IP
JUMP_SSH_USER="${PLUGIN_JUMP_SSH_USER:-}"                   # 跳板机用户名
JUMP_SSH_PRIVATE_KEY="${PLUGIN_JUMP_SSH_PRIVATE_KEY:-}"     # 跳板机私钥
JUMP_SSH_PORT="${PLUGIN_JUMP_SSH_PORT:-22}"                 # 跳板机端口
SSH_PRIVATE_KEY="${PLUGIN_SSH_PRIVATE_KEY:-}"               # 目标主机私钥
SSH_HOST="${PLUGIN_SSH_HOST:-}"                             # 目标主机 IP
SSH_USER="${PLUGIN_SSH_USER:-}"                             # 目标主机用户名
SSH_PORT="${PLUGIN_SSH_PORT:-22}"                           # 目标主机端口
EXECUTE_REMOTE_SCRIPT="${PLUGIN_EXECUTE_REMOTE_SCRIPT:-no}" # 是否执行部署脚本
COPY_SCRIPT="${PLUGIN_COPY_SCRIPT:-no}"                     # 是否拷贝脚本到目标机器
SOURCE_SCRIPT="${PLUGIN_SOURCE_SCRIPT:-}"                   # 本地脚本路径
DEPLOY_SCRIPT="${PLUGIN_DEPLOY_SCRIPT:-}"                   # 目标机脚本路径
TRANSFER_FILES="${PLUGIN_TRANSFER_FILES:-yes}"              # 是否传输文件
SOURCE_FILE_PATH="${PLUGIN_SOURCE_FILE_PATH:-}"             # 本地文件路径
DESTINATION_PATH="${PLUGIN_DESTINATION_PATH:-}"             # 目标机路径
SERVICE_NAME="${PLUGIN_SERVICE_NAME:-}"                     # 服务名称
SERVICE_VERSION="${PLUGIN_SERVICE_VERSION:-}"               # 服务版本

# -------------------- 工具函数定义 --------------------

# 参数不能为空
check_param() {
  local param_value=$1
  local param_name=$2
  ##[ -z "$param_value" ] && log_error "Error: $param_name is missing."
    if [ -z "$param_value" ]; then
    log_error "Error: $param_name is missing."
    exit 1
    else
      log_info "$param_name is set to $param_value."
    fi
}

# 初始化 SSH 目录
ssh_init(){
  mkdir -p /root/.ssh/
  chmod 700 /root/.ssh/
}

# 写入 SSH 私钥文件
setup_ssh_key() {
  local ssh_key="$1"
  local key_path="$2"
  echo "${ssh_key}" > "${key_path}"
  chmod 600 "${key_path}" || { log_error "Error: Failed to set permissions for ${key_path}."; exit 1; }
  [ ! -f "${key_path}" ] && { log_error "Error: Failed to write SSH private key at ${key_path}."; exit 1; }
}

# 生成 SSH 配置（支持 ProxyJump）
setup_ssh_config() {
  local host_name="$1"
  local ssh_host="$2"
  local ssh_user="$3"
  local ssh_key="$4"
  local ssh_port="${5:-22}"
  local proxy_jump="$6"

  if ! grep -q "Host $host_name" /root/.ssh/config 2>/dev/null; then
  echo "${ssh_host} ${host_name}" >> /etc/hosts || log_error "❌ 无法写入 /etc/hosts"
    cat >>/root/.ssh/config <<END
Host ${host_name}
  HostName ${ssh_host}
  User ${ssh_user}
  Port ${ssh_port}
  IdentityFile ${ssh_key}
  StrictHostKeyChecking no
  ServerAliveInterval 60
  ServerAliveCountMax 3
  ${proxy_jump}
END
  fi
}

# 检查 SSH 是否能连接
check_ssh_connection() {
  local max_retries=3
  local retry_delay=10
  local attempt=1
  cat /root/.ssh/config
  while (( attempt <= max_retries )); do
    if ssh -o ConnectTimeout=30 remote "echo successful >/dev/null" 2>/dev/null; then
      log_success "SSH connection established."
      return 0
    else
      (( attempt++ ))
      sleep "$retry_delay"
    fi
  done

  log_error "Error: SSH connection failed after ${max_retries} attempts."
  exit 1
}

# 如果远程没有安装 screen，则尝试自动安装
check_and_install_screen() {
  ssh -q remote "command -v screen &>/dev/null" || {
    ssh -q remote "if command -v apt-get &>/dev/null; then sudo apt-get update && sudo apt-get install -y screen; \
      elif command -v yum &>/dev/null; then sudo yum install -y screen; \
      elif command -v dnf &>/dev/null; then sudo dnf install -y screen; \
      elif command -v pacman &>/dev/null; then sudo pacman -Sy screen; \
      else echo 'Error: No supported package manager.'; exit 1; fi" || {
        log_error "Error: Failed to install 'screen'."; exit 1; 
      }
  }
}

# 在 screen 中执行命令，支持断线后继续运行
execute_inscreen() {
  local command="$1"
  local screen_name_prefix="$2"
  local screen_uuid screen_name
  screen_uuid="$(uuidgen)"
  screen_name="${screen_name_prefix:-screen}-${screen_uuid}"
  check_and_install_screen
  ssh -q remote sudo screen -dmS $screen_name
  ssh -q remote sudo screen -S $screen_name -X stuff "\$'$command && exit\n'"
  log_success "Command dispatched to remote screen session."
}

# 直接 SSH 执行命令
execute_command() {
  local command="$1"
  ssh -q remote "$command" || { log_error "Error: Failed to execute command."; exit 1; }
  log_success "Command executed on remote host."
}

# 设置远程文件权限
set_permissions() {
  local remote_path="$1"
  local permissions="${2:-755}"
  local ssh_user="${SSH_USER:-}"
  ssh -q remote "sudo chmod ${permissions} ${remote_path} && sudo chown ${ssh_user} ${remote_path}" || {
    log_error "Error: Failed to set permissions for ${remote_path}."; exit 1; 
  }
  log_success "Permissions set for ${remote_path}."
}

# 传输文件（含目录），支持跳过已存在相同 MD5 的文件
transfer_file() {
  local source="$1"
  local destination="$2"
  local isdir="false"
  local dest_dir

  [[ -d "$source" ]] && isdir="true"
  [[ "${destination: -1}" == "/" ]] && destination="${destination}$(basename "$source")"
  dest_dir=$(dirname "$destination")

  ssh -q remote "[ -d \"${dest_dir}\" ]" || ssh -q remote "sudo mkdir -p \"${dest_dir}\""
  set_permissions "${dest_dir}"

  if [ "$isdir" == "true" ]; then
    scp -q -r "$source" "remote:$destination" || { log_error "Error: Directory transfer failed."; exit 1; }
    log_success "Directory '$source' transferred to '$destination'."
  else
    local source_md5 remote_md5
    source_md5=$(md5sum "$source" | awk '{print $1}')
    remote_md5=$(ssh -q remote "md5sum \"$destination\" 2>/dev/null" | awk '{print $1}')
    if [ "$source_md5" == "$remote_md5" ]; then
      log_success "Remote file already up-to-date. Skipping transfer."
    else
      scp -q "$source" "remote:$destination" || { log_error "Error: File transfer failed."; exit 1; }
      log_success "File '$source' transferred to '$destination'."
    fi
  fi

  set_permissions "$destination"
}

# 执行部署脚本（可选用 screen）
execute_deployment() {
  local deploy_script="$1"
  local service_name="$2"
  local service_version="$3"
  local screen_name command

  if [ -n "$service_name" ] && [ -n "$service_version" ]; then
    command="sudo ${deploy_script} ${service_name} ${service_version}"
    screen_name="${service_name}-${service_version}"
  else
    command="sudo ${deploy_script}"
    screen_name="deploy-script"
  fi

  if [ "$USE_SCREEN" == "yes" ]; then
    execute_inscreen "$command" "$screen_name"
  else
    execute_command "$command"
  fi

  if [ -n "$service_name" ] && [ -n "$service_version" ]; then
    log_success "Deployment script '${deploy_script}' executed for '${service_name}' version '${service_version}'."
  else
    log_success "Deployment script '${deploy_script}' executed."
  fi
}


# 检查所有关键参数是否存在
check_required_params(){
  check_param "$USE_SCREEN" "Use screen"
  check_param "$USE_JUMP_HOST" "Use jump host"
  check_param "$SSH_PRIVATE_KEY" "SSH private key"
  check_param "$SSH_HOST" "SSH host"
  check_param "$SSH_USER" "SSH user"
  check_param "$SSH_PORT" "SSH port"
  check_param "$EXECUTE_REMOTE_SCRIPT" "Execute remote script"
  check_param "$TRANSFER_FILES" "Transfer files"
}

# 执行 SSH 初始化及配置
setup_ssh(){
  ssh_init
  if [ "$USE_JUMP_HOST" == "yes" ]; then
    check_param "$JUMP_SSH_HOST" "Jump SSH host"
    check_param "$JUMP_SSH_USER" "Jump SSH user"
    check_param "$JUMP_SSH_PRIVATE_KEY" "Jump SSH private key"
    setup_ssh_key "$JUMP_SSH_PRIVATE_KEY" /root/.ssh/jump.key
    setup_ssh_key "$SSH_PRIVATE_KEY" /root/.ssh/remote.key
    setup_ssh_config "jump" "$JUMP_SSH_HOST" "$JUMP_SSH_USER" "/root/.ssh/jump.key" "$JUMP_SSH_PORT"  ""
    setup_ssh_config "remote" "$SSH_HOST" "$SSH_USER" "/root/.ssh/remote.key" "$SSH_PORT"  "ProxyJump jump"
  else
    setup_ssh_key "$SSH_PRIVATE_KEY" /root/.ssh/remote.key
    setup_ssh_config "remote" "$SSH_HOST" "$SSH_USER" "/root/.ssh/remote.key" "$SSH_PORT"  ""
  fi
  chmod 600 /root/.ssh/config
}

# 传输文件（如被启用）
check_transfer_file(){
  if [ "$TRANSFER_FILES" == "yes" ]; then
    check_param "$SOURCE_FILE_PATH" "Source file path"
    check_param "$DESTINATION_PATH" "Destination path"
    transfer_file "$SOURCE_FILE_PATH" "$DESTINATION_PATH"
  fi
}

# 执行部署脚本（如被启用）
check_execute_deployment(){
  if [ "$EXECUTE_REMOTE_SCRIPT" == "yes" ]; then
    check_param "$COPY_SCRIPT" "Copy script"
    check_param "$DEPLOY_SCRIPT" "Deploy script"
    if [ "$COPY_SCRIPT" == "yes" ]; then
      check_param "$SOURCE_SCRIPT" "Source script"
      transfer_file "$SOURCE_SCRIPT" "$DEPLOY_SCRIPT"
    else
      ssh -q remote [ -f "${DEPLOY_SCRIPT}" ] && set_permissions "$DEPLOY_SCRIPT" || {
        log_error "Error: Remote script does not exist: ${DEPLOY_SCRIPT}"; exit 1
      }
    fi
    execute_deployment "$DEPLOY_SCRIPT" "$SERVICE_NAME" "$SERVICE_VERSION"
  fi
}

# 主函数入口
main(){
  log_info "Script Version: ${SCRIPT_VERSION}"
  check_required_params
  setup_ssh
  check_ssh_connection
  check_transfer_file
  check_execute_deployment
}

main
