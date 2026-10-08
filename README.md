<p align="center"><img src="Assets/Logo.svg" width="128" alt="ADI2 Native icon"></p>

# ADI2 Native

Native macOS volume control for the **RME ADI-2 DAC**, with a menu bar app and built-in EQ editor.

[繁體中文](README.zh-TW.md)

A Swift/AppKit app controls the DAC's hardware volume through USB MIDI. A Core Audio HAL proxy forwards stereo PCM, connecting macOS volume keys and Control Center to the DAC's volume setting.

## Features

- System volume and DAC volume synchronization; Line Out, Phones and IEM control targets.
- Rotary volume dial (drag, scroll or arrow keys; ⌥ for 0.1 dB steps), plus menu bar volume/mute controls whose icon shows the current level. Optional Dock icon and launch at login.
- Five-band EQ, separate left/right editing, Bass/Treble, DAC preset loading, and a response graph whose band handles can be dragged to set frequency and gain.
- Per-output volume ranges and a software volume ceiling.
- Traditional Chinese / English interface. Appearance follows the system or is fixed to Light or Dark; on macOS 26 and later the sidebar, cards and buttons use Liquid Glass.
- Output-only playback streams, expiring playback lease, and visible driver errors.

## Status and requirements

Source release: **App 0.5.0 / driver 0.2.2**. Local development build, not a notarized 1.0 release.

- Apple Silicon Mac; the build script targets macOS 13 or newer. Local hardware testing has been on macOS 27; other OS versions are not yet validated.
- Xcode Command Line Tools (`xcode-select --install`).
- Exactly one RME ADI-2 DAC connected over USB, with firmware supporting the official MIDI remote protocol. ADI-2 Pro and 2/4 Pro are not supported.
- Administrator authentication to install the HAL driver.

Seven test suites pass, including simulated failures and recovery. The latest 0.5.0 / 0.2.2 changes have passed compilation and automated tests; final installation/hardware verification is pending. Extended playback, physical reconnect and sleep/wake coverage across machines remains incomplete.

## Build and test

```sh
git clone https://github.com/vendyluo/adi2-native.git
cd adi2-native
./Scripts/build.sh
./Scripts/test.sh
```

Icons are generated locally by `Scripts/render-icons.swift`, which also writes the vector logo `Assets/Logo.svg` from the same geometry. Local builds use ad-hoc signing by default. The DMG prepared on 2026-09-26 passed Developer ID signing, Apple notarization, and Gatekeeper validation. `Scripts/release.sh` supports signed and notarized releases; see the signing section in README.zh-TW.md. The DMG currently contains a folder with command-based installation tools; a graphical PKG installer is still pending.

## Install and use

1. Quit any running ADI2 Native app.
2. Run `./安裝.command` and complete the macOS administrator prompt. Installation briefly restarts the Mac audio service.
3. Choose a control target and enable native volume control in the app.
4. Keep the app running; closing the window leaves menu bar control active.

Keep the app at the same path after enabling launch at login. Moving it requires setting up login launch again.

To uninstall, quit the app and run `./解除安裝.command`. This removes the HAL driver and restarts the audio service; project files remain.

## Behavior and limitations

- The proxy is a separate output named `ADI-2 Native`; it does not modify the original USB device.
- The proxy does not apply a second digital attenuation: hardware gain is set on the DAC. It adds buffering (512 frames by default).
- The volume ceiling is software-enforced while native control is enabled; the physical knob can briefly exceed it. It is not a hardware hearing-protection limiter.
- Selecting Line Out/Phones/IEM selects the controlled volume, not the DAC's physical audio route.
- Stereo PCM only; DSD/DoP and exclusive playback are unsupported. Players using the physical DAC directly bypass the proxy.
- A missing app lease silences proxy playback. If recovery fails, manually select the physical DAC in macOS Sound settings.
- EQ response graphs are approximate. Applying edits changes current settings, not stored preset slots.

Hardware verification is available via `./Scripts/verify-live.sh`. It changes routing, volume, mute and EQ temporarily and attempts to restore them. Close the app first. This is not part of the hardware-free test suite.

## License

Original code and modifications: [MIT](LICENSE). Bundled third-party code retains its own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Independent community project; not affiliated with RME or Apple.
