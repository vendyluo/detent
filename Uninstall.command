#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
echo '請先結束 ADI2 Native，讓它還原音訊輸出。 / Quit ADI2 Native first so it restores your audio output.'
stage="$(/usr/bin/mktemp -d /private/tmp/adi2native-remove.XXXXXX)"
trap '/bin/rm -rf "$stage"' EXIT
/bin/cp Scripts/uninstall-driver.sh "$stage/"
/usr/bin/osascript - "$stage/uninstall-driver.sh" <<'APPLESCRIPT'
on run argv
 do shell script "/bin/bash " & quoted form of (item 1 of argv) with administrator privileges
end run
APPLESCRIPT
