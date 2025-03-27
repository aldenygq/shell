#!/bin/bash

# 此脚本用于设置aws ecr镜像仓库配置，主要包含映像标签可变性和推送扫描配置，默认映像标签可变性为:Immutable,推送扫描配置默认打开。
# 2025-03-27

# 定义使用说明
usage() {
    echo "Usage: $0 <ak> <sk>"
    echo "ak:配置需要操作的账号ak"
    echo "sk:配置需要操作的账号sk"
    exit 1
}
# 校验参数数量
if [ $# -ne 2 ]; then
    usage
fi

export AWS_PAGER=""
ak=$1
sk=$2

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
