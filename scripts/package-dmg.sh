#!/bin/sh
# Đóng gói build/AIUsageMonitor.dmg (kéo app vào Applications để cài).
set -e
cd "$(dirname "$0")/.."

./scripts/build-app.sh

STAGE=build/dmg
rm -rf "$STAGE" build/AIUsageMonitor.dmg
mkdir -p "$STAGE"
cp -R build/AIUsageMonitor.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "AI Usage Monitor" -srcfolder "$STAGE" -ov -format UDZO build/AIUsageMonitor.dmg >/dev/null
rm -rf "$STAGE"
echo "Built build/AIUsageMonitor.dmg"
