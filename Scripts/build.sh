#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ADI2_CACHE="${ADI2_BUILD_CACHE:-${TMPDIR:-/tmp}/adi2native-swift-cache}"
mkdir -p "$ADI2_CACHE" 'build/ADI2Native.driver/Contents/MacOS' 'build/ADI2 Native.app/Contents/MacOS' 'build/ADI2 Native.app/Contents/Resources'
xcrun swift -module-cache-path "$ADI2_CACHE" Scripts/render-icons.swift "$PWD"
iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns
cp Assets/AppIcon.icns Assets/StatusIconTemplate.pdf 'build/ADI2 Native.app/Contents/Resources/'
xcrun clang++ -std=c++17 -O2 -fblocks -bundle -mmacosx-version-min=13.0 \
 -IVendor/shared -IVendor/proxyAudioDevice -IVendor/proxyAudioDevice/PublicUtility \
 Vendor/proxyAudioDevice/*.cpp Vendor/proxyAudioDevice/PublicUtility/*.cpp Vendor/shared/AudioDevice.cpp \
 -framework CoreAudio -framework CoreFoundation -framework CoreServices -framework IOKit \
 -o build/ADI2Native.driver/Contents/MacOS/ADI2Native
/usr/bin/python3 - <<'PY'
import plistlib
from pathlib import Path
p=Path('Vendor/proxyAudioDevice/Info.plist')
d=plistlib.loads(p.read_bytes())
d.update(CFBundleExecutable='ADI2Native',CFBundleIdentifier='local.ADI2Native.Driver',CFBundleName='ADI2Native',CFBundleShortVersionString='0.3.0',CFBundleVersion='6')
Path('build/ADI2Native.driver/Contents/Info.plist').write_bytes(plistlib.dumps(d))
d=dict(CFBundleExecutable='ADI2Native',CFBundleIdentifier='local.ADI2Native.App',CFBundleName='ADI2 Native',CFBundlePackageType='APPL',CFBundleShortVersionString='0.5.0',CFBundleVersion='9',CFBundleLocalizations=['zh-Hant','en'],LSMinimumSystemVersion='13.0',NSHighResolutionCapable=True,LSUIElement=True,CFBundleIconFile='AppIcon')
Path('build/ADI2 Native.app/Contents/Info.plist').write_bytes(plistlib.dumps(d))
PY
mkdir -p build/ADI2Native.driver/Contents/Resources
cp Vendor/proxyAudioDevice/DeviceIcon.icns build/ADI2Native.driver/Contents/Resources/
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos13.0 -module-cache-path "$ADI2_CACHE" Sources/*.swift -o 'build/ADI2 Native.app/Contents/MacOS/ADI2Native'
# Local builds remain ad-hoc; release builds supply a Developer ID identity.
ADI2_IDENTITY="${ADI2_SIGN_IDENTITY:--}"
sign_options=(--force --sign "$ADI2_IDENTITY")
if [[ "$ADI2_IDENTITY" != "-" ]]; then
 sign_options+=(--options runtime --timestamp)
fi
codesign "${sign_options[@]}" build/ADI2Native.driver
codesign "${sign_options[@]}" 'build/ADI2 Native.app'

codesign --verify --strict build/ADI2Native.driver
codesign --verify --strict 'build/ADI2 Native.app'
