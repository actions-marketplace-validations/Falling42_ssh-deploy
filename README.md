# 🚀 Deploy via SSH · GitHub Action

[English](README.md) | [简体中文](README.zh-CN.md)

**Deploy via SSH** is a simple and efficient GitHub Action for remote deployment via SSH. It supports file transfer, script execution, and even jump host connections—suitable for a wide range of deployment scenarios.

---

## ✨ Features

* 🔒 **SSH Connection**: Securely connect to the target host, with optional jump host support.
* 📦 **File Transfer**: Use `scp` to transfer build artifacts from the repository to the remote server.
* 🛠️ **Script Execution**: Run deployment scripts on the remote server to automate deployment.
* 🖥️ **Screen Support**: Optional `screen` mode keeps deployment alive after SSH session ends.
* ⚙️ **Highly Configurable**: Every step can be flexibly customized via input parameters.

---

## ✅ Prerequisites

Before using this Action, ensure the following:

* The GitHub Runner can SSH into the target server (optionally via jump host).
* SSH key authentication is configured on the target server.
* `screen` (optional) is installed on the remote server.
* Required credentials are stored in GitHub Secrets.

---

## 🔧 Input Parameters

| Name                    | Description                                            | Required | Default |
| ----------------------- | ------------------------------------------------------ | -------- | ------- |
| `ssh_host`              | SSH address of the target server                       | ✅        |         |
| `ssh_user`              | SSH username                                           | ✅        |         |
| `ssh_private_key`       | SSH private key (PEM format)                           | ✅        |         |
| `ssh_port`              | SSH port                                               | ❌        | `22`    |
| `use_jump_host`         | Whether to use a jump host (`yes/no`)                  | ❌        | `no`    |
| `jump_ssh_host`         | Jump host address                                      | Cond.    |         |
| `jump_ssh_user`         | Jump host username                                     | Cond.    |         |
| `jump_ssh_private_key`  | Jump host private key                                  | Cond.    |         |
| `jump_ssh_port`         | Jump host port                                         | ❌        | `22`    |
| `transfer_files`        | Whether to transfer files (`yes/no`)                   | ✅        | `yes`   |
| `source_file_path`      | Local file path                                        | ✅        |         |
| `destination_path`      | Absolute destination path on remote host               | ✅        |         |
| `execute_remote_script` | Whether to execute a remote script (`yes/no`)          | ❌        | `no`    |
| `copy_script`           | Whether to upload a local script (`yes/no`)            | ❌        | `no`    |
| `source_script`         | Local script path                                      | Cond.    |         |
| `deploy_script`         | Absolute path of remote deployment script              | Cond.    |         |
| `use_screen`            | Whether to use `screen` to keep tasks alive (`yes/no`) | ❌        | `no`    |
| `service_name`          | Service name (passed to the script)                    | ❌        |         |
| `service_version`       | Service version (passed to the script)                 | ❌        |         |

> ℹ️ Note: If `destination_path` ends with `/`, the entire source directory will be copied into that directory.

---

## 📦 Sample Workflow

### 🚀 Basic Deployment (with file transfer and script execution)

```yaml
name: Deploy to Server

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Deploy Application via SSH
        uses: falling42/ssh-deploy@v0.2.1
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

---

### 🛡️ Using a Jump Host

```yaml
      - name: Deploy with Jump Host
        uses: falling42/ssh-deploy@v0.2.1
        with:
          use_jump_host: 'yes'
          jump_ssh_host: ${{ secrets.JUMP_SSH_HOST }}
          jump_ssh_user: ${{ secrets.JUMP_SSH_USER }}
          jump_ssh_private_key: ${{ secrets.JUMP_SSH_PRIVATE_KEY }}
          # Other parameters remain the same...
```

---

## 🔐 Recommended Secrets Configuration

| Secret Name            | Purpose                           |
| ---------------------- | --------------------------------- |
| `SSH_HOST`             | Target server address             |
| `SSH_USER`             | Target server username            |
| `SSH_PRIVATE_KEY`      | SSH private key for target server |
| `SSH_PORT`             | SSH port (optional)               |
| `JUMP_SSH_HOST`        | Jump host address (if used)       |
| `JUMP_SSH_USER`        | Jump host username (if used)      |
| `JUMP_SSH_PRIVATE_KEY` | Jump host private key (if used)   |

---

## 🧯 Error Handling

This Action will automatically fail in the following scenarios:

* Missing required parameters
* SSH/SCP command failure
* Deployment script execution failure

Check the Action logs for detailed messages.

---

## 🔐 Security Recommendations

* Always store sensitive data in GitHub Secrets.
* Avoid hardcoding private keys or host information in workflows.

---

## 🧾 License

Apache 2.0 License © [falling42](https://github.com/falling42)

---
