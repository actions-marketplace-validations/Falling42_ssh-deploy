#!/usr/bin/env bash

# 定义颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
RESET="\033[0m"
GRAY="\033[90m"

# 输出带颜色的信息

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

# 从环境变量中读取值
SCRIPT_VERSION="${VERSION}"
USE_SCREEN="${PLUGIN_USE_SCREEN:-no}"
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

# 检查必需参数是否为空
check_param() {
  local param_value=$1
  local param_name=$2

  if [ -z "$param_value" ]; then
    log_error "Error: $param_name is missing."
    exit 1
  else
    # log_info "$param_name is ${BLUE}$param_value${RESET}."
    log_info "$param_name has been successfully set."
  fi
}

ssh_init(){
  mkdir -p ~/.ssh/
  chmod 700 ~/.ssh/
}

# 设置 SSH 私钥
setup_ssh_key() {
  local ssh_key="$1"
  local key_path="$2"
  
  echo "${ssh_key}" > "${key_path}"
  chmod 600 "${key_path}" || { log_error "Error: Failed to set permissions for ${key_path}."; exit 1; }
  [ ! -f "${key_path}" ] && { log_error "Error: Failed to write SSH private key at ${key_path}."; exit 1; }
}

# 设置 SSH 配置文件
setup_ssh_config() {
  local host_name="$1"
  local ssh_host="$2"
  local ssh_user="$3"
  local ssh_key="$4"
  local ssh_port="${5:-22}"
  local proxy_jump="$6"

  if ! grep -q "Host $host_name" ~/.ssh/config 2>/dev/null; then
    log_info "Writing SSH configuration for $host_name"
    cat >>~/.ssh/config <<END
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
  else
    log_info "SSH configuration for $host_name already exists."
  fi
}

# 检查 SSH 是否能成功连接远程主机，最多重试3次
check_ssh_connection() {
  local max_retries=3
  local retry_delay=3
  local attempt=1

  log_info "Checking SSH connectivity to remote host..."

  while (( attempt <= max_retries )); do
    if ssh -q -o ConnectTimeout=10 remote "echo -e '${GREEN}SSH connection successful.${RESET}'" 2>/dev/null; then
      log_success "SSH connection to remote host succeeded."
      return 0
    else
      log_warning "Attempt ${attempt}/${max_retries}: SSH connection failed."
      if (( attempt < max_retries )); then
        log_info "Retrying in ${retry_delay} seconds..."
        sleep "$retry_delay"
      fi
      ((attempt++))
    fi
  done

  log_error "Error: SSH connection failed after ${max_retries} attempts. Please check network, SSH key, host, and user configuration."
  exit 1
}

# TODO 检查并安装 screen
check_and_install_screen() {
  log_info "Checking if 'screen' is installed on the remote host..."
  if ssh -q remote "command -v screen &>/dev/null"; then
    log_success "'screen' is already installed on the remote host."
  else
    log_warning "'screen' is not installed. Attempting to install..."
    ssh -q remote "if command -v apt-get &>/dev/null; then
                   sudo apt-get update && sudo apt-get install -y screen;
                 elif command -v yum &>/dev/null; then
                   sudo yum install -y screen;
                 elif command -v dnf &>/dev/null; then
                   sudo dnf install -y screen;
                 elif command -v pacman &>/dev/null; then
                   sudo pacman -Sy screen;
                 else
                   echo 'Error: Unsupported package manager. Please install screen manually.';
                   exit 1;
                 fi" || { log_error "Error: Failed to install 'screen' on the remote server."; exit 1; }
    log_success "'screen' installation completed on the remote host."
  fi
}

# 在screen里执行命令
execute_inscreen() {
  local command="$1"
  local screen_name_prefix="${2:-}"
  local screen_uuid
  screen_uuid="$(uuidgen)"

  check_and_install_screen

  if [ -z "$screen_name_prefix" ]; then
    screen_name="$screen_uuid"
  else
    screen_name="${screen_name_prefix}-${screen_uuid}"
  fi

  log_info "Creating screen session: $screen_name"
  eval "ssh -q remote sudo screen -dmS $screen_name" || { log_error "Error: Failed to create screen session."; exit 1; }
  log_info "Executing command in screen: $command"
  eval "ssh -q remote sudo screen -S $screen_name -X stuff \"\$'$command && exit\n'\"" || { log_error "Error: Failed to execute command in screen."; exit 1; }
  log_info "Command is executing in screen. Check the screen session for any errors."
}

# 执行命令
execute_command() {
  local command="$1"

  log_info "Executing command: $command"
  eval "ssh -q remote \"$command\"" || { log_error "Error: Failed to execute command."; exit 1; }
  log_success "Command executed successfully."
}

# 设置远程文件或目录权限，并将属主设置为 SSH 用户（保留原组）
set_permissions() {
  local remote_path="$1"
  local permissions="${2:-755}"
  local ssh_user="${SSH_USER:-}"

  log_info "Checking current permissions for ${remote_path} on remote host..."
  current_permissions="$(ssh -q remote "stat -c '%a' \"${remote_path}\"" 2>/dev/null || echo "unknown")"

  if [ "$current_permissions" == "$permissions" ]; then
    log_success "Permissions already set to ${permissions} for ${remote_path}."
  else
    log_info "Setting permissions for ${remote_path} to ${permissions}..."
    execute_command "sudo chmod ${permissions} ${remote_path}" || {
      log_error "Error: Failed to set permissions for ${remote_path}."
      exit 1
    }
    log_success "Permissions set to ${permissions} for ${remote_path}."
  fi

  log_info "Setting owner of ${remote_path} to ${ssh_user} (group unchanged)..."
  execute_command "sudo chown ${ssh_user} ${remote_path}" || {
    log_error "Error: Failed to change owner for ${remote_path}."
    exit 1
  }
  log_success "Owner of ${remote_path} set to ${ssh_user} successfully."
}


