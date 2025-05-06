# 🚀 Deploy via SSH · GitHub Action

[English](README.md) | [简体中文](README.zh-CN.md)

**Deploy via SSH** is a simple and efficient GitHub Action that enables remote deployment via SSH. It supports file transfer, script execution, and even jump host connections, making it suitable for various deployment scenarios.

---

## ✨ Features

* 🔒 **SSH Connections**: Securely connect to target servers, even through a jump host.
* 📦 **File Transfer**: Use `scp` to upload artifacts from your repository to a remote server.
* 🛠️ **Script Execution**: Run deployment scripts on the remote server to automate deployment.
* 🖥️ **Screen Support**: Optional `screen` mode keeps tasks running even after disconnection.
* ⚙️ **Highly Configurable**: Configure each step flexibly via input parameters.

---

## ✅ Prerequisites

Before using this Action, make sure:

* The GitHub Runner can access the target server via SSH (optionally via a jump host).
* SSH key-based authentication is set up on the remote server.
* `screen` is installed on the target server if you plan to use it.
* All necessary credentials are stored in GitHub Secrets.

---

## 🔧 Input Parameters

| Name                   | Description                                 | Required | Default |
|------------------------|---------------------------------------------|----------|---------|
| `ssh_host`             | SSH address of the target server            | ✅       |         |
| `ssh_user`             | SSH username                                | ✅       |         |
| `ssh_private_key`      | SSH private key (PEM format)                | ✅       |         |
| `ssh_port`             | SSH port                                    | ❌       | `22`    |
| `use_jump_host`        | Use a jump host (`yes/no`)                  | ❌       | `no`    |
| `jump_ssh_host`        | Jump host address                           | Conditionally required | |
| `jump_ssh_user`        | Jump host username                          | Conditionally required | |
| `jump_ssh_private_key` | Jump host private key                       | Conditionally required | |
| `jump_ssh_port`        | Jump host port                              | ❌       | `22`    |
| `transfer_files`       | Whether to transfer files (`yes/no`)        | ✅       | `yes`   |
| `source_file_path`     | Local file path                             | ✅       |         |
| `destination_path`     | Absolute path on remote server              | ✅       |         |
| `execute_remote_script`| Whether to execute a remote script (`yes/no`)| ❌      | `no`    |
| `copy_script`          | Whether to upload the local script (`yes/no`)| ❌      | `no`    |
| `source_script`        | Local script path                           | Conditionally required | |
| `deploy_script`        | Full absolute path of the script on server  | Conditionally required | |
| `use_screen`           | Use `screen` to persist task (`yes/no`)     | ❌       | `no`    |
| `service_name`         | Service name (passed to the script)         | ❌       |         |
| `service_version`      | Service version (passed to the script)      | ❌       |         |

> ℹ️ Note: If `destination_path` ends with `/`, the entire source directory will be copied into that directory.

---

## 📦 Example Workflow

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
        uses: falling42/ssh-deploy@v0.1.4
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
````

### 🛡️ With Jump Host

```yaml
      - name: Deploy with Jump Host
        uses: falling42/ssh-deploy@v0.1.4
        with:
          use_jump_host: 'yes'
          jump_ssh_host: ${{ secrets.JUMP_SSH_HOST }}
          jump_ssh_user: ${{ secrets.JUMP_SSH_USER }}
          jump_ssh_private_key: ${{ secrets.JUMP_SSH_PRIVATE_KEY }}
          # other parameters remain the same...
```

---

## 🌐 Using with CloudNative Build (CNB)

If you are using [cnb.cool](https://cnb.cool) cloud-native build platform, you can also directly use the deployment image in your pipeline:

### 🧩 Sample Configuration (`.cnb.yml`)

```yml
main:
  push:
    pipeline:
      services:
        - docker
      stages:
        # - name: Build Application
        #   script: mvn clean -B package -DskipTests

        - name: Deploy Application via SSH
          image: docker.cnb.cool/falling42/ssh-deploy:v0.1.4
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

### ✅ Notes

* Make sure variables like `${SSH_HOST}` are configured in the CNB secrets vault.
* If using `imports`, you must configure `allow_images` to permit `docker.cnb.cool/falling42/ssh-deploy:v0.1.4` and `allow_slugs` for your repository in the secrets vault.

---

## 🔐 Recommended Secrets

| Secret Name            | Purpose                       |
| ---------------------- | ----------------------------- |
| `SSH_HOST`             | Target server address         |
| `SSH_USER`             | SSH username on the server    |
| `SSH_PRIVATE_KEY`      | SSH private key               |
| `SSH_PORT`             | SSH port (optional)           |
| `JUMP_SSH_HOST`        | Jump host address (optional)  |
| `JUMP_SSH_USER`        | Jump host username (optional) |
| `JUMP_SSH_PRIVATE_KEY` | Jump host private key         |

---

## 🧯 Error Handling

This Action will automatically fail if:

* Required parameters are missing
* SSH/SCP command fails
* Script execution fails

Check the Action logs for detailed messages.

---

## 🔐 Security Recommendations

* Always use GitHub Secrets to store sensitive credentials.
* Avoid hardcoding private keys or server details in the workflow file.

---

## 🧾 License

Apache 2.0 License © [falling42](https://github.com/falling42)

---
