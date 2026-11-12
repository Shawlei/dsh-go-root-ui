#!/system/bin/sh
# HTTP/1.1 守护的每连接实例：toybox nc -L 拉起，处理一个请求后退出。
# 路由：
#   GET  /  /app.js  /style.css          页面资源
#   GET  /api/ping                       存活探测（无鉴权）
#   GET  /api/status  /api/log?lines=N   状态 / 日志
#   POST /api/exec  /api/rfix            执行命令 / 交还文件属主
HERE="${0%/*}"
MODDIR="${DSHGO_MODDIR:-${HERE%/*}}"
. "$MODDIR/bin/common.sh"

MAX_BODY=65536

# ---------- 响应 ----------
send() { # status ctype body [extra]
  LEN=$(printf '%s' "$3" | wc -c | tr -d ' ')
  printf 'HTTP/1.1 %s\r\n' "$1"
  printf 'Content-Type: %s\r\n' "$2"
  printf 'Content-Length: %s\r\n' "$LEN"
  printf 'Cache-Control: no-store\r\n'
  printf 'Access-Control-Allow-Origin: *\r\n'
  printf 'Access-Control-Allow-Headers: *\r\n'
  printf 'Access-Control-Allow-Methods: GET,POST,OPTIONS\r\n'
  printf 'Access-Control-Expose-Headers: X-Exit-Code,X-Token-Tail\r\n'
  [ -n "$4" ] && printf '%s\r\n' "$4"
  printf 'Connection: close\r\n\r\n'
  printf '%s' "$3"
}

send_file() { # status ctype file
  LEN=$(wc -c < "$3" | tr -d ' ')
  printf 'HTTP/1.1 %s\r\n' "$1"
  printf 'Content-Type: %s\r\n' "$2"
  printf 'Content-Length: %s\r\n' "$LEN"
  printf 'Cache-Control: no-store\r\n'
  printf 'Connection: close\r\n\r\n'
  cat "$3"
}

# ---------- 请求 ----------
IFS= read -r reqline || { printf 'HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n'; exit 0; }
reqline=${reqline%$'\r'}
set -f
set -- $reqline
METHOD="$1"; TARGET="$2"
[ -z "$METHOD" ] && exit 0

case "$TARGET" in
  *\?*) P="${TARGET%%\?*}"; QP="${TARGET#*\?}" ;;
  *)    P="$TARGET";       QP="" ;;
esac
TOK=""
case "$QP" in *token=*) TOK="${QP#*token=}"; TOK="${TOK%%&*}" ;; esac

CL=0; HDR_TOKEN=""
while IFS= read -r h; do
  h=${h%$'\r'}
  [ -z "$h" ] && break
  case "$h" in
    [Cc]ontent-[Ll]ength:*) CL=$(printf '%s' "${h#*:}" | tr -d ' ') ;;
    [Xx]-[Tt]oken:*)        HDR_TOKEN=$(printf '%s' "${h#*:}" | tr -d ' ') ;;
  esac
done
[ -n "$HDR_TOKEN" ] && TOK="$HDR_TOKEN"

BODY=""
if [ "${CL:-0}" -gt 0 ] 2>/dev/null; then
  [ "${CL:-0}" -gt "$MAX_BODY" ] && { send "413 Payload Too Large" text/plain "命令太长（上限 64 KB）" ""; exit 0; }
  BODY=$(dd bs=1 count="$CL" 2>/dev/null)
fi

[ "$METHOD" = "OPTIONS" ] && { send "204 No Content" text/plain "" ""; exit 0; }

# ---------- 公开：存活探测 ----------
case "$P" in
  /api/ping)
    send "200 OK" text/plain "pong" ""
    exit 0 ;;
esac

# ---------- 公开：重装客户端 ----------
# 只把「当前 token」写进目标 App 自己的 rootfs（该目录只有该 App 能读），
# 别的 App 调用也拿不到任何东西；用来修「token 换了但客户端没跟上」。
case "$P" in
  /api/resync)
    [ "$METHOD" = "POST" ] || { send "405 Method Not Allowed" text/plain "用 POST"; exit 0; }
    if [ "$(id -u)" != "0" ]; then
      send "409 Conflict" text/plain "守护不是以 root 运行，无法读写 rootfs"
      exit 0
    fi
    OUT=$(sh "$MODDIR/bin/install-client.sh" 2>&1); RC=$?
    log_line "resync($RC)"
    send "200 OK" "text/plain; charset=utf-8" "$OUT" "X-Exit-Code: $RC"
    exit 0 ;;
