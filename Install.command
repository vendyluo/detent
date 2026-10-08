#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if /usr/bin/pgrep -u "$(/usr/bin/id -u)" -x ADI2Native >/dev/null; then
 echo '請先從 ADI2 Native 選單列結束 App，再重新執行安裝。 / Quit ADI2 Native from the menu bar, then run the installer again.'
 exit 1
fi
echo '安裝 ADI2Native 音訊驅動；會短暫重新啟動 Mac 音訊服務。 / Installing the ADI2Native audio driver; the Mac audio service will briefly restart.'
# Stage outside Documents: macOS TCC can deny privileged helpers access to Documents.
stage="$(/usr/bin/mktemp -d /private/tmp/adi2native-install.XXXXXX)"
trap '/bin/rm -rf "$stage"' EXIT
/bin/mkdir -p "$stage/Scripts" "$stage/build"
/bin/cp Scripts/install-driver.sh "$stage/Scripts/"
/usr/bin/ditto build/ADI2Native.driver "$stage/build/ADI2Native.driver"
/usr/bin/osascript - "$stage/Scripts/install-driver.sh" <<'APPLESCRIPT'
on run argv
 do shell script "/bin/bash " & quoted form of (item 1 of argv) with administrator privileges
end run
APPLESCRIPT
/usr/bin/open "$PWD/build/ADI2 Native.app"