# 传输文件
transfer_file() {
  local source="$1"
  local destination="$2"
  local ssh_user="${SSH_USER:-}"
  local isdir="false"
  local dest_dir

  # 如果源文件是目录
  if [[ -d "$source" ]]; then
    isdir="true"
  fi
  
  # 如果目标路径加了"/"
  if [[ "${destination: -1}" == "/" ]]; then
    destination="${destination}$(basename "$source")"
  fi

  dest_dir=$(dirname "${destination}")

  log_info "Ensuring remote directory exists: ${dest_dir}"
  if ! ssh -q remote "[ -d \"${dest_dir}\" ]"; then
    execute_command "sudo mkdir -p \"${dest_dir}\"" || {
      log_error "Error: Failed to create remote directory."
      exit 1
    }
  fi
  set_permissions "${dest_dir}"

  if [ "$isdir" == "true" ]; then
    log_info "Transferring directory..."
    scp -q -r "${source}" "remote:${destination}" || {
      log_error "Error: Directory transfer failed."
      exit 1
    }
  else
    if ssh -q remote "[ -f \"${destination}\" ]"; then
      local source_md5 remote_md5
      source_md5=$(md5sum "${source}" | awk '{print $1}')
      remote_md5=$(ssh -q remote "md5sum \"${destination}\" 2>/dev/null" | awk '{print $1}')
      if [ "$source_md5" == "$remote_md5" ]; then
        log_success "Remote file is identical, skipping transfer."
        return 0
      fi
    fi
    log_info "Transferring file..."
    scp -q "${source}" "remote:${destination}" || {
      log_error "Error: File transfer failed."
      exit 1
    }
  fi

  set_permissions "${destination}"
  log_success "File transfer complete: ${destination}"
}



# 执行远程部署
execute_deployment() {
  local deploy_script="$1"
  local service_name="$2"
  local service_version="$3"
  local screen_name=""
  local command="sudo ${deploy_script} ${service_name} ${service_version}"

  # 设置 screen_name（仅当 service_name 和 service_version 均非空）
  if [ -n "$service_name" ] && [ -n "$service_version" ]; then
    screen_name="${service_name}-${service_version}"
  fi

  if [ "$USE_SCREEN" == "yes" ]; then
    execute_inscreen "$command" "$screen_name"
 else
    execute_command "$command"
  fi
  log_success "Deployment executed successfully."
}

# 检查必需的参数
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

# 设置 SSH 环境
setup_ssh(){
  ssh_init
  if [ "$USE_JUMP_HOST" == "yes" ]; then
    check_param "$JUMP_SSH_HOST" "Jump SSH host"
    check_param "$JUMP_SSH_USER" "Jump SSH user"
    check_param "$JUMP_SSH_PRIVATE_KEY" "Jump SSH private key"
    setup_ssh_key "$JUMP_SSH_PRIVATE_KEY" ~/.ssh/jump.key
    setup_ssh_key "$SSH_PRIVATE_KEY" ~/.ssh/remote.key
    setup_ssh_config "jump" "$JUMP_SSH_HOST" "$JUMP_SSH_USER" "~/.ssh/jump.key" "$JUMP_SSH_PORT"  ""
    setup_ssh_config "remote" "$SSH_HOST" "$SSH_USER" "~/.ssh/remote.key" "$SSH_PORT"  "ProxyJump jump"
  else
    setup_ssh_key "$SSH_PRIVATE_KEY" ~/.ssh/remote.key
    setup_ssh_config "remote" "$SSH_HOST" "$SSH_USER" "~/.ssh/remote.key" "$SSH_PORT"  ""
  fi
  chmod 600 ~/.ssh/config
}

# 处理文件传输
check_transfer_file(){
  if [ "$TRANSFER_FILES" == "yes" ]; then
    check_param "$SOURCE_FILE_PATH" "Source file path"
    check_param "$DESTINATION_PATH" "Destination path"
    transfer_file "$SOURCE_FILE_PATH" "$DESTINATION_PATH"
  else
    log_warning "Skipping file transfer as per configuration."
  fi    
}

# 处理部署
check_execute_deployment(){
  if [ "$EXECUTE_REMOTE_SCRIPT" == "yes" ]; then
    check_param "$COPY_SCRIPT" "Copy script"
    check_param "$DEPLOY_SCRIPT" "Deploy script"
    if [ "$COPY_SCRIPT" == "yes" ]; then
      check_param "$SOURCE_SCRIPT" "Source script"
      transfer_file "$SOURCE_SCRIPT" "$DEPLOY_SCRIPT"
    else
      if ssh -q remote [ -f ${DEPLOY_SCRIPT} ]; then
        log_info "Remote script ${DEPLOY_SCRIPT} exists."
        set_permissions "${DEPLOY_SCRIPT}"
      else
        log_error "Error:Remote script ${DEPLOY_SCRIPT} does not exist. Please check your config: DEPLOY_SCRIPT."
        exit 1
      fi     
    fi  
    execute_deployment "$DEPLOY_SCRIPT" "$SERVICE_NAME" "$SERVICE_VERSION"
  else
    log_warning "Skipping remote script execution as per configuration."
  fi  
}

# 主函数
main(){
  log_info "Script Version: ${MAGENTA}${SCRIPT_VERSION}${RESET}"
  check_required_params
  setup_ssh
  check_ssh_connection
  check_transfer_file
  check_execute_deployment
}

main