# 🚀 Deploy via SSH · Universal Remote Deployment Tool

[简体中文](README.zh-CN.md) | [English](README.md)

**Deploy via SSH** is a cross-platform deployment utility for pushing build artifacts and executing deployment scripts via SSH. It supports jump hosts, `screen` for background tasks, and works seamlessly with GitHub Actions, CNB Cloud Native pipelines, GitLab CI, Jenkins, and more.

---

## ✨ Features

- 🔒 **Secure SSH Connection**: Direct or via jump host.
- 📦 **File Transfer**: Upload files or directories via `scp`.
- 🛠️ **Script Execution**: Run deployment scripts remotely to restart services, update configs, etc.
- 🖥️ **Screen Support**: Run tasks in `screen` to ensure they persist even after CI disconnects.
- ⚙️ **Highly Configurable**: Configure all behavior via parameters or environment variables.

---

## ✅ Requirements

- Target server must support SSH key authentication.
- CI runner must be able to access the target host (or jump host if used).
- If using `screen`, ensure it is installed on the server.
- Secrets or environment variables should be configured for credentials and sensitive data.

---

## 🔧 Input Parameters

| Name                    | Description                                               | Required | Default |
|-------------------------|-----------------------------------------------------------|----------|---------|
| `ssh_host`              | Target server hostname or IP                              | ✅        |         |
| `ssh_user`              | SSH username                                              | ✅        |         |
| `ssh_private_key`       | SSH private key (PEM format, plaintext or Base64)         | ✅        |         |
| `ssh_port`              | SSH port                                                  | ❌        | `22`    |
| `use_jump_host`         | Whether to use a jump host (`yes` or `no`)                | ❌        | `no`    |
| `jump_ssh_host`         | Jump host address                                         | Cond.    |         |
| `jump_ssh_user`         | Jump host SSH username                                    | Cond.    |         |
| `jump_ssh_private_key`  | Jump host private key                                     | Cond.    |         |
| `jump_ssh_port`         | Jump host SSH port                                        | ❌        | `22`    |
| `transfer_files`        | Transfer local files to server (`yes` or `no`)            | ✅        | `yes`   |
| `source_file_path`      | Local path to file or directory                           | ✅        |         |
| `destination_path`      | Destination absolute path on remote (trailing `/` = copy) | ✅        |         |
| `execute_remote_script` | Execute a remote script (`yes` or `no`)                   | ❌        | `no`    |
| `copy_script`           | Upload local script before execution (`yes` or `no`)      | ❌        | `no`    |
| `source_script`         | Path to local script                                      | Cond.    |         |
| `deploy_script`         | Absolute path to script on remote                         | Cond.    |         |
| `use_screen`            | Use `screen` to run commands                              | ❌        | `no`    |
| `service_name`          | Optional service name (passed to script)                  | ❌        |         |
| `service_version`       | Optional service version (passed to script)               | ❌        |         |

> ℹ️ Note: If `destination_path` ends with `/`, the entire source directory will be copied into that directory.

---

## 📦 Usage Examples

### ✅ GitHub Actions

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Deploy via SSH
        uses: falling42/ssh-deploy@v0.1.0
        with:
          ssh_host: ${{ secrets.SSH_HOST }}
          ssh_user: ${{ secrets.SSH_USER }}
          ssh_private_key: ${{ secrets.SSH_PRIVATE_KEY }}
          ssh_port: 23456
          transfer_files: 'yes'
          source_file_path: './build/app.jar'
          destination_path: '/var/www/app/'
          execute_remote_script: 'yes'
          copy_script: 'yes'
          source_script: 'scripts/deploy.sh'
          deploy_script: '/var/www/scripts/deploy.sh'
          service_name: 'my-app'
          service_version: ${{ steps.meta.outputs.version }}
```

### 🧩 CNB Cloud Native Build Pipeline

```yaml
main:
  push:
    pipeline:
      services:
        - docker
      stages:
        - name: Deploy Application via SSH
          image: docker.cnb.cool/falling42/ssh-deploy:v0.1.0
          imports: https://cnb.cool/org/repo/-/blob/main/yourenv.yml
          settings:
            ssh_host: ${SSH_HOST}
            ssh_user: ${SSH_USER}
            ssh_private_key: ${SSH_PRIVATE_KEY}
            ssh_port: ${SSH_PORT}
            transfer_files: 'yes'
            source_file_path: './build/app.jar'
            destination_path: '/var/www/app/'
            execute_remote_script: 'yes'
            copy_script: 'yes'
            source_script: 'scripts/deploy.sh'
            deploy_script: '/var/www/scripts/deploy.sh'
            service_name: 'my-app'
            service_version: "${CNB_BRANCH}-${CNB_COMMIT_SHORT}"
```

> ✅ Ensure the container image is allowed and secrets are properly configured.

---

### 🐳 Generic Docker Run Example (Other CI/CD platform)

```bash
docker run --rm \
  -e PLUGIN_SSH_HOST=your.remote.host \
  -e PLUGIN_SSH_USER=root \
  -e PLUGIN_SSH_PRIVATE_KEY="$(cat ~/.ssh/id_rsa)" \
  -e PLUGIN_TRANSFER_FILES=yes \
  -e PLUGIN_SOURCE_FILE_PATH=/workspace/build/app.jar \
  -e PLUGIN_DESTINATION_PATH=/opt/apps/my-app/ \
  -e PLUGIN_EXECUTE_REMOTE_SCRIPT=yes \
  -e PLUGIN_COPY_SCRIPT=yes \
  -e PLUGIN_SOURCE_SCRIPT=/workspace/scripts/deploy.sh \
  -e PLUGIN_DEPLOY_SCRIPT=/opt/apps/my-app/deploy.sh \
  -e PLUGIN_SERVICE_NAME=my-app \
  -e PLUGIN_SERVICE_VERSION=1.0.0 \
  -v $(pwd):/workspace \
  falling42/ssh-deploy:v0.1.0

```

---

## 🛡️ Path Safety Checks

To avoid accidental overwrites or privilege escalation, the tool restricts deployment paths using a whitelist:

```bash
/data/*       
/mnt/*        
/home/*       
/opt/*        
/var/www      
/srv/*        
/workspace/*     
/usr/local    
/app/*
```

If a target path violates the rule, deployment will halt:

```bash
❌ Refusing transfer to unsafe path: /root/secret
```

---

## 🔐 Recommended Secrets

| Secret Name             | Purpose             |
|-------------------------|---------------------|
| `SSH_HOST`              | Remote server host  |
| `SSH_USER`              | SSH username        |
| `SSH_PRIVATE_KEY`       | SSH private key     |
| `SSH_PORT`              | Optional SSH port   |
| `JUMP_SSH_HOST`         | Optional jump host  |
| `JUMP_SSH_USER`         | Optional jump user  |
| `JUMP_SSH_PRIVATE_KEY`  | Optional jump key   |

---

## 🧾 License

Apache 2.0 License © [falling42](https://github.com/falling42)
