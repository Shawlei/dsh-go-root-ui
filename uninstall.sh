#!/system/bin/sh
for p in $(ss -ltnp 2>/dev/null | grep ':7000 ' | grep -o 'pid=[0-9]*' | cut -d= -f2); do
  kill "$p" 2>/dev/null
done
rm -rf /data/adb/dshgo_rootui
