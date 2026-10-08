import Foundation
import CoreAudio

struct AudioEndpoint {
    let id: AudioDeviceID
    let uid: String
    let name: String
}
enum Audio {
    static let proxyUID = "ADI2Native_Device"
    static let boxUID = "ADI2Native_Box"
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ element: UInt32 = 0) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }
    static func read<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: UInt32 = 0) throws -> T {
        var a = address(selector, scope, element), v = initial, size = UInt32(MemoryLayout<T>.size)
        try check(withUnsafeMutablePointer(to: &v) { AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0) }, "Read audio property \(selector)")
        return v
    }
    static func write<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: UInt32 = 0) throws {
        var a = address(selector, scope, element), v = value
        try check(withUnsafePointer(to: &v) { AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<T>.size), $0) }, "Write audio property \(selector)")
    }
    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var a = address(selector), v: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr else { return "" }
        return v.map { $0.takeRetainedValue() as String } ?? ""
    }
    static func devices() -> [AudioEndpoint] {
        var a = address(kAudioHardwarePropertyDevices), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size)/MemoryLayout<AudioDeviceID>.size)
        guard !ids.isEmpty, AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { AudioEndpoint(id: $0, uid: string($0,kAudioDevicePropertyDeviceUID), name: string($0,kAudioObjectPropertyName)) }
    }
    static func box() throws -> AudioObjectID {
        let text = boxUID as CFString
        var uid = Unmanaged.passUnretained(text).toOpaque(), result: AudioObjectID = 0
        var a = address(kAudioHardwarePropertyTranslateUIDToBox), size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, UInt32(MemoryLayout<CFString>.size), &uid, &size, &result), "Find bridge box")
        guard result != 0 else { throw BridgeError.message(L("尚未安裝 ADI2Native 音訊驅動", "ADI2Native audio driver is not installed")) }
        return result
    }
    /// Driver protocol 4: one prefixed name write; the driver identifies the sender by pid and
    /// rejects invalid commands with an error instead of silently ignoring them.
    static let driverProtocol = "ADI2Native/4"
    static func configure(_ box: AudioObjectID, _ command: String) throws {
        let text = "\(driverProtocol):\(command)" as CFString
        try withExtendedLifetime(text) {
            try write(box, kAudioObjectPropertyName, Unmanaged.passUnretained(text).toOpaque())
        }
    }
    static func volume(_ id: AudioDeviceID, _ channel: UInt32 = 1) throws -> Float {
        try read(id, kAudioDevicePropertyVolumeScalar, Float(0), scope: kAudioObjectPropertyScopeOutput, element: channel)
    }
    static func setVolume(_ id: AudioDeviceID, _ value: Float) throws {
        for channel: UInt32 in [1,2] { try write(id, kAudioDevicePropertyVolumeScalar, value, scope: kAudioObjectPropertyScopeOutput, element: channel) }
    }
    static func setVolume(_ id: AudioDeviceID, left: Float, right: Float) throws {
        for (channel, value) in [(UInt32(1), left), (UInt32(2), right)] { try write(id, kAudioDevicePropertyVolumeScalar, value, scope: kAudioObjectPropertyScopeOutput, element: channel) }
    }
    static func muted(_ id: AudioDeviceID) throws -> Bool { try read(id, kAudioDevicePropertyMute, UInt32(0), scope: kAudioObjectPropertyScopeOutput) != 0 }
    static func setMute(_ id: AudioDeviceID, _ value: Bool) throws { try write(id,kAudioDevicePropertyMute,UInt32(value ? 1 : 0),scope:kAudioObjectPropertyScopeOutput) }
    static func defaultDevice(_ system: Bool = false) throws -> AudioDeviceID { try read(AudioObjectID(kAudioObjectSystemObject),system ? kAudioHardwarePropertyDefaultSystemOutputDevice : kAudioHardwarePropertyDefaultOutputDevice,AudioDeviceID(0)) }
    static func setDefault(_ id: AudioDeviceID, _ system: Bool = false) throws { try write(AudioObjectID(kAudioObjectSystemObject),system ? kAudioHardwarePropertyDefaultSystemOutputDevice : kAudioHardwarePropertyDefaultOutputDevice,id) }
}
