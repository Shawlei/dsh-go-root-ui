#!/system/bin/sh
# 把 r / rfix 写进 proot 的 rootfs，属主交还该 App
HERE="${0%/*}"
MODDIR="${DSHGO_MODDIR:-${HERE%/*}}"
. "$MODDIR/bin/common.sh"

TOK=$(get_token)
[ -n "$TOK" ] || { echo "token 缺失，先重启一次模块"; exit 1; }

RS=$(find_rootfs) || { echo "没找到 proot rootfs（App 还没装本机环境？）"; exit 1; }
[ -d "$RS" ] || { echo "rootfs 无效：$RS"; exit 1; }

OWNER=$(dir_owner "$RS")
BIN="$RS/usr/local/bin"
mkdir -p "$BIN" || { echo "建 $BIN 失败"; exit 1; }

# 先写临时文件再改名，避免正在运行的脚本被截断
sed "s|__TOKEN__|$TOK|g" "$MODDIR/bin/client.sh"      > "$BIN/.r.tmp"    && mv -f "$BIN/.r.tmp" "$BIN/r"
sed "s|__TOKEN__|$TOK|g" "$MODDIR/bin/client-rfix.sh" > "$BIN/.rfix.tmp" && mv -f "$BIN/.rfix.tmp" "$BIN/rfix"
chmod 755 "$BIN/r" "$BIN/rfix"
chown -R "$OWNER:$OWNER" "$BIN" 2>/dev/null

printf '%s\n' "$RS" > "$DATA/rootfs" 2>/dev/null
echo "已安装 $BIN/r $BIN/rfix（owner=$OWNER, rootfs=$RS）"
