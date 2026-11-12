#!/bin/bash
# rfix <容器内路径...>  把 root 写出来的文件属主交还 App
# token 来源优先级：环境变量 > /usr/local/etc/dshgo.token > 烤入值
TOK="${DSH_ROOTD_TOKEN:-}"
[ -n "$TOK" ] || { [ -r /usr/local/etc/dshgo.token ] && TOK=$(cat /usr/local/etc/dshgo.token 2>/dev/null); }
[ -n "$TOK" ] || TOK="__TOKEN__"
PORT="${DSH_ROOTD_HTTP:-7000}"
[ $# -eq 0 ] && { echo "用法: rfix <容器内路径...>  例：rfix /root/.dsh /tmp/x"; exit 1; }
curl -s -m 120 -X POST --data-binary "$*" "http://127.0.0.1:$PORT/api/rfix?token=$TOK"
echo
