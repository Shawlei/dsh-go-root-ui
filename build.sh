#!/usr/bin/env bash
# 打包成可刷入的模块 zip：./build.sh
set -euo pipefail
cd "$(dirname "$0")"

ID=$(sed -n 's/^id=//p' module.prop)
VER=$(sed -n 's/^version=//p' module.prop)
OUT="dist/${ID}-${VER}.zip"

mkdir -p dist
rm -f "$OUT"
command -v zip >/dev/null || { echo "需要 zip 命令"; exit 1; }

zip -r9 "$OUT" \
  module.prop customize.sh post-fs-data.sh service.sh uninstall.sh README.md \
  bin webroot META-INF \
  -x '*.DS_Store' -x '__MACOSX/*' >/dev/null

echo "built $OUT ($(du -h "$OUT" | cut -f1))"
