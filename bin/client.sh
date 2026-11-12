#!/bin/bash
# dsh-go root 客户端
#   r <命令...>          r - <<'X' ... X
#   rfix <容器内路径...>  把 root 写的文件属主交还 App
# 通道：127.0.0.1:<端口>，token 已在安装时写入本文件
# token 来源优先级：环境变量 > /usr/local/etc/dshgo.token > 烤入值
TOK="${DSH_ROOTD_TOKEN:-}"
[ -n "$TOK" ] || { [ -r /usr/local/etc/dshgo.token ] && TOK=$(cat /usr/local/etc/dshgo.token 2>/dev/null); }
[ -n "$TOK" ] || TOK="__TOKEN__"
HTTP_PORT="${DSH_ROOTD_HTTP:-7000}"
NC_PORT="${DSH_ROOTD_NC:-6000}"

if [ "${1:-}" = "-" ]; then CMD="$(cat)"
elif [ $# -eq 0 ]; then CMD='id'
else CMD="$*"; fi

TMP=$(mktemp 2>/dev/null || echo "/tmp/.r.$$")
cleanup() { rm -f "$TMP"; }
trap cleanup EXIT

newline() { # 保证输出以换行结尾
  [ -s "$1" ] && [ "$(tail -c 1 "$1" | od -An -tx1 | tr -d ' \n')" != "0a" ] && echo
  return 0
}

CODE=$(curl -s -m 120 -o "$TMP" -w '%{http_code}' -X POST --data-binary "$CMD" \
        "http://127.0.0.1:$HTTP_PORT/api/exec?token=$TOK" 2>/dev/null)

case "$CODE" in
  200) cat "$TMP"; newline "$TMP"; exit 0 ;;
  000) ;;  # 7000 没起来，退回老的一次性 nc 通道
  401)
    # 守护的 token 变了（重装/轮换），让它把客户端重写一遍再试一次
    curl -s -m 10 -X POST -o /dev/null "http://127.0.0.1:$HTTP_PORT/api/resync" 2>/dev/null
    CODE2=$(curl -s -m 120 -o "$TMP" -w '%{http_code}' -X POST --data-binary "$CMD" \
            "http://127.0.0.1:$HTTP_PORT/api/exec?token=$TOK" 2>/dev/null)
    if [ "$CODE2" = "200" ]; then cat "$TMP"; newline "$TMP"; exit 0; fi
    cat "$TMP"; echo; echo "[r] token 不匹配且自动同步失败，重装一次模块" >&2; exit 1 ;;
  *)   cat "$TMP"; echo; echo "[r] 通道返回 $CODE" >&2; exit 1 ;;
esac

{ printf '%s\n' "$TOK"; printf '%s\n' "$CMD"; } | /system/bin/nc -w 30 127.0.0.1 "$NC_PORT" 2>/dev/null
