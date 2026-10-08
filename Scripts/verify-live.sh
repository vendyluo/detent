#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo '實機測試會暫時切換輸出、降低音量、測試靜音與 EQ 讀寫；完成後還原。'
ADI2_CACHE="${ADI2_BUILD_CACHE:-${TMPDIR:-/tmp}/detent-swift-cache}"
mkdir -p "$ADI2_CACHE" build
xcrun swiftc -swift-version 5 -module-cache-path "$ADI2_CACHE" \
 Sources/Localization.swift Sources/Audio.swift Sources/Bridge.swift Sources/BridgeIO.swift Sources/Settings.swift Sources/MIDI.swift Sources/RMEProtocol.swift Sources/EQ.swift \
 Tests/LiveVerification.swift -o build/LiveVerification
build/LiveVerification "${1:-3}"
