#!/bin/bash

# 设置备份目录
backup_dir=$2

# 设置要备份的文件或目录
files_to_backup=$1

# 创建一个日期时间戳
timestamp=$(date +%F_%T)

# 备份文件
tar -czvf "${backup_dir}/backup_${timestamp}.tar.gz" ${files_to_backup}
