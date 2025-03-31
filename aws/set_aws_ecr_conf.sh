#!/bin/bash

# 此脚本用于设置aws ecr镜像仓库配置，主要包含映像标签可变性和推送扫描配置，默认映像标签可变性为:Immutable,推送扫描配置默认打开。
# 2025-03-27

# 定义使用说明
usage() {
    echo "Usage: $0 <account_type> <ak> <sk>"
    echo "ak:配置需要操作的账号ak"
    echo "sk:配置需要操作的账号sk"
    echo "account_type:配置认证的账号类型,海外账号:oversea,国内账号:inchina"
    exit 1
}
# 校验参数数量
if [ $# -ne 3 ]; then
    usage
fi

export AWS_PAGER=""
ak=$2
sk=$3
account_type=$1

if [ "$account_type" == "oversea" ]; then
    aws configure set region us-west-2
else
    aws configure set region cn-north-1
fi
aws configure set aws_access_key_id $ak
aws configure set aws_secret_access_key $sk

regions=`aws ec2 describe-regions --query 'Regions[*].[RegionName]' --output json  | jq -r '.[].[]'`
IFS=$'\n' read -rd '' -a regions_array <<< "$regions"
for region in "${regions_array[@]}"; do
    echo "region:$region"
    repositories=`aws ecr describe-repositories --region $region --query 'repositories[].repositoryName' --output json | jq -r '.[]'`
    IFS=$'\n' read -rd '' -a repositories_array <<< "$repositories"
    for repository in "${repositories_array[@]}"; do
        aws ecr put-image-tag-mutability --repository-name $repository --image-tag-mutability IMMUTABLE --region $region
        aws ecr put-image-scanning-configuration --repository-name $repository --image-scanning-configuration scanOnPush=true --region $region
    done
done
