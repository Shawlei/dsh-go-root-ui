#!/bin/bash
# dsh-go root 客户端
#   r <命令...>          r - <<'X' ... X
#   rfix <容器内路径...>  把 root 写的文件属主交还 App
# 通道：127.0.0.1:<端口>，token 已在安装时写入本文件
TOK="${DSH_ROOTD_TOKEN:-__TOKEN__}"
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
  401) cat "$TMP"; echo; echo "[r] token 不匹配：在模块 WebUI 点「更新客户端」" >&2; exit 1 ;;
  *)   cat "$TMP"; echo; echo "[r] 通道返回 $CODE" >&2; exit 1 ;;
esac

{ printf '%s\n' "$TOK"; printf '%s\n' "$CMD"; } | /system/bin/nc -w 30 127.0.0.1 "$NC_PORT" 2>/dev/null
