#!/bin/bash

# shell脚本主要干了以下下这些事：
# 1、检查是否以 root 用户身份运行，并且定义了一些变量，如 Nginx 版本、临时目录、脚本目录和安装目录等。
# 2、创建了一个错误处理函数 command_status_check，用于检查命令执行结果并处理可能出现的错误。
# 3、创建了一个名为 www 的用户，并安装了 Nginx 所需的依赖包。
# 4、下载、解压、配置、编译和安装了 Nginx，包括一些常用的模块和选项。
# 5、配置了 Nginx，包括设置用户、指定日志路径、配置 http 块等。
# 6、创建了一个简单的虚拟主机配置文件 test.conf，包含 https配置和 php。
# 7、创建了一个定时任务脚本 nginx_logs.sh，用于Nginx日志切割，定期清理 Nginx 日志文件。
# 8、将定时任务添加到 cron 中，每天凌晨执行日志清理脚本。
# 9、最后输出一条安装和配置完成的提示消息。

# 定义变量
###指定nginx安装版本
nginx_version=1.24.0
tmp_dir=/usr/local/data/soft
scripts_dir=/home/scripts
install_dir=/usr/local/nginx

# 检查是否为root用户运行
if [ "$(id -u)" != "0" ]; then
    echo "Error: You must be root to run this script"
    exit 1
fi

# 错误处理函数
command_status_check(){
    if [ $? -ne 0 ]; then
        echo "$1"
        exit 1
    fi
}

# 创建用户并安装依赖
# 检查是否存在www用户
if ! id -u www &>/dev/null; then
    echo "Creating www user..."
    useradd www -d $install_dir/www -s /sbin/nologin
    echo "www user created."
fi

mkdir -p $tmp_dir && mkdir -p $scripts_dir

# 安装依赖
yum install gcc gcc-c++ make pcre-devel wget openssl-devel zlib-devel -y

# 下载、编译和安装Nginx
cd $tmp_dir
wget -q -nc http://nginx.org/download/nginx-${nginx_version}.tar.gz
tar zxf nginx-${nginx_version}.tar.gz
cd nginx-${nginx_version}
./configure --prefix=$install_dir/nginx-${nginx_version} --user=www --group=www  \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_gzip_static_module \
    --with-pcre \
    --with-http_v2_module \
    --with-http_secure_link_module \
    --with-stream \
    --with-openssl-opt=enable-tlsext \
    --with-http_flv_module
command_status_check "Nginx - 平台环境检查失败！"
make -j 4
command_status_check "Nginx - 编译失败！"
make install
command_status_check "Nginx - 安装失败！"

# 配置Nginx
cd $install_dir
ln -s nginx-${nginx_version} nginx
mkdir -p $install_dir/nginx/conf/{vhosts,cert}
#替换nginx默认配置
cat <<'EOF'  > $install_dir/nginx/conf/nginx.conf
user www www;
worker_processes 4;
worker_cpu_affinity 0001 0010 0100 1000;
worker_rlimit_nofile 65535;
error_log logs/error.log error;
pid     logs/nginx.pid;
events {
use epoll;
worker_connections 65535;
}

http {
    include mime.types;
    default_type application/octet-stream;
    server_tokens off;
    server_name_in_redirect off;

    gzip on;
    gzip_min_length 1k;
    gzip_comp_level 2;
    gzip_http_version 1.1;
    gzip_types text/plain text/css application/x-javascript application/xml text/javascript text/xml;
    gzip_buffers 4 128k;

    server_names_hash_bucket_size 128;
    client_max_body_size 100m;
    client_header_buffer_size 32k;
    large_client_header_buffers 4 32k;


    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
        '$status $body_bytes_sent "$http_referer" '
        '"$http_user_agent" "$http_x_forwarded_for" $upstream_response_time $request_time';

    access_log off;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;

    client_header_timeout 3m;
    client_body_timeout 3m;
    send_timeout 3m;
    keepalive_timeout 75 20;

    fastcgi_intercept_errors on;
    fastcgi_connect_timeout 300;
    fastcgi_send_timeout 300;
    fastcgi_read_timeout 300;
    fastcgi_buffer_size 32k;
    fastcgi_buffers 4 64k;
    fastcgi_busy_buffers_size 128k;
    fastcgi_temp_file_write_size 128k;

    include vhosts/*.conf;#开启虚拟主机
}
EOF
cat <<"EOF" > $install_dir/nginx/conf/vhosts/test.conf
server {
        listen 80;
        server_name  www.test.com test.com;#替换成真实域名
        if ( $host = 'test.com' ){
               rewrite ^/(.*)$ https://test.com/$1 permanent;
        }
        if ( $host = 'www.test.com' ){
               rewrite ^/(.*)$ https://test.com/$1 permanent;
        }
}
server {
        listen 443 ssl;

        server_name www.test.comtest.com; #替换成真实域名
        if ( $host = 'www.test.com' ){
               rewrite ^/(.*)$ https://test.com/$1 permanent;
        }
        #nginx/conf目录下新建cert目录，用于存放https证书文件
        ssl_certificate   cert/test.pem; #替换成域名pem
        ssl_certificate_key  cert/test.key;#替换成域名key
        ssl_session_timeout 5m;
        ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE:ECDH:AES:HIGH:!NULL:!aNULL:!MD5:!ADH:!RC4;
        ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
        ssl_prefer_server_ciphers on;
        access_log  logs/access.log main;
        root /usr/local/data/www;
        index   index.php;
        location / {
                try_files $uri $uri/ /index.php$is_args$args;
                }
        location ~ \.php$ {
                fastcgi_pass 127.0.0.1:9000;
                fastcgi_index  index-test.php;
                fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
                include        fastcgi_params;
        }
        location ~* \.(svn|git|gitignore|DS|ssh|md|release|example|conf|env|json|log|zip|rar|gz|7z)(.*) {
                deny all;
        }
}
EOF


# 创建定时清理日志的脚本
cat <<'EOF' > $scripts_dir/nginx_logs.sh
#!/bin/bash

Date=$(date +%F.%H --date="-1 hours")
NginxPid=/usr/local/data/nginx/logs/nginx.pid
DelTime=$(date +%F --date="-10 days")

cd /usr/local/data/nginx/logs

for LogFile in *.log
do
    if [ -e "${LogFile}" ]; then
        mv -f "${LogFile}" "${LogFile}.${Date}"
    else
        exit 0
    fi
done

if [ -e "${NginxPid}" ]; then
    kill -HUP $(cat "${NginxPid}")
fi

rm -f ./*${DelTime}*

EOF

# 启动Nginx，需要替换域名和上传https证书后再启动
#$install_dir/nginx/sbin/nginx
#command_status_check "Nginx - 启动失败！"

# 添加定时任务，每天凌晨执行清理脚本
echo "0 0 * * * $scripts_dir/nginx_logs.sh >>/dev/null" >> /var/spool/cron/root

# 结束提示
echo "Nginx安装和配置完成！"
