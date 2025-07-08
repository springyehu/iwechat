# 使用 Alpine 作为基础镜像，适合多平台构建
FROM alpine:3.18

# 设置环境变量，避免交互式提示
ENV DEBIAN_FRONTEND=noninteractive

# 安装所有必要的软件包
# 包括：bash(用于脚本), qemu(运行x86_64程序), supervisor, redis, mariadb, tzdata(时区)
RUN apk update && \
    apk add --no-cache \
        bash \
        qemu-user-static \
        supervisor \
        redis \
        mariadb \
        mariadb-client \
        tzdata

# 设置容器时区为上海
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

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

# *** 关键修改：使用 COPY 并保持原始路径 ***
COPY myapp /app/myapp
COPY assets /app/assets
COPY static /app/static

# 复制入口脚本 (假设它在您仓库的 scripts 目录下)
COPY scripts/docker-entrypoint.sh /docker-entrypoint.sh
# 赋予入口脚本执行权限
RUN chmod +x /docker-entrypoint.sh

# 暴露应用程序端口
EXPOSE 8849

# 设置容器的入口点和默认命令
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
