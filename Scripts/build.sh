#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ADI2_CACHE="${ADI2_BUILD_CACHE:-${TMPDIR:-/tmp}/detent-swift-cache}"
mkdir -p "$ADI2_CACHE" 'build/Detent.driver/Contents/MacOS' 'build/Detent.app/Contents/MacOS' 'build/Detent.app/Contents/Resources'
xcrun swift -module-cache-path "$ADI2_CACHE" Scripts/render-icons.swift "$PWD"
iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns
cp Assets/AppIcon.icns Assets/StatusIconTemplate.pdf 'build/Detent.app/Contents/Resources/'
xcrun clang++ -std=c++17 -O2 -fblocks -bundle -mmacosx-version-min=13.0 \
 -IVendor/shared -IVendor/proxyAudioDevice -IVendor/proxyAudioDevice/PublicUtility \
 Vendor/proxyAudioDevice/*.cpp Vendor/proxyAudioDevice/PublicUtility/*.cpp Vendor/shared/AudioDevice.cpp \
 -framework CoreAudio -framework CoreFoundation -framework CoreServices -framework IOKit \
 -o build/Detent.driver/Contents/MacOS/Detent
/usr/bin/python3 - <<'PY'
import plistlib
from pathlib import Path
p=Path('Vendor/proxyAudioDevice/Info.plist')
d=plistlib.loads(p.read_bytes())
d.update(CFBundleExecutable='Detent',CFBundleIdentifier='local.Detent.Driver',CFBundleName='Detent',CFBundleShortVersionString='0.4.0',CFBundleVersion='8')
Path('build/Detent.driver/Contents/Info.plist').write_bytes(plistlib.dumps(d))
d=dict(CFBundleExecutable='Detent',CFBundleIdentifier='local.Detent.App',CFBundleName='Detent',CFBundlePackageType='APPL',CFBundleShortVersionString='0.6.0',CFBundleVersion='10',CFBundleLocalizations=['zh-Hant','en'],LSMinimumSystemVersion='13.0',NSHighResolutionCapable=True,LSUIElement=True,CFBundleIconFile='AppIcon')
Path('build/Detent.app/Contents/Info.plist').write_bytes(plistlib.dumps(d))
PY
mkdir -p build/Detent.driver/Contents/Resources
cp Vendor/proxyAudioDevice/DeviceIcon.icns build/Detent.driver/Contents/Resources/
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos13.0 -module-cache-path "$ADI2_CACHE" Sources/*.swift -o 'build/Detent.app/Contents/MacOS/Detent'
# Local builds remain ad-hoc; release builds supply a Developer ID identity.
ADI2_IDENTITY="${ADI2_SIGN_IDENTITY:--}"
sign_options=(--force --sign "$ADI2_IDENTITY")
if [[ "$ADI2_IDENTITY" != "-" ]]; then
 sign_options+=(--options runtime --timestamp)
fi
codesign "${sign_options[@]}" build/Detent.driver
codesign "${sign_options[@]}" 'build/Detent.app'

codesign --verify --strict build/Detent.driver
codesign --verify --strict 'build/Detent.app'
