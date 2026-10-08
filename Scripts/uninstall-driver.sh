#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo '需要管理員權限'; exit 1; }
dst='/Library/Audio/Plug-Ins/HAL/Detent.driver'
if [[ -e "$dst" ]]; then
 [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$dst/Contents/Info.plist")" == 'local.Detent.Driver' ]]
 /bin/rm -rf "$dst"
fi
if [[ -e /Library/Audio/Plug-Ins/HAL/Detent.previous ]]; then
 [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' /Library/Audio/Plug-Ins/HAL/Detent.previous/Contents/Info.plist)" == 'local.Detent.Driver' ]]
 /bin/rm -rf /Library/Audio/Plug-Ins/HAL/Detent.previous
fi
# Also remove a driver left from before the rename to Detent (0.6).
for legacy in /Library/Audio/Plug-Ins/HAL/ADI2Native.driver /Library/Audio/Plug-Ins/HAL/ADI2Native.previous; do
 if [[ -e "$legacy" && "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$legacy/Contents/Info.plist")" == 'local.ADI2Native.Driver' ]]; then /bin/rm -rf "$legacy"; fi
done
/usr/bin/killall coreaudiod || true
