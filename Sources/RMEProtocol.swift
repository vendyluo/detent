import Foundation

struct RMEParameter: Equatable {
    let channel: Int
    let index: Int
    let value: Int
}
enum RMEProtocol {
    static let device: UInt8 = 0x71
    static let request: [UInt8] = [0xF0,0,0x20,0x0D,device,3,9,0xF7]
    static let eqAddresses = [4,5,7,8,10,11,13,14]
    static let frequencies = [5,8,11,14,18,22,25]
    static func isFrequency(channel:Int,index:Int) -> Bool { eqAddresses.contains(channel) && frequencies.contains(index) }
    static func isDeviceMessage(_ b:[UInt8])->Bool {
        b.count>=8 && b.count<=256 && Array(b.prefix(5)) == [0xF0,0,0x20,0x0D,device] && b.last==0xF7 && b.dropFirst().dropLast().allSatisfy{$0<128} && [1,5,7].contains(b[5])
    }
    static func valid(_ p:RMEParameter)->Bool {
        if [3,6,9].contains(p.channel) {
            if p.index==12 { return (-1145...60).contains(p.value) }
            return [11,15].contains(p.index) && (0...1).contains(p.value)
        }
        guard [4,5,7,8,10,11,13,14].contains(p.channel) else { return false }
        let left=[4,7,10,13].contains(p.channel), preset=p.channel >= 13
        if preset {
            // Preset buffers carry band and Bass/Treble data plus the flag word that commits them.
            if p.index == 1 { return p.channel == 13 && presetFlag(p.value) != nil }
            if [2,27,28].contains(p.index) { return false }
        } else if p.index == 1 { return false }
        switch p.index {
        case 2,20,27: return left && (0...1).contains(p.value)
        case 3: return (0...3).contains(p.value)
        case 16: return (0...2).contains(p.value)
        case 4,7,10,13,17: return (-24...24).contains(p.value)
        case 5,8,11: return (20...20000).contains(p.value)
        case 14,18: return (200...20000).contains(p.value)
        case 6,9,12: return (5...99).contains(p.value)
        case 15,19: return (5...50).contains(p.value)
        case 21,24: return left && (-24...24).contains(p.value)
        case 22: return left && (20...150).contains(p.value)
        case 25: return left && (3000...10000).contains(p.value)
        case 23,26: return left && (5...15).contains(p.value)
        case 28: return left && (0...21).contains(p.value) // Never send Clear or write a stored preset.
        default: return false
        }
    }
    static func normalized(_ p:RMEParameter)->RMEParameter {
        let v=isFrequency(channel:p.channel,index:p.index) && p.value>2047 ? Int((Double(p.value)/10).rounded())*10 : p.value
        return RMEParameter(channel:p.channel,index:p.index,value:v)
    }
    static func message(_ parameters:[RMEParameter]) throws->[UInt8] {
        guard !parameters.isEmpty, parameters.count<=83, parameters.allSatisfy(valid) else { throw BridgeError.message(L("不支援或超出範圍的 RME 參數", "Unsupported or out-of-range RME parameter")) }
        var b:[UInt8]=[0xF0,0,0x20,0x0D,device,2]
        for parameter in parameters {
            let p=normalized(parameter)
            let bits=isFrequency(channel:p.channel,index:p.index) ? (p.value>2047 ? 0x800 | (p.value/10) : p.value) : p.value & 0xFFF
            b += [UInt8(p.channel<<3 | p.index>>2),UInt8((p.index&3)<<5 | bits>>7),UInt8(bits&127)]
        }
        return b+[0xF7]
    }
    static func set(channel:Int,index:Int,value:Int)->[UInt8] { try! message([RMEParameter(channel:channel,index:index,value:value)]) }
    /// EQ-Preset flag word on address 13, index 1 (RME's table says 2; its own example and the hardware use 1).
    /// Bits 8..4 hold the preset number counted from zero, bit 0 the Dual EQ flag. Never the "empty" pattern.
    static func presetFlag(number:Int,dual:Bool)->Int { (number-1)<<4 | (dual ? 1 : 0) }
    static func presetFlag(_ value:Int)->(number:Int,dual:Bool)? {
        let number=(value>>4)+1
        guard (1...20).contains(number), value & 15 <= 1 else { return nil }
        return (number,value & 1 == 1)
    }
    /// Preset names travel as 14 right-aligned ASCII characters plus two zero bytes, as the device sends them.
    static let presetNameLength=12
    static func presetNameMessage(_ number:Int,_ name:String)->[UInt8]? {
        guard (1...20).contains(number), (1...presetNameLength).contains(name.count),
              name.unicodeScalars.allSatisfy({ (32...126).contains($0.value) }) else { return nil }
        let padded=String(repeating:" ",count:14-name.count)+name
        return [0xF0,0,0x20,0x0D,device,6,UInt8(number)]+Array(padded.utf8)+[0,0,0xF7]
    }
    static func requestPreset(_ number:Int)->[UInt8] {
        precondition((1...20).contains(number))
        return [0xF0,0,0x20,0x0D,device,3,UInt8(number+9),0xF7]
    }
    static func presetName(_ b:[UInt8])->(Int,String)? {
        guard isDeviceMessage(b), b[5]==5, (1...20).contains(b[6]) else { return nil }
        let name=String(bytes:b.dropFirst(7).dropLast().prefix(while:{$0 != 0}),encoding:.ascii)?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
        return (Int(b[6]),name)
    }
    static func parameters(_ bytes:[UInt8])->[RMEParameter] {
        guard isDeviceMessage(bytes), bytes[5]==1, (bytes.count-7)%3==0 else { return [] }
        return stride(from:6,to:bytes.count-1,by:3).map { i in
            let a=Int(bytes[i]), b=Int(bytes[i+1]), c=Int(bytes[i+2]), channel=a>>3
            if channel==12 { return RMEParameter(channel:channel,index:((a&7)<<3)|(b>>4),value:((b&15)<<7)|c) }
            let index=((a&7)<<2)|(b>>5), raw=((b&31)<<7)|c
            let value = isFrequency(channel:channel,index:index) ? ((raw&0x800 != 0) ? (raw&0x7FF)*10 : raw) : (raw>=2048 ? raw-4096 : raw)
            return RMEParameter(channel:channel,index:index,value:value)
        }
    }
    static func scalar(_ db:Double)->Float { Float(min(1,max(0,(db+114.5)/114.5))) }
    static func decibels(_ scalar:Float)->Double { Double(min(1,max(0,scalar)))*114.5-114.5 }
}

// MIDI packets may contain partial/multiple SysEx frames, with interleaved realtime bytes.
struct SysExFramer {
    private var pending: [UInt8] = []
    mutating func consume(_ bytes: [UInt8]) -> [[UInt8]] {
        var result: [[UInt8]] = []
        for b in bytes {
            if b >= 0xF8 { continue }
            if b == 0xF0 { pending = [b] }
            else if b == 0xF7 {
                if !pending.isEmpty { pending.append(b); result.append(pending) }
                pending.removeAll(keepingCapacity: true)
            } else if b >= 0x80 { pending.removeAll(keepingCapacity: true) }
            else if !pending.isEmpty {
                pending.append(b)
                if pending.count > 255 { pending.removeAll(keepingCapacity: true) }
            }
        }
        return result
    }
}

enum BridgeError: Error, CustomStringConvertible {
    case message(String)
    var description:String { switch self { case .message(let s): return s } }
}
