#!/bin/bash

# 检查kubeconfig文件中所有上下文的有效期，并输出提醒信息

# 定义kubeconfig文件路径
KUBECONFIG="${HOME}/.kube/config"

# 检查kubeconfig文件中所有上下文的有效期
kubectl config get-contexts --output=name | while read context; do
  # 获取当前上下文的信息
  CURRENT_CONTEXT=$(kubectl config current-context)
  EXPIRY=$(kubectl config get-contexts "$context" -o jsonpath='{.contexts[?(@.name == "'"${context}"'")].expires}')

  # 如果上下文有过期时间，计算剩余天数
  if [[ $EXPIRY != "" ]]; then
    EXPIRY_LEFT_DAYS=$(( ($(date -d "$EXPIRY" +%s) - $(date +%s)) / (3600*24) ))

    # 如果剩余天数小于等于30天，输出警告信息
    if [[ $EXPIRY_LEFT_DAYS -le 30 ]]; then
      echo "警告: 上下文 '${context}' 将在 ${EXPIRY_LEFT_DAYS} 天后过期."
    fi
  fi
done
