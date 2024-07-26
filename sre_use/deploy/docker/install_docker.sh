#!/bin/bash
# vim:sw=4:ts=4:et
<<INFO
DATE:2021-01-26
DESCRIBE:1、二进制方式安装/卸载Docker，可以指定数据盘作为Docker的存储盘   2、如果本地没有Docker二进制包会去官网下载，需确保网络可用
SYSTEM:CentOS7/RedHat7
WARNING:
MODIFY:2021-10-21:删除docker组之前先删除docker用户  2021-10-25:增加docker日志的设置
INFO

set -e

WORKDIR=$(cd `dirname $0`;pwd)
LOG_PATH=${WORKDIR}/docker.log
DOCKER_VERSION="18.09.0"
DOCKER_PKG_NAME="docker-${DOCKER_VERSION}.tgz"
DOCKER_URL="download.docker.com"
DOCKER_BIN_PATH="/usr/local/bin"
DOCKER_CONFIG="/usr/lib/systemd/system/docker.service"
DOCKER_STORAGE="/data/docker"       #使用逻辑卷时，挂载到该路径
VG_NAME="dockervg"
LV_NAME="${VG_NAME}_storage"

#${FUNCNAME[1]代表调用该函数的函数，$LINENO代表当前代码行号
Log(){
    local log_level=$1
    local log_info=$2
    local line=$3
    local script_name=$(basename $0)

    case ${log_level} in
    "INFO")
        echo -e "\033[32m$(date "+%Y-%m-%d %T.%N") [INFO]: ${log_info}\033[0m";;
    "WARN")
        echo -e "\033[33m$(date "+%Y-%m-%d %T.%N") [WARN]: ${log_info}\033[0m";;
    "ERROR")
        echo -e "\033[31m$(date "+%Y-%m-%d %T.%N") [ERROR ${script_name} ${FUNCNAME[1]}:$line]: ${log_info}\033[0m";;
    *)
        echo -e "${@}"
    ;;
    esac
}

# 检查当前环境
Check_Env(){
    local docker_status=$(systemctl is-active docker)
    if [[ ${docker_status} == "active" ]];then
    	systemctl enable docker
        Log WARN "Docker Is Installed" && exit 0
    elif command -v docker &> /dev/null;then
    	systemctl enable docker
        Log WARN "Docker Is Installed" && exit 0
    fi
    if ! grep '^docker:' /etc/group &> /dev/null;then
        groupadd docker
    fi
    if ! echo $PATH | grep "${DOCKER_BIN_PATH}" &> /dev/null;then
        Log ERROR "${DOCKER_BIN_PATH} Not In PATH Environment" $LINENO && exit 1
    fi
}

#配置内核
Config_Kernel(){
    echo "INFO:Begin Config Kernel..."
    local config_name="/etc/sysctl.conf"
    [[ ! -f ${config_name}.bak ]] && cp ${config_name}{,.bak}
    sed -i '/^net.ipv4.ip_forward/d' ${config_name}
    echo "net.ipv4.ip_forward = 1" >> ${config_name}
    sysctl -p
    echo "INFO:Config Kernel Success"
}

# 下载Docker二进制包
Download_Pkg(){
    Log INFO "Download Docker Binary Package......"
    local download_url="https://${DOCKER_URL}/linux/static/stable/x86_64/${DOCKER_PKG_NAME}"
    local http_code=$(curl -k -m 3  -s -o /dev/null -w %{http_code} ${DOCKER_URL})
    if ! echo ${http_code} | egrep '(^2|^3)' &> /dev/null;then
        Log ERROR "${DOCKER_URL} Unreachable,Please Check Network Or DNS" $LINENO && exit 1
    fi
    curl -kLO ${download_url}
    if tar -tf ${DOCKER_PKG_NAME} &> /dev/null;then
        Log INFO "Download Docker Success"
    else
        Log ERROR "Download Docker faild" $LINENO && exit 1
    fi
}

#配置docker的启动文件
Conf_Docker(){
    if [[ -f ${DOCKER_CONFIG} ]];then
        [[ ! -f ${DOCKER_CONFIG}.bak ]] && cp ${DOCKER_CONFIG}{,.bak}
    fi
    cat > ${DOCKER_CONFIG} << EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
ExecStart=${DOCKER_BIN_PATH}/dockerd -H unix://var/run/docker.sock
ExecReload=/bin/kill -s HUP $MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TimeoutStartSec=0
# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes
# kill only the docker process, not all processes in the cgroup
KillMode=process
# restart the docker process if it exits prematurely
Restart=always
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target
EOF
}

