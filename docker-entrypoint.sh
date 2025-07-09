#!/usr/bin/env bash
set -e

# 运行数据库初始化
/init_mariadb.sh

# 如果使用VOLUMEs需要确保目录存在并设置权限
mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld
mkdir -p /var/lib/mysql && chown mysql:mysql /var/lib/mysql

# 执行主命令
exec "$@"
