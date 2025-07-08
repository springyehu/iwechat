#!/bin/sh
set -e # 如果任何命令失败，立即退出脚本

# 检查 MariaDB 数据目录是否已初始化
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "MariaDB data directory not found. Initializing database..."
    
    # 初始化数据库。`--user=mysql` 确保文件权限正确
    mysql_install_db --user=mysql --datadir=/var/lib/mysql

    # 启动一个临时的 MariaDB 服务用于设置密码和数据库
    mysqld_safe --datadir='/var/lib/mysql' --socket='/var/run/mysqld/mysqld.sock' --user=mysql &
    
    # 等待 MariaDB socket 文件出现，表示服务已基本启动
    timeout=30
    while [ ! -S /var/run/mysqld/mysqld.sock ]; do
        if [ "$timeout" -eq 0 ]; then
            echo "Timed out waiting for MariaDB socket to be created."
            exit 1
        fi
        sleep 1
        timeout=$((timeout-1))
    done

    echo "Temporary MariaDB server started. Setting up user and database..."

    # 执行数据库初始化SQL命令
    # 使用 SET PASSWORD 代替 ALTER USER，兼容性更好
    # 将所有命令合并到一个 heredoc 中，更高效
    mysql --socket='/var/run/mysqld/mysqld.sock' <<-EOSQL
        SET PASSWORD FOR 'root'@'localhost' = PASSWORD('Iwe@12345678');
        CREATE DATABASE IF NOT EXISTS iwedb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        FLUSH PRIVILEGES;
EOSQL

    # 关闭临时服务
    # 使用 mysqladmin shutdown 来安全关闭
    if ! mysqladmin --socket='/var/run/mysqld/mysqld.sock' -u root -p'Iwe@12345678' shutdown; then
        echo "Could not shut down temporary MariaDB server. Killing it..."
        # 如果安全关闭失败，强制杀死进程
        pkill mysqld
    fi

    echo "Database initialization complete."
else
    echo "MariaDB data directory already exists. Skipping initialization."
fi

# 执行传递给 entrypoint 的原始命令（例如，启动 supervisord）
echo "Starting main process: $@"
exec "$@"
