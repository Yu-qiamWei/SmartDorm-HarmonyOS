#!/bin/bash
# tap.sh <text> [nth] — 按文本查找控件并点击中心点（先 dumpLayout 再 uiInput click）
HDC="D:/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
export MSYS_NO_PATHCONV=1
TXT="$1"
NTH="${2:-0}"
[ -z "$TXT" ] && echo "usage: tap.sh <text> [nth]" && exit 1

"$HDC" shell uitest dumpLayout -p /data/local/tmp/_t.json >/dev/null 2>&1
( cd /d/SmartDormHarmonyOS && "$HDC" file recv /data/local/tmp/_t.json "evidence/device/_t.json" >/dev/null 2>&1 )

COORD=$(cd /d/SmartDormHarmonyOS && node scripts/btn.js evidence/device/_t.json "$TXT" "$NTH" 2>/dev/null)
if [ -z "$COORD" ]; then
  echo "NOT_FOUND: $TXT"
  exit 2
fi
X=${COORD% *}
Y=${COORD#* }
"$HDC" shell uitest uiInput click "$X" "$Y" >/dev/null 2>&1
echo "tapped [$TXT] at $X,$Y"
