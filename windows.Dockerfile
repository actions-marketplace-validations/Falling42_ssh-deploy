# 使用 Alpine 作为基础镜像
FROM alpine:3.21

ARG CNB_BRANCH
ENV VERSION=${CNB_BRANCH}

# 一次性安装全部依赖、设置时区、复制文件、赋权限
RUN apk add --no-cache \
      bash \
      curl \
      openssh-client \
      util-linux \
      screen \
      git \
      tzdata && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    rm -rf /var/cache/apk/*

# 拷贝并赋予执行权限
COPY scripts/entrypoint-windows.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
