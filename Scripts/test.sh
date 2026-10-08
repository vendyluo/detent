#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ADI2_CACHE="${ADI2_BUILD_CACHE:-${TMPDIR:-/tmp}/detent-swift-cache}"
mkdir -p "$ADI2_CACHE" build
core=(Sources/Localization.swift Tests/TestDoubles.swift Sources/Audio.swift Sources/Bridge.swift Sources/BridgeIO.swift Sources/Settings.swift Sources/MIDI.swift Sources/RMEProtocol.swift Sources/EQ.swift)
for suite in ProtocolTests BridgeTests EQTests; do
 xcrun swiftc -swift-version 5 -module-cache-path "$ADI2_CACHE" "${core[@]}" "Tests/$suite.swift" -o "build/$suite"
 "build/$suite"
done
xcrun clang++ -std=c++17 -O1 -fblocks -Wno-deprecated-declarations \
 -IVendor/shared -IVendor/proxyAudioDevice -IVendor/proxyAudioDevice/PublicUtility \
 Tests/DriverTests.cpp Vendor/proxyAudioDevice/*.cpp Vendor/proxyAudioDevice/PublicUtility/*.cpp Vendor/shared/AudioDevice.cpp \
 -framework CoreAudio -framework CoreFoundation -framework CoreServices -framework IOKit -o build/DriverTests
build/DriverTests

xcrun swiftc -swift-version 5 -module-cache-path "$ADI2_CACHE" "${core[@]}" Sources/Theme.swift Sources/StatusKnob.swift Sources/EQEditor.swift Tests/PolishTests.swift -o build/PolishTests
build/PolishTests

# Use the real AppDelegate without the production entry point for UI localization checks.
sed '/^@main struct Application/,$d' Sources/App.swift > build/AppDelegateForTests.swift
xcrun swiftc -swift-version 5 -module-cache-path "$ADI2_CACHE" "${core[@]}" Sources/Theme.swift Sources/EQEditor.swift Sources/AppLayout.swift Sources/StatusKnob.swift Sources/InterfaceLanguage.swift Sources/StatusMenu.swift build/AppDelegateForTests.swift Tests/LocalizationTests.swift -o build/LocalizationTests
build/LocalizationTests

xcrun clang++ -std=c++17 -fblocks -Wno-deprecated-declarations \
 -IVendor/shared -IVendor/proxyAudioDevice -IVendor/proxyAudioDevice/PublicUtility \
 Tests/OutputOnlyTests.cpp -framework CoreAudio -framework CoreFoundation -framework CoreServices -framework IOKit -o build/OutputOnlyTests
build/OutputOnlyTests
