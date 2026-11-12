#!/system/bin/sh
# 换 token，并把容器里的 r / rfix 同步到新 token
HERE="${0%/*}"
MODDIR="${DSHGO_MODDIR:-${HERE%/*}}"
. "$MODDIR/bin/common.sh"

ensure_data
NEW=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
printf '%s' "$NEW" > "$DATA/token"
chmod 600 "$DATA/token" 2>/dev/null
log_line "token rotated"
PAGE="$MODDIR/webroot/index.html"
if [ -f "$PAGE" ]; then
  OLD=$(grep -o 'token: "[a-f0-9]*"' "$PAGE" | head -1 | cut -d'"' -f2)
  [ -n "$OLD" ] && sed -i "s|$OLD|$NEW|g" "$PAGE"
fi
echo "新 token: $NEW"
sh "$MODDIR/bin/install-client.sh"
