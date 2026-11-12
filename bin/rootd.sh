#!/system/bin/sh
# 启动 127.0.0.1 上的 root 守护（toybox nc -L，每个连接一个 handler 实例）
HERE="${0%/*}"
MODDIR="${DSHGO_MODDIR:-${HERE%/*}}"
. "$MODDIR/bin/common.sh"

ensure_data
if [ "$(id -u)" != "0" ]; then
  log_line "refuse: not root (uid=$(id -u))"
  echo "rootd: 必须以 root 启动（当前 uid=$(id -u)），否则读不到 $DATA/token" >&2
  exit 1
fi
export DSHGO_MODDIR="$MODDIR" DSHGO_DATA="$DATA" DSHGO_PORT="$PORT"

# 客户端一并在启动时装好，用户不用再点一次
if [ -x "$MODDIR/bin/install-client.sh" ] || [ -f "$MODDIR/bin/install-client.sh" ]; then
  log_line "auto install-client: $(sh "$MODDIR/bin/install-client.sh" 2>&1 | tr '\n' ' ')"
fi

# 只杀本端口的旧监听，别的端口不管
if command -v ss >/dev/null 2>&1; then
  for p in $(ss -ltnp 2>/dev/null | grep ":$PORT " | grep -o 'pid=[0-9]*' | cut -d= -f2); do
    [ "$p" != "$$" ] && kill "$p" 2>/dev/null
  done
fi
sleep 1

log_line "listen 127.0.0.1:$PORT"
exec /system/bin/nc -s 127.0.0.1 -L -p "$PORT" /system/bin/sh "$MODDIR/bin/handler.sh"
