# 阶段 1: 获取 QEMU 静态二进制文件（如果需要）
FROM alpine:latest AS qemu-builder
RUN apk add --no-cache qemu-x86_64

# 阶段 2: 最终的 Alpine 镜像
FROM alpine:latest

# 如果不需要跨架构支持，可以移除以下两行
COPY --from=qemu-builder /usr/bin/qemu-x86_64 /usr/bin/qemu-x86_64-static

# 安装依赖项 - 添加了 mariadb-server-utils 和 bash
RUN apk add --no-cache \
    tzdata \
    redis \
    supervisor \
    mariadb \
    mariadb-client \
    mariadb-server-utils \  # 提供 mysql_install_db 等工具
    curl \
    ca-certificates \
    shadow \
    coreutils \
    libc6-compat \        # 解决 musl/glibc 兼容性问题
    bash                  # 提供更好的脚本支持

# 设置时区为亚洲/上海
RUN cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

# 创建必要的目录并设置权限
RUN mkdir -p /var/run/mysqld && \
    chown mysql:mysql /var/run/mysqld && \
    mkdir -p /etc/supervisor/conf.d

# 创建 supervisor 主配置文件
RUN echo "[supervisord]" > /etc/supervisord.conf && \
    echo "nodaemon=true" >> /etc/supervisord.conf && \
    echo "logfile=/dev/null" >> /etc/supervisord.conf && \
    echo "pidfile=/var/run/supervisord.pid" >> /etc/supervisord.conf && \
    echo "" >> /etc/supervisord.conf && \
    echo "[include]" >> /etc/supervisord.conf && \
    echo "files = /etc/supervisor/conf.d/*.conf" >> /etc/supervisord.conf

# 配置 MariaDB 服务
RUN echo "[program:mariadb]" > /etc/supervisor/conf.d/01_mariadb.conf && \
    echo "command=/usr/bin/mysqld_safe --datadir='/var/lib/mysql' --socket='/var/run/mysqld/mysqld.sock' --user=mysql" >> /etc/supervisor/conf.d/01_mariadb.conf && \
    echo "autostart=true" >> /etc/supervisor/conf.d/01_mariadb.conf && \
    echo "autorestart=true" >> /etc/supervisor/conf.d/01_mariadb.conf && \
    echo "stdout_logfile=/dev/stdout" >> /etc/supervisor/conf.d/01_mariadb.conf && \
    echo "stdout_logfile_maxbytes=0" >> /etc/supervisor/conf.d/01_mariadb.conf && \
    echo "redirect_stderr=true" >> /etc/supervisor/conf.d/01_mariadb.conf

# 配置 Redis 服务
RUN echo "[program:redis]" > /etc/supervisor/conf.d/02_redis.conf && \
    echo "command=/usr/bin/redis-server --save \"\" --appendonly no" >> /etc/supervisor/conf.d/02_redis.conf && \
    echo "autostart=true" >> /etc/supervisor/conf.d/02_redis.conf && \
    echo "autorestart=true" >> /etc/supervisor/conf.d/02_redis.conf && \
    echo "stdout_logfile=/dev/stdout" >> /etc/supervisor/conf.d/02_redis.conf && \
    echo "stdout_logfile_maxbytes=0" >> /etc/supervisor/conf.d/02_redis.conf && \
    echo "redirect_stderr=true" >> /etc/supervisor/conf.d/02_redis.conf

# 更新 myapp 服务 - 更健壮的等待检测
RUN echo "[program:myapp]" > /etc/supervisor/conf.d/99_myapp.conf && \
    echo "command=bash -c 'until mysqladmin ping -h localhost --socket=/var/run/mysqld/mysqld.sock --silent; do sleep 1; done; echo \"MariaDB is ready\"; /app/myapp --port 8849'" >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo "autostart=true" >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo "autorestart=true" >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo "stdout_logfile=/dev/stdout" >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo "stdout_logfile_maxbytes=0" >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo "redirect_stderr=true" >> /etc/supervisor/conf.d/99_myapp.conf

# 设置工作目录
WORKDIR /app

# 复制应用程序文件
COPY myapp /app/myapp
COPY assets /app/assets
COPY static /app/static

# 复制入口脚本和数据库初始化脚本
COPY scripts/docker-entrypoint.sh /docker-entrypoint.sh
COPY scripts/init_mariadb.sh /init_mariadb.sh  # 新加入的初始化脚本

# 赋予入口脚本执行权限
RUN chmod +x /docker-entrypoint.sh /init_mariadb.sh

# 确保数据目录权限
RUN chown -R mysql:mysql /var/lib/mysql

# 暴露应用程序端口
EXPOSE 8849

# 设置容器的入口点和默认命令
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
