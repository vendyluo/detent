#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $EUID -ne 0 ]]; then echo '需要管理員權限。請開啟 Install.command。 / Administrator rights are required; open Install.command.'; exit 1; fi
src="$PWD/build/Detent.driver"
dst='/Library/Audio/Plug-Ins/HAL/Detent.driver'
/usr/bin/codesign --verify --strict "$src"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$src/Contents/Info.plist")" == 'local.Detent.Driver' ]]
/bin/mkdir -p /Library/Audio/Plug-Ins/HAL
if [[ -e "$dst" ]]; then
 [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$dst/Contents/Info.plist")" == 'local.Detent.Driver' ]]
 /bin/rm -rf /Library/Audio/Plug-Ins/HAL/Detent.previous
 /bin/mv "$dst" /Library/Audio/Plug-Ins/HAL/Detent.previous
fi
# Remove the driver installed under the pre-0.6 name so two proxies never coexist.
for legacy in /Library/Audio/Plug-Ins/HAL/ADI2Native.driver /Library/Audio/Plug-Ins/HAL/ADI2Native.previous; do
 if [[ -e "$legacy" && "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$legacy/Contents/Info.plist")" == 'local.ADI2Native.Driver' ]]; then /bin/rm -rf "$legacy"; fi
done
/usr/bin/ditto "$src" "$dst"
/usr/sbin/chown -R root:wheel "$dst"
/bin/chmod -R go-w "$dst"
/usr/bin/killall coreaudiod || true
echo 'Detent 音訊驅動已安裝。 / Detent audio driver installed.'
