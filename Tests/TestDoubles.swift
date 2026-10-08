import Foundation
import CoreAudio

final class Clock { var time:Double=100 }
final class FakeMIDI:MIDITransport {
    var onMessage:(([UInt8])->Void)?, onTopology:(()->Void)?
    var present=true, linked=false, acknowledge=true
    var state:[Int:[Int:Int]]=[3:[12:-100,13:0,15:0],6:[12:-300,13:0,15:0],9:[12:-165,13:0,15:0]]
    var writes:[[UInt8]]=[]
    /// DAC preset memory, as measured on hardware: address 13/14 writes and the name fill a buffer that the
    /// flag word (written at index 2, reported at index 1) commits to a slot.
    var presetBuffer:[Int:Int]=[:], presets:[Int:[Int:Int]]=[:], presetNames:[Int:String]=[:], bufferedName:String?
    var corruptPresets=false
    func topologyIsCurrent()->Bool { present && linked }
    func connect()throws { guard present else { throw BridgeError.message("offline") }; linked=true; snapshot() }
    func disconnect() { linked=false }
    func emit(_ ps:[RMEParameter]) {
        var b:[UInt8]=[0xF0,0,0x20,0x0D,0x71,1]
        for parameter in ps {
            let p=RMEProtocol.normalized(parameter)
            let bits=RMEProtocol.isFrequency(channel:p.channel,index:p.index) ? (p.value>2047 ? 0x800 | (p.value/10) : p.value) : p.value&0xFFF
            b += [UInt8(p.channel<<3|p.index>>2),UInt8((p.index&3)<<5|bits>>7),UInt8(bits&127)]
        }
        onMessage?(b+[0xF7])
    }
    func snapshot() {
        guard acknowledge else { return }
        emit(state.flatMap { c,params in params.map { RMEParameter(channel:c,index:$0.key,value:$0.value) } })
    }
    func hardware(_ channel:Int,_ index:Int,_ value:Int) { state[channel,default:[:]][index]=value; emit([RMEParameter(channel:channel,index:index,value:value)]) }
    func send(_ b:[UInt8])throws {
        guard present else { throw BridgeError.message("offline") }
        writes.append(b)
        if b==RMEProtocol.request { snapshot() }
        else if b[5]==2 {
            var incoming=b; incoming[5]=1
            let ps=RMEProtocol.parameters(incoming)
            if ps.allSatisfy({ $0.channel >= 13 }) {
                for p in ps {
                    if p.channel == 13 && p.index == 1 { continue } // Ignored, like the real device.
                    if p.channel == 13 && p.index == 2 {
                        let n=(p.value>>4)+1;presets[n]=presetBuffer;presetBuffer=[:]
                        if let name=bufferedName { presetNames[n]=name;bufferedName=nil }
                    }
                    else { presetBuffer[p.channel*32+p.index]=corruptPresets && p.index == 4 ? p.value+1 : p.value }
                }
                return
            }
            for p in ps { state[p.channel,default:[:]][p.index]=p.value }
            if acknowledge { onMessage?(incoming) }
        } else if b[5]==6 {
            bufferedName=String(bytes:b[7..<21],encoding:.ascii)!.trimmingCharacters(in:.whitespaces)
        } else if b[5]==3, (0x0A...0x1D).contains(b[6]) {
            let n=Int(b[6])-9
            if let data=presets[n] {
                emit([RMEParameter(channel:13,index:1,value:(n-1)<<4)]+data.map { RMEParameter(channel:$0.key/32,index:$0.key%32,value:$0.value) })
            } else { emit([RMEParameter(channel:13,index:1,value:(n-1)<<4|15)]) }
            let name=presetNames[n] ?? "EQ Preset \(n)"
            onMessage?([0xF0,0,0x20,0x0D,0x71,5,UInt8(n)]+Array((String(repeating:" ",count:14-name.count)+name).utf8)+[0,0,0xF7])
        }
    }
}
final class FakeAudio:AudioTransport {
    var available=true, deviceID:AudioDeviceID=1, proxyID:AudioDeviceID=2
    var normal:AudioDeviceID=1, system:AudioDeviceID=1
    var scalar:Float=0, mute=false, gate=false
    /// Right channel when the user has set a balance; nil means both channels equal `scalar`.
    var rightScalar:Float?
    var configurations:[String]=[]
    var failRange=false, failVolume=false, playbackError=false
    func checkPlayback(_ box:AudioObjectID)throws { if playbackError { throw BridgeError.message("playback failed") } }
    func devices()->[AudioEndpoint] {
        (available ? [AudioEndpoint(id:deviceID,uid:"DAC-A",name:"ADI-2 DAC A")] : []) +
        [AudioEndpoint(id:proxyID,uid:Audio.proxyUID,name:"Detent"),AudioEndpoint(id:3,uid:"other",name:"Other output")]
    }
    func box()throws->AudioObjectID { 7 }
    func configure(_ b:AudioObjectID,_ s:String)throws { if failRange && s.hasPrefix("volumeRange=") { throw BridgeError.message("range failed") }; configurations.append(s); if s.hasPrefix("bridgeReady=") { gate=s.hasSuffix("1") } }
    func volume(_ id:AudioDeviceID,_ c:UInt32)throws->Float { c==2 ? rightScalar ?? scalar : scalar }
    func setVolume(_ id:AudioDeviceID,_ v:Float)throws { if failVolume { throw BridgeError.message("volume failed") }; scalar=v; rightScalar=nil }
    func setVolume(_ id:AudioDeviceID,left:Float,right:Float)throws { if failVolume { throw BridgeError.message("volume failed") }; scalar=left; rightScalar=right }
    func muted(_ id:AudioDeviceID)throws->Bool { mute }
    func setMute(_ id:AudioDeviceID,_ v:Bool)throws { mute=v }
    func defaultDevice(_ s:Bool)throws->AudioDeviceID { s ? system : normal }
    func setDefault(_ id:AudioDeviceID,_ s:Bool)throws { if s { system=id } else { normal=id } }
}
