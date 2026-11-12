#!/system/bin/sh
# 安装期：落盘、生成 token、注入页面、设定权限与 SELinux 上下文
command -v ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }

MODID=$(sed -n 's/^id=//p' "$TMPDIR/module.prop" 2>/dev/null | head -1)
[ -n "$MODID" ] || MODID=dshgo_rootui
MODPATH=/data/adb/modules/$MODID
mkdir -p "$MODPATH"

if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ] && [ "$TMPDIR" != "$MODPATH" ]; then
  cp -af "$TMPDIR/." "$MODPATH/" 2>/dev/null
fi
rm -rf "$MODPATH/META-INF"

DATA=/data/adb/dshgo_rootui
mkdir -p "$DATA" && chmod 700 "$DATA"
if [ ! -s "$DATA/token" ]; then
  head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$DATA/token"
fi
chmod 600 "$DATA/token"
TOK=$(cat "$DATA/token")

sed -i "s|__TOKEN__|$TOK|g" "$MODPATH/webroot/index.html" 2>/dev/null
sed -i "s|__TOKEN__|$TOK|g" "$MODPATH/bin/client.sh" 2>/dev/null
sed -i "s|__TOKEN__|$TOK|g" "$MODPATH/bin/client-rfix.sh" 2>/dev/null

chmod 755 "$MODPATH"/*.sh "$MODPATH"/bin/*.sh 2>/dev/null
chmod 644 "$MODPATH/module.prop" "$MODPATH/README.md" \
          "$MODPATH/webroot/index.html" "$MODPATH/webroot/app.js" "$MODPATH/webroot/style.css" 2>/dev/null
chown -R 0:0 "$MODPATH" 2>/dev/null
command -v chcon >/dev/null 2>&1 && chcon -R u:object_r:system_file:s0 "$MODPATH" 2>/dev/null

# 顺手清掉旧的一次性通道
rm -f /data/adb/service.d/rootd.sh 2>/dev/null

ui_print "  dsh-go Root UI 已安装"
ui_print "  token: $TOK"
ui_print "  守护: 127.0.0.1:7000（开机自启）"
ui_print "  打开: 模块卡片 → WebUI"
