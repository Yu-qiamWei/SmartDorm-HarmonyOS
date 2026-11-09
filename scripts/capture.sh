#!/bin/bash
# capture.sh <name> — 在模拟器上抓取当前界面截图 + 组件树，落到仓库证据目录
# 用法：bash scripts/capture.sh 02_device_list
HDC="D:/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
export MSYS_NO_PATHCONV=1
NAME="$1"
[ -z "$NAME" ] && echo "usage: capture.sh <name>" && exit 1

"$HDC" shell snapshot_display -f "/data/local/tmp/$NAME.jpeg" >/dev/null 2>&1
( cd /d/SmartDormHarmonyOS/screenshots && "$HDC" file recv "/data/local/tmp/$NAME.jpeg" "$NAME.jpeg" >/dev/null 2>&1 )
"$HDC" shell uitest dumpLayout -p "/data/local/tmp/lay_$NAME.json" >/dev/null 2>&1
( cd /d/SmartDormHarmonyOS && "$HDC" file recv "/data/local/tmp/lay_$NAME.json" "evidence/device/lay_$NAME.json" >/dev/null 2>&1 )

if [ -f "/d/SmartDormHarmonyOS/screenshots/$NAME.jpeg" ]; then
  echo "[OK] screenshots/$NAME.jpeg $(stat -c%s "/d/SmartDormHarmonyOS/screenshots/$NAME.jpeg") bytes"
else
  echo "[FAIL] screenshot not captured: $NAME"
fi
if [ -f "/d/SmartDormHarmonyOS/evidence/device/lay_$NAME.json" ]; then
  echo "[OK] evidence/device/lay_$NAME.json $(stat -c%s "/d/SmartDormHarmonyOS/evidence/device/lay_$NAME.json") bytes"
else
  echo "[FAIL] layout not captured: $NAME"
fi
