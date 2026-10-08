import Foundation
import CoreAudio

protocol MIDITransport: AnyObject {
    var onMessage: (([UInt8])->Void)? { get set }
    var onTopology: (()->Void)? { get set }
    func connect() throws
    func disconnect()
    func send(_ bytes:[UInt8]) throws
    func topologyIsCurrent() -> Bool
}
protocol AudioTransport {
    func devices() -> [AudioEndpoint]
    func box() throws -> AudioObjectID
    func checkPlayback(_ box:AudioObjectID) throws
    func configure(_ box:AudioObjectID,_ command:String) throws
    func volume(_ id:AudioDeviceID,_ channel:UInt32) throws -> Float
    func setVolume(_ id:AudioDeviceID,_ value:Float) throws
    func setVolume(_ id:AudioDeviceID,left:Float,right:Float) throws
    func muted(_ id:AudioDeviceID) throws -> Bool
    func setMute(_ id:AudioDeviceID,_ value:Bool) throws
    func defaultDevice(_ system:Bool) throws -> AudioDeviceID
    func setDefault(_ id:AudioDeviceID,_ system:Bool) throws
}
struct SystemAudio: AudioTransport {
    func devices()->[AudioEndpoint] { Audio.devices() }
    func box() throws->AudioObjectID {
        let result=try Audio.box()
        guard Audio.string(result,kAudioObjectPropertyFirmwareVersion)==Audio.driverProtocol else {
            throw BridgeError.message(L("需要更新 Detent 音訊驅動：請執行新版 Install.command", "Update the Detent audio driver by running the new installer."))
        }
        return result
    }
    func checkPlayback(_ box:AudioObjectID)throws {
        try Audio.write(box,kAudioObjectPropertyIdentify,Int32(-8))
        let value=Audio.string(box,kAudioObjectPropertyName)
        guard let code=Int32(value) else { throw BridgeError.message(L("無法讀取驅動播放狀態", "Cannot read driver playback status")) }
        if code != 0 { throw BridgeError.message(L("音訊驅動無法啟動播放（\(code)）；請重新啟用控制以重試", "Audio driver could not start playback (\(code)). Enable control again to retry.")) }
    }
    func configure(_ box:AudioObjectID,_ command:String)throws { try Audio.configure(box,command) }
    func volume(_ id:AudioDeviceID,_ channel:UInt32)throws->Float { try Audio.volume(id,channel) }
    func setVolume(_ id:AudioDeviceID,_ value:Float)throws { try Audio.setVolume(id,value) }
    func setVolume(_ id:AudioDeviceID,left:Float,right:Float)throws { try Audio.setVolume(id,left:left,right:right) }
    func muted(_ id:AudioDeviceID)throws->Bool { try Audio.muted(id) }
    func setMute(_ id:AudioDeviceID,_ value:Bool)throws { try Audio.setMute(id,value) }
    func defaultDevice(_ system:Bool)throws->AudioDeviceID { try Audio.defaultDevice(system) }
    func setDefault(_ id:AudioDeviceID,_ system:Bool)throws { try Audio.setDefault(id,system) }
}
