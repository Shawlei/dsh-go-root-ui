#!/bin/bash
# rfix <容器内路径...>  把 root 写出来的文件属主交还 App
TOK="${DSH_ROOTD_TOKEN:-__TOKEN__}"
PORT="${DSH_ROOTD_HTTP:-7000}"
[ $# -eq 0 ] && { echo "用法: rfix <容器内路径...>  例：rfix /root/.dsh /tmp/x"; exit 1; }
curl -s -m 120 -X POST --data-binary "$*" "http://127.0.0.1:$PORT/api/rfix?token=$TOK"
echo
