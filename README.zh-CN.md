# 🚀 Deploy via SSH · 通用远程部署工具

[English](README.md) | [简体中文](README.zh-CN.md)

**Deploy via SSH** 是一个跨平台部署工具，可通过 SSH 实现构建产物的传输与远程脚本执行，适配 GitHub Actions、CNB 云原生平台、GitLab CI、Jenkins 等多种场景，支持跳板机连接、screen 后台任务等功能。

---

## ✨ 功能特色

- 🔒 **SSH 安全连接**：支持直连与跳板机方式访问服务器。
- 📦 **构建产物传输**：通过 `scp` 上传文件/目录到远程主机。
- 🛠️ **远程脚本执行**：自动运行部署脚本，实现服务发布或重启等操作。
- 🖥️ **Screen 支持**：可在 `screen` 中运行部署命令，保持后台执行不中断。
- ⚙️ **可配置参数**：支持环境变量、YAML 配置等多种方式配置部署逻辑。

---

## ✅ 使用条件

- 目标服务器已配置 SSH 公钥认证；
- CI 环境可访问目标服务器（如有跳板机则需中转）；
- 如使用 `screen` 功能，请确保远程服务器已安装；
- 所有密钥、主机信息建议通过 Secret 或环境变量传入。

---

## 🔧 参数说明

| 参数名                    | 描述                                         | 是否必需 | 默认值   |
|-------------------------|--------------------------------------------|---------|--------|
| `ssh_host`              | 目标服务器地址                                 | ✅       |        |
| `ssh_user`              | SSH 登录用户名                                 | ✅       |        |
| `ssh_private_key`       | SSH 私钥（PEM 格式，Base64 或纯文本）           | ✅       |        |
| `ssh_port`              | SSH 端口                                      | ❌       | `22`   |
| `use_jump_host`         | 是否使用跳板机（`yes/no`）                    | ❌       | `no`   |
| `jump_ssh_host`         | 跳板机地址                                     | 条件必需 |        |
| `jump_ssh_user`         | 跳板机用户名                                   | 条件必需 |        |
| `jump_ssh_private_key`  | 跳板机私钥                                     | 条件必需 |        |
| `jump_ssh_port`         | 跳板机端口                                     | ❌       | `22`   |
| `transfer_files`        | 是否传输构建产物（`yes/no`）                  | ✅       | `yes`  |
| `source_file_path`      | 本地构建文件或目录路径                          | ✅       |        |
| `destination_path`      | 远程目标路径（以 `/` 结尾则整体复制目录）       | ✅       |        |
| `execute_remote_script` | 是否执行远程脚本（`yes/no`）                  | ❌       | `no`   |
| `copy_script`           | 是否上传本地脚本（`yes/no`）                   | ❌       | `no`   |
| `source_script`         | 本地脚本路径（若启用上传）                     | 条件必需 |        |
| `deploy_script`         | 远程脚本完整路径（将被执行）                   | 条件必需 |        |
| `use_screen`            | 是否在 screen 中执行部署命令                   | ❌       | `no`   |
| `service_name`          | 服务名（将传入部署脚本）                       | ❌       |        |
| `service_version`       | 服务版本（将传入部署脚本）                     | ❌       |        |

> ℹ️ 注意：`destination_path` 如果以 `/` 结尾，则源目录会完整复制进该目录。

---

## 📦 多平台使用方式

### ✅ GitHub Actions 示例

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

### 🧩 CNB 云原生构建平台

#### 示例 `.cnb.yml` 配置

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

> ✅ 确保 `imports` 中允许该镜像，并在密钥仓库配置相应变量。

---

### 🐳 通用 Docker 方式 (其他 CI/CD 平台)

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

## 🛡️ 安全机制与路径校验

为避免误部署至敏感目录，默认启用路径白名单校验，仅允许以下前缀：

```bash
/data/*       
/mnt/*        
/home/*       
/opt/*        
/var/www      
/srv/*        
/usr/local    
/app/*        
/workspace/*
```

如目标路径不安全，部署将被拒绝：

```bash
❌ Refusing transfer to unsafe path: /root/secret
```

---

## 🔐 推荐 Secret 列表

| Secret 名称              | 用途               |
|--------------------------|--------------------|
| `SSH_HOST`               | 目标服务器地址       |
| `SSH_USER`               | 登录用户名           |
| `SSH_PRIVATE_KEY`        | SSH 私钥            |
| `SSH_PORT`               | SSH 端口（可选）     |
| `JUMP_SSH_HOST`          | 跳板机地址（可选）   |
| `JUMP_SSH_USER`          | 跳板机用户名（可选） |
| `JUMP_SSH_PRIVATE_KEY`   | 跳板机私钥（可选）   |

---

## 🧾 License

Apache 2.0 License © [falling42](https://github.com/falling42)
