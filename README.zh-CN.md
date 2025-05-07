# 🚀 Deploy via SSH · GitHub Action

[English](README.md) | [简体中文](README.zh-CN.md)

**Deploy via SSH** 是一个简单高效的 GitHub Action，用于通过 SSH 实现远程部署，支持文件传输、脚本执行，甚至跳板机连接，适合各种部署场景。

---

## ✨ 功能特色

* 🔒 **SSH 连接**：支持通过跳板机安全连接目标主机。
* 📦 **文件传输**：使用 `scp` 将构建产物从仓库传输至远程服务器。
* 🛠️ **脚本执行**：在远程服务器运行部署脚本，完成自动化部署。
* 🖥️ **Screen 支持**：可选 `screen` 模式，部署任务不中断。
* ⚙️ **高可配置性**：通过输入参数灵活配置每一个步骤。

---

## ✅ 使用前提

在使用此 Action 之前，请确保：

* GitHub Runner 能够通过 SSH 访问目标服务器（可选跳板机）。
* 远程服务器已配置 SSH 公钥认证。
* `screen`（可选）已在目标服务器中安装。
* GitHub Secrets 中已配置必要的凭据信息。

---

## 🔧 输入参数一览

| 名称                    | 描述                                 | 是否必需 | 默认值 |
| ----------------------- | ------------------------------------ | -------- | ------ |
| `ssh_host`              | 目标服务器 SSH 地址                  | ✅        |        |
| `ssh_user`              | SSH 用户名                           | ✅        |        |
| `ssh_private_key`       | SSH 私钥（PEM 格式）                 | ✅        |        |
| `ssh_port`              | SSH 端口                             | ❌        | `22`   |
| `use_jump_host`         | 是否使用跳板机（`yes/no`）           | ❌        | `no`   |
| `jump_ssh_host`         | 跳板机地址                           | 条件必需 |        |
| `jump_ssh_user`         | 跳板机用户名                         | 条件必需 |        |
| `jump_ssh_private_key`  | 跳板机私钥                           | 条件必需 |        |
| `jump_ssh_port`         | 跳板机端口                           | ❌        | `22`   |
| `transfer_files`        | 是否传输文件（`yes/no`）             | ✅        | `yes`  |
| `source_file_path`      | 本地文件路径                         | ✅        |        |
| `destination_path`      | 远程目标绝对路径（可省文件名）       | ✅        |        |
| `execute_remote_script` | 是否执行部署脚本（`yes/no`）         | ❌        | `no`   |
| `copy_script`           | 是否上传本地脚本（`yes/no`）         | ❌        | `no`   |
| `source_script`         | 本地脚本路径                         | 条件必需 |        |
| `deploy_script`         | 远程脚本完整绝对路径                 | 条件必需 |        |
| `use_screen`            | 是否使用 screen 保持任务（`yes/no`） | ❌        | `no`   |
| `service_name`          | 服务名称（传给脚本）                 | ❌        |        |
| `service_version`       | 服务版本（传给脚本）                 | ❌        |        |

> ℹ️ 注意：`destination_path` 如果以 `/` 结尾，则源目录会完整复制进该目录。

---

## 📦 示例工作流

### 🚀 基础部署（含文件传输和脚本执行）

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
        uses: falling42/ssh-deploy@v0.1.10
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

### 🛡️ 使用跳板机

```yaml
      - name: Deploy with Jump Host
        uses: falling42/ssh-deploy@v0.1.10
        with:
          use_jump_host: 'yes'
          jump_ssh_host: ${{ secrets.JUMP_SSH_HOST }}
          jump_ssh_user: ${{ secrets.JUMP_SSH_USER }}
          jump_ssh_private_key: ${{ secrets.JUMP_SSH_PRIVATE_KEY }}
          # 其他参数与上面类似...
```

---

## 🌐 在 云原生构建 (CNB) 中使用

如果你使用 [cnb.cool](https://cnb.cool) 云原生构建平台，也可以在流水线中直接使用本 Action 的镜像进行部署：

### 🧩 示例配置（.cnb.yml）

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
          image: docker.cnb.cool/falling42/ssh-deploy:v0.1.10
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

### ✅ 注意事项

* 请确保 `${SSH_HOST}` 等变量已在 CNB 密钥仓库中配置。
* `imports` 时确保你已经在密钥仓库文件中配置`allow_images`允许`docker.cnb.cool/falling42/ssh-deploy:v0.1.10`和`allow_slugs`允许你的仓库。

---

## 🔐 推荐的 Secrets 配置

| Secret 名称              | 用途               |
| ---------------------- | ---------------- |
| `SSH_HOST`             | 目标服务器地址          |
| `SSH_USER`             | 目标服务器用户名         |
| `SSH_PRIVATE_KEY`      | 目标服务器私钥          |
| `SSH_PORT`             | 目标服务器 SSH 端口（可选） |
| `JUMP_SSH_HOST`        | 跳板机地址（如使用）       |
| `JUMP_SSH_USER`        | 跳板机用户名（如使用）      |
| `JUMP_SSH_PRIVATE_KEY` | 跳板机私钥（如使用）       |

---

## 🧯 错误处理

本 Action 遇到以下任一问题将自动失败：

* 缺失必填参数
* SSH/SCP 命令失败
* 脚本执行失败

请在 Action 日志中查看详细信息。

---

## 🔐 安全建议

* 始终使用 GitHub Secrets 管理敏感信息。
* 避免将私钥或主机信息硬编码在工作流中。

---

## 🧾 License

Apache 2.0 License © [falling42](https://github.com/falling42)

---