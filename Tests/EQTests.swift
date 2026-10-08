import Foundation
@main struct Tests {
    static func incoming(_ params:[RMEParameter])throws->[UInt8] { var b=try RMEProtocol.message(params);b[5]=1;return b }
    static func main()throws {
        // RME official protocol example: address 4, band 4, 5 kHz.
        let known:[UInt8]=[0xF0,0,0x20,0x0D,0x71,1,0x23,0x53,0x74,0xF7]
        assert(RMEProtocol.parameters(known)==[RMEParameter(channel:4,index:14,value:5000)])
        for frequency in [20,200,2047,2048,5000,19999,20000] {
            let p=RMEParameter(channel:4,index:5,value:frequency)
            assert(RMEProtocol.parameters(try! incoming([p])) == [RMEProtocol.normalized(p)])
        }
        let validEQ:[Int:Int]=[2:1,3:0,4:0,5:100,6:10,7:0,8:500,9:10,10:0,11:1000,12:10,13:0,14:5000,15:10,16:0,17:0,18:10000,19:10,20:0,21:0,22:85,23:9,24:0,25:6500,26:7,28:0]
        var state=EQState(values:[3:[11:0],4:validEQ,5:validEQ],output:3)!
        assert(try! state.parameters(output:3).count==26)
        for hz in [20.0,100,1000,10000,20000] { assert(abs(state.response(frequency:hz))<1e-8) }
        let peak=EQBand(kind:.peak,frequency:1000,gain:6,q:1)
        assert(abs(EQResponse.decibels(peak,at:1000,sampleRate:44100)-6)<1e-8)
        assert(EQResponse.decibels(EQBand(kind:.highPass,frequency:1000,gain:0,q:0.707),at:50,sampleRate:44100)<(-40))
        state.left[2]=peak;state.dual=true;state.btEnabled=true;state.bass.gain = -3
        let params=try state.parameters(output:3)
        assert(params.count==43)
        assert(RMEProtocol.parameters(try! incoming(params))==params.map(RMEProtocol.normalized))
        assert(params.allSatisfy{$0.channel<12}) // Does not write stored preset memory.
        var invalid=state;invalid.left[1].gain=100
        do { _ = try invalid.parameters(output:3);assertionFailure("accepted invalid gain") } catch {}
        invalid=state;invalid.left[4].q=9.9
        do { _ = try invalid.parameters(output:3);assertionFailure("accepted invalid Q") } catch {}
        assert(!RMEProtocol.valid(RMEParameter(channel:4,index:28,value:22))) // Clear is not exposed.
        assert(!RMEProtocol.valid(RMEParameter(channel:13,index:2,value:15))) // The "empty" pattern is never written.
        assert(RMEProtocol.requestPreset(2)==[0xF0,0,0x20,0x0D,0x71,3,0x0B,0xF7])
        let name:[UInt8]=[0xF0,0,0x20,0x0D,0x71,5,2]+Array("  HD650  ".utf8)+[0,0xF7]
        let parsed=RMEProtocol.presetName(name);assert(parsed?.0==2 && parsed?.1=="HD650")
        for t in EQTemplate.all {
            let applied=t.applied(to:state)
            do { _ = try applied.parameters(output:6) } catch { assertionFailure("template \(t.name) is out of range: \(error)") }
            assert(applied.enabled && applied.left==applied.right && applied.bass==state.bass && applied.treble==state.treble)
        }
        assert(EQTemplate.presetNames.count == EQTemplate.all.count && EQTemplate.presetNames.allSatisfy { RMEProtocol.presetNameMessage(1,$0) != nil })
        print("PASS: every EQ template is within DAC ranges and keeps Bass/Treble")
        // Preset transfer: buffers on 13/14, flag word last on 13/1; names as 14 right-aligned ASCII + 2 zero bytes.
        var dualState=state;dualState.dual=true
        let batches=try! dualState.presetParameters(number:5)
        assert(batches.count == 3 && batches[0].allSatisfy { $0.channel == 13 } && batches[1].allSatisfy { $0.channel == 14 })
        assert(batches.last! == [RMEParameter(channel:13,index:2,value:4<<4|1)] && RMEProtocol.presetFlag(4<<4|1)! == (5,true))
        assert(!RMEProtocol.valid(RMEParameter(channel:13,index:1,value:0)))
        assert(RMEProtocol.presetFlag(4<<4|15) == nil && !batches.dropLast().joined().contains { [1,2,20,27,28].contains($0.index) })
        for b in batches { _ = try! RMEProtocol.message(b) }
        assert(RMEProtocol.presetNameMessage(2,"ProPhile 8")! == [0xF0,0,0x20,0x0D,0x71,6,2,0x20,0x20,0x20,0x20,0x50,0x72,0x6F,0x50,0x68,0x69,0x6C,0x65,0x20,0x38,0,0,0xF7])
        assert(RMEProtocol.presetNameMessage(1,"") == nil && RMEProtocol.presetNameMessage(1,"Thirteen chars") == nil && RMEProtocol.presetNameMessage(21,"x") == nil)
        print("PASS: DAC preset transfer uses buffers, a final flag word and RME's name format")
        print("PASS: official frequency vector, x10 quantization boundaries, full 5-band/stereo/B-T round trip, EQ validation, preset write protection, preset names, response model")
    }
}
