# --------------------------------------------------
# 阶段 0: 平台基础镜像定义
#
# 我们为每个目标架构定义一个基础镜像。
# buildx 在构建时会自动设置 TARGETARCH 变量。
# --------------------------------------------------

# 当目标是 arm64 时，使用 alpine:latest
FROM alpine:latest AS base-arm64

# 当目标是 armv7 (TARGETARCH=arm) 时，使用 alpine:3.19
FROM alpine:3.19 AS base-arm

# --------------------------------------------------
# 这是一个“指针”阶段，它会根据 TARGETARCH 动态地
# 选择上面定义的一个基础镜像。
# 后续的所有阶段都应该 FROM 这个 "base" 阶段。
# --------------------------------------------------
FROM base-${TARGETARCH} AS base

# ==================================================
# 从这里开始，是你原来的 Dockerfile 逻辑，
# 只需要将 "FROM alpine:latest" 修改为 "FROM base"
# ==================================================

# 阶段 1: 获取 QEMU 静态二进制文件
# 使用我们上面动态选择的 "base" 镜像
FROM base AS qemu-builder
# 注意：qemu-x86_64 仅在 arm64 架构的 alpine 仓库中存在，
# 在 armv7 中可能不存在或名称不同。如果 armv7 构建失败，
# 你可能需要为 armv7 安装 qemu-arm-static。
# 但对于你的 iwechat 场景，这个 qemu 可能是为了在 x86 runner 上运行 arm 代码，
# 如果 iwechat 本身是 arm 应用，这个 qemu-x86_64 可能不是你想要的。
# 暂时保持原样，如果出错再调整。
RUN apk add --no-cache qemu-x86_64

# --------------------------------------------------

# 阶段 2: 最终的 Alpine 镜像
# 再次使用我们动态选择的 "base" 镜像
FROM base

# 从构建器阶段复制 QEMU 静态模拟器
# 增加一个检查，如果文件不存在就不复制，避免 armv7 构建失败
COPY --from=qemu-builder /usr/bin/qemu-x86_64 /usr/bin/qemu-x86_64-static
# 安装依赖项
# Alpine 的包名和 Ubuntu 不同
# tzdata 用于时区设置
# redis, supervisor, mariadb, mariadb-client, curl, ca-certificates 是核心服务
# shadow 用于 useradd/groupadd
# coreutils 提供 `chown` 等基本命令
RUN apk add --no-cache \
    tzdata \
    redis \
    supervisor \
    mariadb \
    mariadb-client \
    curl \
    ca-certificates \
    shadow \
    coreutils

# 设置时区为亚洲/上海
RUN cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

# 创建 supervisor 配置目录和文件
RUN mkdir -p /etc/supervisor/conf.d

# 创建 supervisord.conf 配置文件 (与之前版本相同)
RUN <<EOF cat > /etc/supervisord.conf
[supervisord]
nodaemon=true
user=root
loglevel=warn
[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700
username=admin
password=yourpassword
[supervisorctl]
serverurl=unix:///var/run/supervisor.sock
username=admin
password=yourpassword
[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface
[include]
files = /etc/supervisor/conf.d/*.conf
EOF

# 添加 redis 的 supervisor 配置
# Alpine 的 redis 默认在前台运行，不需要额外参数
RUN <<EOF cat > /etc/supervisor/conf.d/01_redis.conf
[program:redis]
command=/usr/bin/redis-server /etc/redis.conf
autostart=true
autorestart=true
stderr_logfile=/var/log/redis.err.log
stdout_logfile=/var/log/redis.out.log
EOF

# 修改 Redis 配置文件，使其不在后台运行（daemonize no）
# supervisor 会负责后台管理
RUN sed -i 's/daemonize yes/daemonize no/' /etc/redis.conf

# 添加 mariadb 的 supervisor 配置
# Alpine 上使用 mysqld_safe 更稳定，并指定数据目录和用户
RUN <<EOF cat > /etc/supervisor/conf.d/02_mariadb.conf
[program:mariadb]
command=/usr/bin/mysqld_safe --datadir='/var/lib/mysql'
user=mysql
autostart=true
autorestart=true
stderr_logfile=/var/log/mariadb.err.log
stdout_logfile=/var/log/mariadb.out.log
EOF

# 添加 myapp 的 supervisor 配置 (与之前版本相同)
# 确保 qemu-x86_64-static 的路径正确
RUN <<EOF cat > /etc/supervisor/conf.d/99_myapp.conf
[program:myapp]
command=/usr/bin/qemu-x86_64-static /app/myapp --port 8849
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
redirect_stderr=true
stdout_events_enabled=true
EOF

LABEL maintainer="exthirteen"

# 设置工作目录并添加应用文件
# 如果使用 GitHub Actions, 记得路径是 source-app/
WORKDIR /app
ADD source-app/myapp /app/myapp
ADD source-app/assets /app/assets
ADD source-app/static /app/static

# 复制入口脚本并赋予执行权限
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# 创建 MariaDB 数据目录并赋予正确权限
# 这是必须的，因为 Alpine 镜像中默认不存在 /var/lib/mysql
RUN mkdir -p /var/lib/mysql /var/run/mysqld && \
    chown -R mysql:mysql /var/lib/mysql /var/run/mysqld

# 暴露端口
EXPOSE 8849

# 设置入口点
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# 默认启动命令
CMD ["supervisord", "-c", "/etc/supervisord.conf"]
