# 使用 Alpine 作为基础镜像
FROM alpine:3.21

ARG CNB_BRANCH
ENV VERSION=${CNB_BRANCH}

# 设置时区为上海
RUN apk add --no-cache tzdata && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    apk del tzdata

# 安装需要的软件包
RUN apk add --no-cache \
    bash \
    curl \
    openssh-client \
    uuidgen \
    screen \
    sudo \
    git

# 设置工作目录
WORKDIR /app

# 将脚本文件拷贝到镜像中
COPY scripts/deploy-via-ssh.sh /app/deploy-via-ssh.sh

# 给予执行权限
RUN chmod +x /app/deploy-via-ssh.sh

# 设置默认的入口命令
ENTRYPOINT ["/app/deploy-via-ssh.sh"]