esac

# ---------- 公开：前端资源 ----------
case "$P" in
  /|/index.html)
    if [ -f "$MODDIR/webroot/index.html" ]; then
      # 注意：这里不注入 token。否则任何能访问回环的 App 都能 GET / 拿到 root 凭证。
      send_file "200 OK" "text/html; charset=utf-8" "$MODDIR/webroot/index.html"
    else
      send "404 Not Found" text/plain "webroot/index.html 缺失"
    fi
    exit 0 ;;
  /app.js)
    [ -f "$MODDIR/webroot/app.js" ] \
      && send_file "200 OK" "application/javascript; charset=utf-8" "$MODDIR/webroot/app.js" \
      || send "404 Not Found" text/plain "app.js 缺失"
    exit 0 ;;
  /style.css)
    [ -f "$MODDIR/webroot/style.css" ] \
      && send_file "200 OK" "text/css; charset=utf-8" "$MODDIR/webroot/style.css" \
      || send "404 Not Found" text/plain "style.css 缺失"
    exit 0 ;;
  /favicon.ico)
    send "204 No Content" text/plain ""
    exit 0 ;;
esac

# ---------- 鉴权 ----------
VALID=$(get_token)
if [ -z "$VALID" ] || [ "$TOK" != "$VALID" ]; then
  send "401 Unauthorized" "application/json; charset=utf-8" '{"err":"bad token"}'
  exit 0
fi

# ---------- 需要 token ----------
case "$P" in
  /api/status)
    U=$(id -u)
    RS=$(find_rootfs 2>/dev/null)
    CLI=no; [ -n "$RS" ] && [ -x "$RS/usr/local/bin/r" ] && CLI=yes
    send "200 OK" "text/plain; charset=utf-8" "uid=$U
model=$(getprop ro.product.model)
android=$(getprop ro.build.version.release)
sdk=$(getprop ro.build.version.sdk)
context=$(cat /proc/self/attr/current 2>/dev/null | tr -d '\n')
rootfs=$RS
client=$CLI
port=$PORT
moddir=$MODDIR
token_tail=$(printf '%s' "$VALID" | tail -c 4)"
    ;;

  /api/log)
    N=80
    case "$QP" in *lines=*) N=${QP#*lines=}; N=${N%%&*}; esac
    case "$N" in ''|*[!0-9]*) N=80 ;; esac
    [ "$N" -gt 500 ] && N=500
    send "200 OK" "text/plain; charset=utf-8" "$(tail -n "$N" "$LOG" 2>/dev/null)"
    ;;

  /api/exec)
    if [ "$METHOD" != "POST" ]; then send "405 Method Not Allowed" text/plain "用 POST"; exit 0; fi
    OUT=$(/system/bin/sh -c "$BODY" 2>&1); RC=$?
    log_line "exec($RC): $(printf '%s' "$BODY" | head -c 120 | tr '\n' ' ')"
    send "200 OK" "text/plain; charset=utf-8" "$OUT" "X-Exit-Code: $RC"
    ;;

  /api/rfix)
    # body = 容器内的绝对路径（空格分隔），把属主交还该 App
    if [ "$METHOD" != "POST" ]; then send "405 Method Not Allowed" text/plain "用 POST"; exit 0; fi
    RS=$(find_rootfs 2>/dev/null)
    if [ -z "$RS" ]; then send "404 Not Found" text/plain "没找到 rootfs"; exit 0; fi
    OWNER=$(dir_owner "$RS")
    OUT=""
    for x in $BODY; do
      t="$RS$x"
      if [ -e "$t" ]; then
        chown -Rh "$OWNER:$OWNER" "$t" 2>/dev/null && OUT=$(printf '%s\nok: %s' "$OUT" "$x")
      else
        OUT=$(printf '%s\nmissing: %s' "$OUT" "$x")
      fi
    done
    log_line "rfix: $BODY"
    send "200 OK" "text/plain; charset=utf-8" "$OUT"
    ;;

  *) send "404 Not Found" "application/json; charset=utf-8" '{"err":"not found"}' ;;
esac

exit 0
