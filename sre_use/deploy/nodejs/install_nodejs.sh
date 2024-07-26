#!/bin/bash
# Author: zhpengfei
# Date: 2024-5-07
set -x

# 定义变量
base_home="/usr/local/data"
node_home=$base_home/node
soft_home="${base_home}/soft"
node_version="v18.19.1"
node_pkg="node-${node_version}-linux-x64.tar.gz"
node_src="node-${node_version}-linux-x64"

# 检查是否为root用户运行
if [ "$(id -u)" != "0" ]; then
    echo "Error: You must be root to run this script" >&2
    exit 1
fi

# 检查目录是否存在，不存在则创建
if [ ! -d "$base_home" ]; then
    mkdir -p "$base_home"
fi

# 下载 Node.js
cd "$base_home"
wget -nc "https://nodejs.org/dist/$node_version/$node_pkg"

tar xvf "$node_pkg" -C "$base_home"

# 创建软链接
cd "$base_home"
ln -s "$node_src" "node"

#删除安装包
rm -f $node_pkg

# 创建 npm 和 node 软链接
ln -s "$node_home/bin/npm" "/usr/bin/npm"
ln -s "$node_home/bin/node" "/usr/bin/node"

# 设置 npm 镜像
npm config set registry "https://registry.npmmirror.com"

# 安装全局工具
npm install -g pm2  yarn

# 创建 pm2 和 yarn 软链接
ln -s "$node_home/bin/pm2" "/usr/bin/pm2"
ln -s "$node_home/bin/yarn" "/usr/bin/yarn"

echo "Node.js and related tools install completed successfully."