# 创建逻辑卷，当作Docker存储路径
Create_Lvm(){
    Log INFO "Begin Create LVM....."
    local disk_name=$1
    local disk_num=$(fdisk -l |grep "${disk_name}" |wc -l)
    [[ ${disk_num} -gt 1 ]] && Log ERROR "${disk_name} Is Used,Please Format or Change New Disk" $LINENO && exit 1
    if pvs | grep -w ${disk_name};then
        Log ERROR "${disk_name} Is Used,Please Format or Change New Disk" $LINENO && exit 1
    fi
    Log INFO "挂载磁盘为:${disk_name}"
    #创建卷组
    if ! vgs | grep -w "${VG_NAME}" >/dev/null;then  
        vgcreate "${VG_NAME}" "${disk_name}"
    else
        Log ERROR "${VG_NAME} Is Exist" $LINENO && exit 1
    fi
    #创建逻辑卷
    if ! lvs | grep -w "${LV_NAME}" >/dev/null;then
        lvcreate -n ${LV_NAME} -l 100%VG ${VG_NAME} -y
        mkfs.ext4 /dev/${VG_NAME}/${LV_NAME} >/dev/null
    else
        Log ERROR "${LV_NAME} Is Exist" $LINENO && exit 1           
    fi
    if lvs | grep -w ${LV_NAME};then
        Log INFO "${LV_NAME} Create Success"
    else
        Log ERROR "${LV_NAME} Create Faild" $LINENO && exit 1
    fi
    # 挂载逻辑卷
    if [[ ! -d ${DOCKER_STORAGE} ]];then
        mkdir -p ${DOCKER_STORAGE}
        local uuid=$(blkid | grep -w "${VG_NAME}-${LV_NAME}" |awk '{print $2}')
        [[ ! -f /etc/fstab.bak ]] && cp /etc/fstab{,.bak}
        sed -ri "s#(.*)${DOCKER_STORAGE}(.*)##" /etc/fstab        #防止多次写入相同的挂载内容
        echo "${uuid} ${DOCKER_STORAGE} ext4 defaults 0 0" >> /etc/fstab
        sed -i '/^$/d' /etc/fstab
        mount -a
        if df -h | grep -w "${DOCKER_STORAGE}$";then
            Log INFO "${DOCKER_STORAGE} Mount Success"
        else
            Log ERROR "${DOCKER_STORAGE} Mount Faild" $LINENO && exit 1
        fi
    else
        Log ERROR "${DOCKER_STORAGE} Is Exist" $LINENO && exit 1
    fi
}

# 删除逻辑卷
Remove_Lvm(){
    Log INFO "Begin Remove LVM....."
    local disk_name=$1
    if df -h | grep -w "${DOCKER_STORAGE}$" &> /dev/null;then
        umount ${DOCKER_STORAGE}
    fi
    [[ ! -f /etc/fstab.bak ]] && cp /etc/fstab{,.bak}
    sed -ri "s#(.*)${DOCKER_STORAGE}(.*)##" /etc/fstab
    sed -i '/^$/d' /etc/fstab
    #删除逻辑卷
    if lvs | grep -w "${LV_NAME}" >/dev/null;then
        lvremove -f /dev/${VG_NAME}/${LV_NAME}
    fi
    #删除卷组
    if vgs | grep -w "${VG_NAME}" >/dev/null;then
        vgremove ${VG_NAME}
    fi
    #删除物理卷
    if pvs | grep -w "${disk_name}" >/dev/null;then
        pvremove "${disk_name}"
    fi
    [[ -d ${DOCKER_STORAGE} ]] && rm -rf ${DOCKER_STORAGE}
    Log INFO "Remove LVM Success"
}

# 修改Docker存储路径
Modify_Docker_Storage(){
    [[ ! -d /etc/docker ]] && mkdir /etc/docker
    cat > /etc/docker/daemon.json << EOF
{
    "graph":"${DOCKER_STORAGE}",
    "registry-mirrors": ["https://8auvmfwy.mirror.aliyuncs.com"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "50m",
        "max-file":"3"
    }
}
EOF
}

