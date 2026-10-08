#!/bin/bash
# Build a signed DMG, submit it to Apple, and staple the accepted ticket.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ADI2_SIGN_IDENTITY:?Set ADI2_SIGN_IDENTITY to your Developer ID Application identity}"
[[ "$ADI2_SIGN_IDENTITY" == 'Developer ID Application:'* ]] || { echo 'A Developer ID Application identity is required.' >&2; exit 1; }
./Scripts/build.sh
stage="$(mktemp -d "${TMPDIR:-/tmp}/adi2-release.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Detent/build" "$stage/Detent/Scripts" build/release
for bundle in 'Detent.app' Detent.driver; do
 ditto "build/$bundle" "$stage/Detent/build/$bundle"
done
cp Install.command Uninstall.command README.zh-TW.md LICENSE THIRD_PARTY_NOTICES.md "$stage/Detent/"
cp Scripts/install-driver.sh Scripts/uninstall-driver.sh "$stage/Detent/Scripts/"
dmg="$PWD/build/release/ADI2-Native.dmg"
hdiutil create -ov -format UDZO -volname 'Detent' -srcfolder "$stage" "$dmg"
codesign --force --timestamp --sign "$ADI2_SIGN_IDENTITY" "$dmg"
codesign --verify --strict "$dmg"
if [[ -z "${ADI2_NOTARY_PROFILE:-}" ]]; then
 echo "Signed DMG (NOT notarized): $dmg"
 echo 'Set ADI2_NOTARY_PROFILE to a notarytool Keychain profile and run again to notarize.'
 exit 0
fi
xcrun notarytool submit "$dmg" --keychain-profile "$ADI2_NOTARY_PROFILE" --wait --output-format json > build/release/notary-result.json
/usr/bin/python3 - <<'PY'
import json
from pathlib import Path
r = json.loads(Path('build/release/notary-result.json').read_text())
if r.get('status') != 'Accepted':
    raise SystemExit(f"Notarization not accepted: {r}. Retrieve the notarytool log before distributing.")
PY
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
echo "Notarized release: $dmg"
