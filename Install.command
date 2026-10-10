#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# ADI2Native is the name used before 0.6.
if /usr/bin/pgrep -u "$(/usr/bin/id -u)" -x Detent >/dev/null || /usr/bin/pgrep -u "$(/usr/bin/id -u)" -x ADI2Native >/dev/null; then
 echo '請先從 Detent 選單列結束 App，再重新執行安裝。 / Quit Detent from the menu bar, then run the installer again.'
 exit 1
fi
echo '安裝 Detent 音訊驅動；會短暫重新啟動 Mac 音訊服務。 / Installing the Detent audio driver; the Mac audio service will briefly restart.'
# Stage outside Documents: macOS TCC can deny privileged helpers access to Documents.
stage="$(/usr/bin/mktemp -d /private/tmp/detent-install.XXXXXX)"
trap '/bin/rm -rf "$stage"' EXIT
/bin/mkdir -p "$stage/Scripts" "$stage/build"
/bin/cp Scripts/install-driver.sh "$stage/Scripts/"
/usr/bin/ditto build/Detent.driver "$stage/build/Detent.driver"
/usr/bin/osascript - "$stage/Scripts/install-driver.sh" <<'APPLESCRIPT'
on run argv
 do shell script "/bin/bash " & quoted form of (item 1 of argv) with administrator privileges
end run
APPLESCRIPT
# Install the app in /Applications so launch at login keeps a stable path.
app='/Applications/Detent.app'
for old in "$app" /Applications/ADI2Native.app; do
 if [[ -e "$old" ]]; then
  id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$old/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$id" != 'local.Detent.App' && "$id" != 'local.ADI2Native.App' ]]; then
   echo "$old 不是 Detent，未覆蓋。 / $old is not Detent; left untouched."; exit 1
  fi
  /bin/rm -rf "$old"
 fi
done
/usr/bin/ditto build/Detent.app "$app"
echo "App 已安裝到 $app / App installed to $app"
/usr/bin/open "$app"
