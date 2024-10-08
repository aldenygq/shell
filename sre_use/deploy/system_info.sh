#!/bin/bash

#[网络部分]
net_work=`[[ $(curl -o /dev/null --connect-timeout 3 -s -w "%{http_code}" www.baidu.com) -eq 200 ]] && echo yes || echo no`
ip_local=`ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | egrep -v  "^127" | head -n 1`

#[cpu部分]
cpu_info=`awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//'`
cpu_pinlv=`awk -F: '/cpu MHz/ {freq=$2} END {print freq}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//'`
cpu_hexin=`awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo`

#[内存部分]
mem_zong=`free -m | awk '/Mem/ {print $2}'`
men_sheng=`free -m | awk '/Mem/ {print $4}'`
swa_zong=`free -m | awk '/Swap/ {print $2}'`
swa_sheng=`free -m | awk '/Swap/ {print $4}'`

#[硬盘部分]
disk_zong=`df -Th | grep '/dev/' | awk '{print $3}' | head -n 1`
disk_sheng=`df -Th | grep '/dev/' | awk '{print $5}' | head -n 1`

#[其它]
time_local=`awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60;d=$1%60} {printf("%ddays, %d:%d:%d\n",a,b,c,d)}' /proc/uptime`
jiagou=`uname -m`
hostname=`hostname`

#判断是否centos或ubuntu
if cat /proc/version | grep -Eqi "ubuntu"; then
        banben=`lsb_release -a`
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
        banben=`awk '{print ($1,$3~/^[0-9]/?$3:$4)}' /etc/redhat-release`
fi

cn_info() { #全部信息
    clear
    echo "主机名：  $hostname"
    echo "版本：    $banben"
    echo "架构：    $jiagou"
    echo
    echo "cpu信息： $cpu_info"
    echo "cpu频率： $cpu_pinlv"
    echo "cpu核心： $cpu_hexin"
    echo
    echo "总内存：  $mem_zong"
    echo "剩内存：  $men_sheng"
    echo "总swap：  $swa_zong"
    echo "剩swap：  $swa_sheng"
    echo
    echo "根目录：  $disk_zong"
    echo "根剩余：  $disk_sheng"
    echo
    echo "是否联网：$net_work"
    echo "本地ip：  $ip_local"
    echo
    echo "开机：    $time_local"
}

cn_info
