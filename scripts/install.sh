#!/bin/sh
# Build và cài AIUsageMonitor.app vào /Applications (fallback ~/Applications), rồi mở app.
set -e
cd "$(dirname "$0")/.."

./scripts/build-app.sh

DEST=/Applications
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }

# Thoát bản đang chạy (nếu có) trước khi ghi đè.
pkill -x AIUsageMonitor 2>/dev/null && sleep 1 || true

rm -rf "$DEST/AIUsageMonitor.app"
cp -R build/AIUsageMonitor.app "$DEST/"
open "$DEST/AIUsageMonitor.app"
echo "Đã cài vào $DEST/AIUsageMonitor.app"
