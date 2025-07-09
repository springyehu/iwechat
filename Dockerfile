# 阶段 1: 获取 QEMU 静态二进制文件
FROM alpine:latest AS qemu-builder
RUN apk add --no-cache qemu-x86_64

# 阶段 2: 最终的 Alpine 镜像
FROM alpine:latest

# 如果不需要跨架构支持，可以移除以下两行
COPY --from=qemu-builder /usr/bin/qemu-x86_64 /usr/bin/qemu-x86_64-static

# 安装依赖项
RUN apk add --no-cache \
    tzdata \
    redis \
    supervisor \
    mariadb \
    mariadb-client \
    mariadb-server-utils \
    curl \
    ca-certificates \
    shadow \
    coreutils \
    libc6-compat \
    bash

# 设置时区
RUN cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

# 创建必要目录并设置权限
RUN mkdir -p /var/run/mysqld && \
    chown mysql:mysql /var/run/mysqld && \
    mkdir -p /etc/supervisor/conf.d && \
    mkdir -p /var/lib/mysql && \
    chown -R mysql:mysql /var/lib/mysql

# 创建入口脚本
RUN echo '#!/usr/bin/env bash' > /docker-entrypoint.sh && \
    echo 'set -e' >> /docker-entrypoint.sh && \
    echo '' >> /docker-entrypoint.sh && \
    echo '# 内联的数据库初始化脚本' >> /docker-entrypoint.sh && \
    echo 'if [ ! -d "/var/lib/mysql/mysql" ]; then' >> /docker-entrypoint.sh && \
    echo '  echo "🌟 初始化 MariaDB 数据库..."' >> /docker-entrypoint.sh && \
    echo '  # 安装系统数据库' >> /docker-entrypoint.sh && \
    echo '  mysql_install_db --user=mysql --datadir=/var/lib/mysql' >> /docker-entrypoint.sh && \
    echo '' >> /docker-entrypoint.sh && \
    echo '  # 启动临时服务' >> /docker-entrypoint.sh && \
    echo '  echo "🟠 启动临时 MariaDB 服务进行初始化..."' >> /docker-entrypoint.sh && \
    echo '  mysqld_safe --datadir="/var/lib/mysql" --socket="/var/run/mysqld/mysqld.sock" --user=mysql &' >> /docker-entrypoint.sh && \
    echo '  pid=$!' >> /docker-entrypoint.sh && \
    echo '' >> /docker-entrypoint.sh && \
    echo '  # 等待MySQL套接字创建' >> /docker-entrypoint.sh && \
    echo '  timeout=30' >> /docker-entrypoint.sh && \
    echo '  while [ ! -S /var/run/mysqld/mysqld.sock ]; do' >> /docker-entrypoint.sh && \
    echo '    if [ $timeout -le 0 ]; then' >> /docker-entrypoint.sh && \
    echo '      echo "⛔ 等待 MariaDB socket 超时"' >> /docker-entrypoint.sh && \
    echo '      exit 1' >> /docker-entrypoint.sh && \
    echo '    fi' >> /docker-entrypoint.sh && \
    echo '    echo "⏳ 等待 MariaDB 启动 ($timeout)..."' >> /docker-entrypoint.sh && \
    echo '    sleep 1' >> /docker-entrypoint.sh && \
    echo '    timeout=$((timeout-1))' >> /docker-entrypoint.sh && \
    echo '  done' >> /docker-entrypoint.sh && \
    echo '' >> /docker-entrypoint.sh && \
    echo '  # 设置root密码和创建应用数据库' >> /docker-entrypoint.sh && \
    echo '  echo "🔐 设置 root 密码和创建数据库..."' >> /docker-entrypoint.sh && \
    echo '  mysql --socket="/var/run/mysqld/mysqld.sock" <<-EOSQL' >> /docker-entrypoint.sh && \
    echo '    UPDATE mysql.user SET Password=PASSWORD("Iwe@12345678") WHERE User="root";' >> /docker-entrypoint.sh && \
    echo '    DELETE FROM mysql.user WHERE User="";' >> /docker-entrypoint.sh && \
    echo '    CREATE DATABASE IF NOT EXISTS iwedb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' >> /docker-entrypoint.sh && \
    echo '    FLUSH PRIVILEGES;' >> /docker-entrypoint.sh && \
    echo 'EOSQL' >> /docker-entrypoint.sh && \
    echo '' >> /docker-entrypoint.sh && \
    echo '  # 安全关闭临时服务' >> /docker-entrypoint.sh && \
    echo '  echo "🛑 关闭临时 MariaDB 服务..."' >> /docker-entrypoint.sh && \
    echo '  if ! mysqladmin --socket="/var/run/mysqld/mysqld.sock" -u root -pIwe@12345678 shutdown; then' >> /docker-entrypoint.sh && \
    echo '    echo "⚠️  无法正常关闭 MariaDB，强制终止进程"' >> /docker-entrypoint.sh && \
    echo '    kill -TERM $pid' >> /docker-entrypoint.sh && \
    echo '    wait $pid' >> /docker-entrypoint.sh && \
    echo '  fi' >> /docker-entrypoint.sh && \
    echo 'else' >> /docker-entrypoint.sh && \
    echo '  echo "ℹ️  MariaDB 已初始化，跳过初始化"' >> /docker-entrypoint.sh && \
    echo 'fi' >> /docker-entrypoint.sh && \
    echo '' >> /docker-entrypoint.sh && \
    echo '# 确保目录权限正确' >> /docker-entrypoint.sh && \
    echo 'chown -R mysql:mysql /var/lib/mysql' >> /docker-entrypoint.sh && \
    echo 'chown -R mysql:mysql /var/run/mysqld' >> /docker-entrypoint.sh && \
    echo 'mkdir -p /var/run/mysqld' >> /docker-entrypoint.sh && \
    echo 'mkdir -p /var/lib/mysql' >> /docker-entrypoint.sh && \
    echo '' >> /docker-entrypoint.sh && \
    echo '# 执行主命令' >> /docker-entrypoint.sh && \
    echo 'exec "$@"' >> /docker-entrypoint.sh && \
    chmod +x /docker-entrypoint.sh

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

# 配置 myapp 服务
RUN echo "[program:myapp]" > /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'command=bash -c "until mysqladmin ping -h localhost --socket=/var/run/mysqld/mysqld.sock --silent; do sleep 1; done; /usr/bin/qemu-x86_64-static /app/myapp --port 8849"' >> /etc/supervisor/conf.d/99_myapp.conf && \
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

# 赋予应用执行权限
RUN chmod +x /app/myapp

# 暴露应用程序端口
EXPOSE 8849

# 设置容器的入口点和默认命令
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
