#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $EUID -ne 0 ]]; then echo '需要管理員權限。請開啟 Install.command。 / Administrator rights are required; open Install.command.'; exit 1; fi
src="$PWD/build/ADI2Native.driver"
dst='/Library/Audio/Plug-Ins/HAL/ADI2Native.driver'
/usr/bin/codesign --verify --strict "$src"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$src/Contents/Info.plist")" == 'local.ADI2Native.Driver' ]]
/bin/mkdir -p /Library/Audio/Plug-Ins/HAL
if [[ -e "$dst" ]]; then
 [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$dst/Contents/Info.plist")" == 'local.ADI2Native.Driver' ]]
 /bin/rm -rf /Library/Audio/Plug-Ins/HAL/ADI2Native.previous
 /bin/mv "$dst" /Library/Audio/Plug-Ins/HAL/ADI2Native.previous
fi
/usr/bin/ditto "$src" "$dst"
/usr/sbin/chown -R root:wheel "$dst"
/bin/chmod -R go-w "$dst"
/usr/bin/killall coreaudiod || true
echo 'ADI2Native 音訊驅動已安裝。 / ADI2Native audio driver installed.'
