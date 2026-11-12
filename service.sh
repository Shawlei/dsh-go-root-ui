#!/system/bin/sh
# 开机后拉起守护；dsh 运行环境可能还没就绪，所以等一会儿
MODDIR=${0%/*}
sleep 10
[ -f "$MODDIR/bin/rootd.sh" ] && nohup /system/bin/sh "$MODDIR/bin/rootd.sh" >/dev/null 2>&1 &
