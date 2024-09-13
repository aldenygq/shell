#!/bin/sh

#db_backups_conf.txt文件路径
db_backups_conf="/wocloud/shell/es_deletel_history_index_config.txt"

#判断文件是否存在
if [ -f "${db_backups_conf}" ];then
	
	echo $(date +'%Y-%m-%d %H:%M:%S')" 发现文件配置信息文件存在"

	#获取等号前内容，作为map中的Key值
	dbArrOne=($(awk -F'[=]' '{print $1}' ${db_backups_conf} ))
	
	#获取等号后内容，作为map中的value值
	dbArrTwo=($(awk -F'[=]' '{print $2}' ${db_backups_conf}))

	#创建一个空map
	declare -A map=()
	
	#通过循环，将db_backups_conf配置文件中的信息存储在map中
	for((i=0;i<${#dbArrOne[@]};i++))
	do
		map[${dbArrOne[i]}]=${dbArrTwo[i]}
	done	

	#获取要监测集群节点IP和端口号组合的字符串
	ipPortsStr=${map["ipAddressAndPorts"]}
	
	#获取收件人的邮件账号的字符串
	semdEmailTo=${map["semdEmailTo"]}
	
	#获取要删除的索引名称的字符串
	deleteIndexName=${map["deleteIndexName"]}
	
	#获取默认的字符串分隔符
	old_ifs="$IFS"
	
	#设置字符串分隔符为逗号
	IFS=","

	#将要备份的索引名称value值的字符串进行分隔，获取一个数组
	ipPortArr=($ipPortsStr)
	
	#将收件人的邮件账号value值的字符串进行分隔，获取一个数组
	semdEmailToArr=($semdEmailTo)
	
	#将删除索引名称value值的字符串进行分隔，获取一个数组
	deleteIndexNameArr=($deleteIndexName)

	#将字符串的分隔符重新设置为默认的分隔符
	IFS="$old_ifs"
	
	
	#定义一个是否需要发送异常提醒邮件变量
	isSendEmailStr=0
	
	#定义一个出现异常集群节点ip和端口号存储的变量
	errorIpPort=""
	
	#定义一个集群中可用的节点ip和端口号变量
	isUseIpPort=""
	
	#执行命令
	{
	
		#遍历集群节点
		for ipPort in ${ipPortArr[@]};
		do
		
			#检测es访问地址是否有效
			esStatus=$(curl -s -m 5 -IL http://${ipPort}|grep 200)
			if [ "$esStatus" == "" ];then
			
					echo $(date +'%Y-%m-%d %H:%M:%S')" es地址访问异常："${ipPort}
					isSendEmailStr=1
					errorIpPort=${errorIpPort}""${ipPort}","
				else
			
					isUseIpPort=${ipPort}
				
			fi
			
		
		done
		
	} || {
		isSendEmailStr=1
	}
	

	#判断命令执行是否有异常，如果有异常就发送邮件
	if [ ${isSendEmailStr} == "0" ];then
			echo $(date +'%Y-%m-%d %H:%M:%S')" 执行es集群节点监测全部正常"
			#集群中所有节点都正常，开始执行删除历史索引命令
		
			#获取保存指定天数之前日期，并按照格式进行格式化
			delday=$(date -d ${map["saveIndexDays"]}' days ago' +${map["dayFormate"]})
			echo $(date +'%Y-%m-%d %H:%M:%S')" 要删除的索引中带日期的时间为:"${delday}
			
		
			#遍历要删除的索引名称
			for indexName in ${deleteIndexNameArr[@]};
			do
				
				#替换索引名中*为要删除的日期字符串
				delIndexName=${indexName//\*/${delday}}
				echo $(date +'%Y-%m-%d %H:%M:%S')" 开始删除索引:"${delIndexName}
				
				#执行删除索引命令
				${map["curlPath"]} -XDELETE http://${isUseIpPort}/${delIndexName}
				
				echo $(date +'%Y-%m-%d %H:%M:%S')" 成功删除索引:"${delIndexName}
				
			done
		else 
			echo $(date +'%Y-%m-%d %H:%M:%S')" 执行es集群节点监测有异常，开始发送邮件通知管理员"
			
			#遍历收件人的邮箱地址，逐个发送邮件
			for email in ${semdEmailToArr[@]};
			do
				echo $(date +'%Y-%m-%d %H:%M:%S')" 开始发送邮件："${email}

				echo ""${map["sendEmailContent"]}",异常节点信息如下："${errorIpPort} | mail -s ""${map["sendEmailTitle"]} ${email}
			done
			
			echo $(date +'%Y-%m-%d %H:%M:%S')" 执行es集群节点监测有异常，成功发送邮件通知管理员"
	
	fi
	
	echo $(date +'%Y-%m-%d %H:%M:%S')" 脚本执行完毕"


else
	echo "文件不存在"
fi