Install_Docker(){
    local disk_name=$1
    Check_Env
    Config_Kernel
    Log INFO "Begin Install Docker ${DOCKER_VERSION}....."
    [[ -f /etc/sysconfig/docker ]] && mv /etc/sysconfig/docker /etc/sysconfig/docker.bak
    if [[ -n ${disk_name} ]];then
        Create_Lvm ${disk_name}
    fi 
    [[ ! -d ${DOCKER_STORAGE} ]] && mkdir -p ${DOCKER_STORAGE}
    Modify_Docker_Storage   
    [[ ! -f ${WORKDIR}/${DOCKER_PKG_NAME} ]] && Download_Pkg
    tar xvf ${DOCKER_PKG_NAME}
    chown .docker docker/*
    cp -ap docker/* ${DOCKER_BIN_PATH}
    Conf_Docker
    systemctl daemon-reload && systemctl enable docker
    systemctl start docker
    hash -r
    local docker_status=$(systemctl is-active docker)
    if [[ ${docker_status} == "active" ]];then
        docker -v
        Log INFO "Install Docker Success"
    else
        Log ERROR "Install Docker Faild" $LINENO && exit 1
    fi
}

Uninstall_Docker(){
    Log INFO "Begin Uninstall Docker......"
    local disk_name=$1
    local docker_status=$(systemctl is-active docker)
    if [[ ${docker_status} == "active" ]];then
    	local container_num=$(docker ps -aq)
        if [[ -n ${container_num} ]];then
            docker stop $(docker ps -aq)
        fi
        docker system prune -a -f
        systemctl disable docker
        systemctl stop docker
    else
        Log WARN "Docker Is Stop"
    fi
    rm -f ${DOCKER_BIN_PATH}/{containerd,containerd-shim,ctr,docker,dockerd,docker-init,docker-proxy,runc}
    rm -f /usr/bin/docker
    rm -rf /etc/docker
    [[ -f ${DOCKER_CONFIG} ]] && rm -f ${DOCKER_CONFIG} && systemctl daemon-reload
    if [[ -n ${disk_name} ]];then
        Remove_Lvm ${disk_name}
    else
        [[ -d /var/lib/docker ]] && rm -rf /var/lib/docker
    fi
    if id docker &> /dev/null;then
        userdel -r docker
    fi
    if grep '^docker:' /etc/group &> /dev/null;then
        groupdel docker
    fi
    [[ -f /etc/sysconfig/docker ]] && rm -f /etc/sysconfig/docker
    local docker_status=$(systemctl is-active docker)
    if [[ ${docker_status} != "active" ]];then
        if ! which docker &> /dev/null;then
            Log INFO "Uninstall Docker Success" && exit 0
        else
            Log ERROR "Uninstall Docker Faild" $LINENO && exit 1
        fi
    else
        Log ERROR "Uninstall Docker Faild" $LINENO && exit 1
    fi
}

#帮助信息
Help(){
	cat << EOF
Usage: 
=======================================================================
optional arguments:
    help                 提供帮助信息
    install              安装docker，存储路径为/var/lib/docker
    install /dev/xvde    安装docker,创建逻辑卷，存储路径为:${DOCKER_STORAGE}
    uninstall             卸载docker,如果安装时指定了磁盘，卸载也需要指定磁盘
EXAMPLE:
    bash install_docker.sh install /dev/xvde
    bash install_docker.sh uninstall /dev/xvde
    bash install_docker.sh install
    bash install_docker.sh uninstall
EOF
}

######################主程序######################
[[ $UID -ne 0 ]] && Log ERROR "Please Use Admin(root) Excute......" $LINENO | tee -a ${LOG_PATH} && exit 1
[[ $# -ne 1 && $# -ne 2 ]] && Help && exit 1

if [[ -n $2 ]];then
    if [[ -b $2 ]];then
        DISK_NAME=$2
        Log INFO "Docker数据盘为:${DISK_NAME}"
    else
        Log ERROR "$2 Not Is Disk Or Not Found" $LINENO | tee -a ${LOG_PATH} && exit 1
    fi
fi

case $1 in
install)
    Install_Docker ${DISK_NAME} | tee -a ${LOG_PATH};;
uninstall)
    Uninstall_Docker ${DISK_NAME} | tee -a ${LOG_PATH};;
help)
    Help;;
*)
    Log ERROR "Invalid option:bash `basename $0` help" $LINENO | tee -a ${LOG_PATH} && exit 1
esac
