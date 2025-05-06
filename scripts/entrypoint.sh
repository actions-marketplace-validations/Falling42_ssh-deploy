#!/usr/bin/env bash

# 定义颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"
GRAY="\033[90m"

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

check_param() {
  local param_value=$1
  local param_name=$2
  [ -z "$param_value" ] && log_error "Error: $param_name is missing."
}

ssh_init(){
  mkdir -p ~/.ssh/
  chmod 700 ~/.ssh/
}

setup_ssh_key() {
  local ssh_key="$1"
  local key_path="$2"
  echo "${ssh_key}" > "${key_path}"
  chmod 600 "${key_path}" || { log_error "Error: Failed to set permissions for ${key_path}."; exit 1; }
  [ ! -f "${key_path}" ] && { log_error "Error: Failed to write SSH private key at ${key_path}."; exit 1; }
}

setup_ssh_config() {
  local host_name="$1"
  local ssh_host="$2"
  local ssh_user="$3"
  local ssh_key="$4"
  local ssh_port="${5:-22}"
  local proxy_jump="$6"

  if ! grep -q "Host $host_name" ~/.ssh/config 2>/dev/null; then
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
  fi
}

check_ssh_connection() {
  local max_retries=3
  local retry_delay=3
  local attempt=1

  while (( attempt <= max_retries )); do
    if ssh -q -o ConnectTimeout=10 remote "echo successful >/dev/null" 2>/dev/null; then
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

execute_command() {
  local command="$1"
  ssh -q remote "$command" || { log_error "Error: Failed to execute command."; exit 1; }
  log_success "Command executed on remote host."
}

set_permissions() {
  local remote_path="$1"
  local permissions="${2:-755}"
  local ssh_user="${SSH_USER:-}"
  ssh -q remote "sudo chmod ${permissions} ${remote_path} && sudo chown ${ssh_user} ${remote_path}" || {
    log_error "Error: Failed to set permissions for ${remote_path}."; exit 1; 
  }
  log_success "Permissions set for ${remote_path}."
}

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

execute_deployment() {
  local deploy_script="$1"
  local service_name="$2"
  local service_version="$3"
  local screen_name command
  command="sudo ${deploy_script} ${service_name} ${service_version}"
  screen_name="${service_name}-${service_version}"

  if [ "$USE_SCREEN" == "yes" ]; then
    execute_inscreen "$command" "$screen_name"
  else
    execute_command "$command"
  fi
  log_success "Deployment script '${deploy_script}' executed for '${service_name}' version '${service_version}'."
}

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

check_transfer_file(){
  if [ "$TRANSFER_FILES" == "yes" ]; then
    check_param "$SOURCE_FILE_PATH" "Source file path"
    check_param "$DESTINATION_PATH" "Destination path"
    transfer_file "$SOURCE_FILE_PATH" "$DESTINATION_PATH"
  fi
}

check_execute_deployment(){
  if [ "$EXECUTE_REMOTE_SCRIPT" == "yes" ]; then
    check_param "$COPY_SCRIPT" "Copy script"
    check_param "$DEPLOY_SCRIPT" "Deploy script"
    if [ "$COPY_SCRIPT" == "yes" ]; then
      check_param "$SOURCE_SCRIPT" "Source script"
      transfer_file "$SOURCE_SCRIPT" "$DEPLOY_SCRIPT"
    else
      ssh -q remote [ -f ${DEPLOY_SCRIPT} ] && set_permissions "$DEPLOY_SCRIPT" || {
        log_error "Error: Remote script does not exist: ${DEPLOY_SCRIPT}"; exit 1
      }
    fi
    execute_deployment "$DEPLOY_SCRIPT" "$SERVICE_NAME" "$SERVICE_VERSION"
  fi
}

main(){
  log_info "Script Version: ${SCRIPT_VERSION}"
  check_required_params
  setup_ssh
  check_ssh_connection
  check_transfer_file
  check_execute_deployment
}

main
