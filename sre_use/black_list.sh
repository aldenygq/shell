#! /bin/bash
#主要功能是 自动分析SSH登录失败日志，封禁多次尝试失败的IP地址以增强服务器安全

#分析日志提取攻击IP
cat /var/log/secure|awk '/sshd.*Failed password/ {for(i=1;i<=NF;i++) if($i=="from") {print $(i+1); break}}'|sort|uniq -c|awk '{print $2"="$1;}' > /root/black/black.txt

DEFINE="5" # 允许的失败次数阈值

for i in `cat /root/black/black.txt`
do

  IP=`echo $i |awk -F= '{print $1}'` # 提取IP
  NUM=`echo $i|awk -F= '{print $2}'` # 提取失败次数

  if [ $NUM -gt $DEFINE ]; then # 判断是否超过阈值
    grep $IP /etc/hosts.deny > /dev/null # 检查是否已封禁

    if [ $? -gt 0 ]; then
      echo "sshd:$IP" >> /etc/hosts.deny # 未封禁则执行封禁
    fi
  fi
done
