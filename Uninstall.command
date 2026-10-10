#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
echo '請先結束 Detent，讓它還原音訊輸出。 / Quit Detent first so it restores your audio output.'
stage="$(/usr/bin/mktemp -d /private/tmp/detent-remove.XXXXXX)"
trap '/bin/rm -rf "$stage"' EXIT
/bin/cp Scripts/uninstall-driver.sh "$stage/"
/usr/bin/osascript - "$stage/uninstall-driver.sh" <<'APPLESCRIPT'
on run argv
 do shell script "/bin/bash " & quoted form of (item 1 of argv) with administrator privileges
end run
APPLESCRIPT
app='/Applications/Detent.app'
if [[ -e "$app" && "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || true)" == 'local.Detent.App' ]]; then
 /bin/rm -rf "$app"
 echo "已移除 $app / Removed $app"
fi
