# 阶段 1: 获取 QEMU 静态二进制文件
# Alpine 镜像本身不含 qemu, 我们需要从其他地方获取或者直接在 Alpine 中安装
# 这里我们选择在 Alpine 中直接安装
FROM alpine:latest AS qemu-builder
RUN apk add --no-cache qemu-x86_64

# --------------------------------------------------

# 阶段 2: 最终的 Alpine 镜像
FROM alpine:latest

# 从构建器阶段复制 QEMU 静态模拟器
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

# 创建 supervisor 配置目录和主配置文件
RUN mkdir -p /etc/supervisor/conf.d
RUN echo "[supervisord]" > /etc/supervisord.conf && \
    echo "nodaemon=true" >> /etc/supervisord.conf && \
    echo "logfile=/dev/null" >> /etc/supervisord.conf && \
    echo "pidfile=/var/run/supervisord.pid" >> /etc/supervisord.conf && \
    echo "" >> /etc/supervisord.conf && \
    echo "[include]" >> /etc/supervisord.conf && \
    echo "files = /etc/supervisor/conf.d/*.conf" >> /etc/supervisord.conf

# 配置 MariaDB 服务
RUN echo "[program:mariadb]" > /etc/supervisor/conf.d/01_mariadb.conf && \
    echo "command=/usr/bin/mysqld_safe --datadir='/var/lib/mysql' --user=mysql" >> /etc/supervisor/conf.d/01_mariadb.conf && \
    echo "autostart=true" >> /etc/supervisor/conf.d/01_mariadb.conf && \
    echo "autorestart=true" >> /etc/supervisor/conf.d/01_mariadb.conf && \
    echo "stdout_logfile=/dev/stdout" >> /etc/supervisor/conf.d/01_mariadb.conf && \
    echo "stdout_logfile_maxbytes=0" >> /etc/supervisor/conf.d/01_mariadb.conf && \
    echo "redirect_stderr=true" >> /etc/supervisor/conf.d/01_mariadb.conf

# 配置 Redis 服务 (禁用持久化，适合容器环境)
RUN echo "[program:redis]" > /etc/supervisor/conf.d/02_redis.conf && \
    echo "command=/usr/bin/redis-server --save \"\" --appendonly no" >> /etc/supervisor/conf.d/02_redis.conf && \
    echo "autostart=true" >> /etc/supervisor/conf.d/02_redis.conf && \
    echo "autorestart=true" >> /etc/supervisor/conf.d/02_redis.conf && \
    echo "stdout_logfile=/dev/stdout" >> /etc/supervisor/conf.d/02_redis.conf && \
    echo "stdout_logfile_maxbytes=0" >> /etc/supervisor/conf.d/02_redis.conf && \
    echo "redirect_stderr=true" >> /etc/supervisor/conf.d/02_redis.conf

# 配置 myapp 服务 (包含等待 MariaDB 的逻辑)
RUN echo "[program:myapp]" > /etc/supervisor/conf.d/99_myapp.conf && \
    echo "command=sh -c 'while ! mysqladmin ping -h 127.0.0.1 --silent; do echo \"Waiting for MariaDB to be ready...\"; sleep 1; done; echo \"MariaDB is up, starting myapp.\"; /app/myapp --port 8849'" >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo "autostart=true" >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo "autorestart=true" >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo "stdout_logfile=/dev/stdout" >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo "stdout_logfile_maxbytes=0" >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo "redirect_stderr=true" >> /etc/supervisor/conf.d/99_myapp.conf

# 设置工作目录
WORKDIR /app

# 使用 COPY 并保持原始路径
COPY myapp /app/myapp
COPY assets /app/assets
COPY static /app/static

# 复制入口脚本
COPY scripts/docker-entrypoint.sh /docker-entrypoint.sh
# 赋予入口脚本执行权限
RUN chmod +x /docker-entrypoint.sh

# 暴露应用程序端口
EXPOSE 8849

# 设置容器的入口点和默认命令
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
