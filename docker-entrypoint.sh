#!/bin/sh
set -e

if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "MariaDB data directory not found. Initializing database..."
    mysql_install_db --user=mysql --datadir=/var/lib/mysql
    mysqld_safe --datadir='/var/lib/mysql' --socket='/var/run/mysqld/mysqld.sock' --user=mysql &
    
    timeout=30
    while [ ! -S /var/run/mysqld/mysqld.sock ]; do
        if [ "$timeout" -eq 0 ]; then
            echo "Timed out waiting for MariaDB socket to be created." >&2
            exit 1
        fi
        sleep 1
        timeout=$((timeout-1))
    done

    echo "Temporary MariaDB server started. Setting up user and database..."
    mysql --socket='/var/run/mysqld/mysqld.sock' <<-EOSQL
        SET PASSWORD FOR 'root'@'localhost' = PASSWORD('Iwe@12345678');
        CREATE DATABASE IF NOT EXISTS iwedb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        FLUSH PRIVILEGES;
EOSQL
    echo "User and database created successfully."

    if ! mysqladmin --socket='/var/run/mysqld/mysqld.sock' -u root -p'Iwe@12345678' shutdown; then
        echo "Could not shut down temporary MariaDB server cleanly. Killing process..." >&2
        pkill mysqld
    fi
    echo "Database initialization complete."
else
    echo "MariaDB data directory already exists. Skipping initialization."
fi

echo "Starting main process: $@"
exec "$@"
