#!/system/bin/sh
# 公共函数：路径发现、token、日志。被 rootd.sh / handler.sh / install-client.sh 引用。

DATA="${DSHGO_DATA:-/data/adb/dshgo_rootui}"
MODDIR="${DSHGO_MODDIR:-/data/adb/modules/dshgo_rootui}"
PORT="${DSHGO_PORT:-7000}"
CFG_ROOTFS="$DATA/rootfs"
LOG="$DATA/daemon.log"

ensure_data() {
  mkdir -p "$DATA" 2>/dev/null
  chmod 700 "$DATA" 2>/dev/null
  if [ ! -s "$DATA/token" ]; then
    head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$DATA/token"
  fi
  chmod 600 "$DATA/token" 2>/dev/null
}

get_token() { cat "$DATA/token" 2>/dev/null; }

# proot 应用的 rootfs 特征：<app data>/files/runtime/rootfs
# 支持 DSHGO_ROOTFS 覆盖、$DATA/rootfs 缓存、以及自动扫描
find_rootfs() {
  if [ -n "$DSHGO_ROOTFS" ] && [ -d "$DSHGO_ROOTFS" ]; then printf '%s' "$DSHGO_ROOTFS"; return 0; fi
  if [ -s "$CFG_ROOTFS" ]; then
    r=$(cat "$CFG_ROOTFS" 2>/dev/null)
    if [ -n "$r" ] && [ -d "$r" ]; then printf '%s' "$r"; return 0; fi
  fi
  for d in /data/user/0/*/files/runtime/rootfs /data/data/*/files/runtime/rootfs; do
    if [ -d "$d" ]; then
      printf '%s' "$d" > "$CFG_ROOTFS" 2>/dev/null
      printf '%s' "$d"; return 0
    fi
  done
  return 1
}

# 目标目录属主 = 那个 App 的 uid，客户端要交还给它
dir_owner() { stat -c %u "$1" 2>/dev/null || echo 0; }

log_line() {
  printf '[%s] %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null
  # 超过 64KB 只留最后 300 行
  if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt 65536 ]; then
    tail -n 300 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG" 2>/dev/null
  fi
}
