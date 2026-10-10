#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
if [[ "$(uname -m)" != "arm64" || "$(sw_vers -productVersion | cut -d. -f1)" -lt 26 ]]; then
  echo '這份移轉包需要 Apple 晶片 Mac 與 macOS 26 或更新版本。'
  read -r -p '按 Enter 關閉。' reply
  exit 1
fi
open "$PWD/edgelesstype.app"
