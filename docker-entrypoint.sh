#!/bin/sh
# 使用 /bin/sh，因为 Alpine 默认不安装 bash
set -e

# 检查 MariaDB 数据目录是否已初始化
if [ -d "/var/lib/mysql/mysql" ]; then
    echo "MariaDB data directory already exists, skipping initialization."
else
    echo "MariaDB data directory not found, initializing database..."

    # Alpine 使用 mariadb-install-db
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql

    # 在后台启动 MariaDB
    /usr/bin/mysqld_safe --datadir='/var/lib/mysql' --socket='/var/run/mysqld/mysqld.sock' &
    MARIADB_PID=$!

    # 等待 MariaDB 准备就绪
    for i in $(seq 30 -1 0); do
        if mysqladmin ping -h localhost --socket='/var/run/mysqld/mysqld.sock' > /dev/null 2>&1; then
            break
        fi
        echo 'Waiting for database connection...'
        sleep 1
    done
    if [ "$i" = 0 ]; then
        echo >&2 'MariaDB startup failed.'
        exit 1
    fi

    echo "Database is up. Setting root password and creating database."

    # 执行数据库设置命令
    # 注意：Alpine 的 mariadb-client 默认可能需要指定 socket
    mysql --socket='/var/run/mysqld/mysqld.sock' -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'Iwe@12345678';"
    mysql --socket='/var/run/mysqld/mysqld.sock' -e "FLUSH PRIVILEGES;"
    mysql --socket='/var/run/mysqld/mysqld.sock' -u root -p'Iwe@12345678' -e "CREATE DATABASE iwedb;"

    echo "Database initialization complete."

    # 停止临时的 MariaDB 服务
    if ! kill -s TERM "$MARIADB_PID" || ! wait "$MARIADB_PID"; then
        echo >&2 'Failed to stop temporary MariaDB server.'
        exit 1
    fi
    echo "Temporary MariaDB server stopped."
fi

# 执行传递给此脚本的命令 (即 Dockerfile 中的 CMD)
exec "$@"
