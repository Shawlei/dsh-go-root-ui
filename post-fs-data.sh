#!/system/bin/sh
MODDIR=${0%/*}
DATA=/data/adb/dshgo_rootui
mkdir -p "$DATA" && chmod 700 "$DATA"
[ -s "$DATA/token" ] || { head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$DATA/token"; }
chmod 600 "$DATA/token"
