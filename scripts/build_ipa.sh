#!/bin/bash
# 產生未簽名的 qBitGlass.ipa（供 Sideloadly / AltStore / TrollStore 等側載工具重新簽名安裝）
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null && xcodegen generate >/dev/null

DERIVED=build/DerivedData-Release
rm -rf "$DERIVED" build/Payload dist/qBitGlass.ipa
xcodebuild -project QBManager.xcodeproj -scheme QBManager -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build | tail -n 3

mkdir -p build/Payload dist
cp -R "$DERIVED/Build/Products/Release-iphoneos/QBManager.app" build/Payload/
(cd build && zip -qry ../dist/qBitGlass.ipa Payload)
rm -rf build/Payload
echo "完成：$(pwd)/dist/qBitGlass.ipa ($(du -h dist/qBitGlass.ipa | cut -f1))"
