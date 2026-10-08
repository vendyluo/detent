import Foundation
import CoreAudio
@main struct Tests {
    static func main()throws {
        let key="local.Detent.Tests.\(UUID())", defaults=UserDefaults(suiteName:key)!
        defer { defaults.removePersistentDomain(forName:key) }
        let settings=Settings(defaults), clock=Clock(), midi=FakeMIDI(), audio=FakeAudio()
        let b=try Bridge(midi:midi,audio:audio,settings:settings,now:{clock.time},startTimer:false)
        assert(b.synchronized && !b.enabled && midi.writes.isEmpty)
        try b.enable(); assert(b.enabled && audio.gate && audio.normal==2 && settings.wanted)
        audio.scalar=VolumeRange().scalar(-20); b.tick()
        assert(midi.state[3]?[12] == -200)
        midi.hardware(3,12,-150); assert(abs(audio.scalar-VolumeRange().scalar(-15))<0.0001)
        // Unrelated MIDI topology changes do not disturb the route.
        b.topologyChanged(); assert(b.enabled)
        // Device IDs may change across unplug/replug; match persistent UIDs, not old IDs.
        midi.present=false; audio.available=false; b.topologyChanged()
        assert(!b.enabled && b.wanted && !audio.gate)
        clock.time += 4; b.tick(); assert(!b.enabled)
        midi.present=true; audio.available=true; audio.deviceID=11; clock.time += 4; b.tick()
        assert(b.enabled && audio.normal==2 && midi.state[3]?[12] == -150)
        b.willSleep(); assert(!audio.gate && b.wanted)
        clock.time += 120; b.tick(); assert(!b.enabled)
        b.didWake(); b.tick(); assert(b.enabled)
        // Setting a ceiling only lowers hardware volume, never raises it.
        try b.setRange(VolumeRange(minimum:-60,maximum:-25)); assert(midi.state[3]?[12] == -250)
        clock.time += 1; b.tick(); assert(audio.gate)
        midi.hardware(3,12,-100); assert(midi.state[3]?[12] == -250)
        midi.hardware(3,12,-900); assert(audio.scalar>0 && midi.state[3]?[12] == -900)
        try b.setMuted(true); b.tick(); assert(midi.state[3]?[15] == 1 && midi.state[3]?[12] == -900)
        try b.setMuted(false); b.tick(); assert(midi.state[3]?[15] == 0 && midi.state[3]?[12] == -900)
        // User switching to another output cancels restoration.
        audio.normal=3; b.tick(); assert(!b.enabled && !b.wanted && audio.normal==3)
        try b.enable(); b.willSleep(); audio.normal=3; b.didWake(); b.tick(); assert(!b.enabled && !b.wanted && audio.normal==3)
        try b.enable(); b.select(channel:6); assert(b.enabled && b.channel==6 && midi.state[6]?[12] == -300)
        b.shutdown(); assert(settings.wanted && audio.normal==3)
        let b2=try Bridge(midi:midi,audio:audio,settings:settings,now:{clock.time},startTimer:false)
        b2.tick(); assert(b2.enabled && b2.channel==6)
        b2.disable(); assert(!settings.wanted)
        // Missing acknowledgement is a failure; never keep renewing a stale gain lease.
        try b2.enable(); midi.acknowledge=false; audio.scalar=0.4; b2.tick()
        clock.time+=2.6; b2.tick(); assert(!b2.wanted && !audio.gate)
        assert(!VolumeRange(minimum:-10,maximum:-12).valid)
        assert(!VolumeRange(minimum:.nan,maximum:0).valid)
        // A quiet connected DAC stays synchronized via read-only polling.
        midi.acknowledge=true;b2.disable();try b2.requestSettings();try b2.enable()
        for _ in 0..<600 { clock.time += 0.5;b2.tick();assert(b2.enabled && b2.synchronized && audio.gate) }
        // A failure remains visible even after healthy state packets return.
        midi.acknowledge=false;audio.scalar=0.35;b2.tick();clock.time += 2.6;b2.tick()
        assert(b2.failureMessage != nil)
        midi.acknowledge=true;midi.snapshot();assert(b2.failureMessage != nil && b2.controlSummary.contains("需要處理"))
        b2.disable();assert(b2.failureMessage == nil)
        // Range failures must stop renewal and retain the last accepted mapping.
        for volumeFailure in [false,true] {
            b2.disable();try b2.enable()
            let saved=b2.range
            audio.failRange = !volumeFailure;audio.failVolume=volumeFailure
            do { try b2.setRange(VolumeRange(minimum:-80,maximum:-60));assertionFailure("expected failure") } catch {}
            assert(!b2.enabled && !b2.wanted && !audio.gate && b2.range==saved && b2.failureMessage != nil)
            audio.failRange=false;audio.failVolume=false
            for _ in 0..<8 {clock.time += 0.5;b2.tick();assert(!audio.gate && !b2.enabled)}
        }
        // Asynchronous HAL errors must reach the UI and release the route.
        try b2.enable();audio.playbackError=true;clock.time += 1.1;b2.tick()
        assert(!b2.enabled && !b2.wanted && !audio.gate && b2.failureMessage != nil)
        audio.playbackError=false;try b2.enable();clock.time += 1.1;b2.tick();assert(b2.enabled && audio.gate)
        // Off-grid ceilings snap to the DAC's 0.1 dB grid instead of clamp-looping above the ceiling.
        b2.disable();midi.hardware(6,12,-100);try b2.setRange(VolumeRange(minimum:-80,maximum:-20.04))
        assert(b2.range.maximum == -20.0 && Settings(defaults).range(6).maximum == -20.0)
        defaults.set(-20.04,forKey:"maximum.6");assert(b2.range.maximum == -20.0)
        let sendsBefore=midi.writes.count;try b2.enable()
        assert(b2.enabled && midi.state[6]?[12] == -200 && midi.writes.count-sendsBefore < 6)
        // A continuous volume drag with acknowledgements in flight keeps renewing the lease.
        midi.acknowledge=false;clock.time += 1;b2.tick();audio.configurations.removeAll()
        for step in 1...40 { audio.scalar=0.5+Float(step)/200;clock.time += 0.05;b2.tick() }
        assert(b2.enabled && audio.configurations.filter { $0=="bridgeReady=1" }.count >= 4)
        // Unmuting still closes the gate until the DAC confirms.
        midi.acknowledge=true;midi.snapshot();audio.mute=true;b2.tick();midi.acknowledge=false;audio.configurations.removeAll()
        audio.mute=false;b2.tick();clock.time += 0.5;b2.tick()
        assert(!audio.gate && !audio.configurations.contains("bridgeReady=1"))
        midi.acknowledge=true;midi.snapshot();clock.time += 0.5;b2.tick();assert(audio.gate)
        // Balance survives syncing, and the louder side sets the DAC level.
        do {
            let suite="local.Detent.BalanceTests.\(UUID())",balanceDefaults=UserDefaults(suiteName:suite)!
            defer { balanceDefaults.removePersistentDomain(forName:suite) }
            let m=FakeMIDI(),a=FakeAudio(),t=Clock()
            let bb=try Bridge(midi:m,audio:a,settings:Settings(balanceDefaults),now:{t.time},startTimer:false)
            try bb.enable()
            a.scalar=0.6;a.rightScalar=0.3;t.time += 0.1;bb.tick()
            assert(m.state[3]?[12] == Int((VolumeRange().decibels(0.6)*10).rounded()) && a.rightScalar == 0.3)
            m.hardware(3,12,-200)
            let s=VolumeRange().scalar(-20)
            assert(abs(a.scalar-s)<0.0001 && abs((a.rightScalar ?? 0)-s/2)<0.0001)
            // Full balance to one side is a level, not mute.
            a.scalar=0.7;a.rightScalar=0;t.time += 0.1;bb.tick();assert(m.state[3]?[15] == 0)
        }
        print("PASS: left/right balance is preserved through sync and full balance does not mute")
        // The IEM jack flag arrives on the Line Out address and follows plugging.
        do {
            let m=FakeMIDI(),t=Clock(),suite="local.Detent.JackTests.\(UUID())",d=UserDefaults(suiteName:suite)!
            defer { d.removePersistentDomain(forName:suite) }
            let jb=try Bridge(midi:m,audio:FakeAudio(),settings:Settings(d),now:{t.time},startTimer:false)
            assert(jb.iemPlugged == nil)
            m.hardware(3,2,1);assert(jb.iemPlugged == true)
            m.hardware(3,2,0);assert(jb.iemPlugged == false)
        }
        print("PASS: IEM jack state is read from the Line Out address")
        // Below the slider floor, steps move from the real level instead of jumping to the floor.
        do {
            let suite="local.Detent.FloorTests.\(UUID())",floorDefaults=UserDefaults(suiteName:suite)!
            defer { floorDefaults.removePersistentDomain(forName:suite) }
            let m=FakeMIDI(),a=FakeAudio(),t=Clock()
            m.state[3]?[12] = -1000
            let fb=try Bridge(midi:m,audio:a,settings:Settings(floorDefaults),now:{t.time},startTimer:false)
            try fb.setRange(VolumeRange(minimum:-60,maximum:0));try fb.enable()
            a.scalar += 0.0625;t.time += 0.1;fb.tick()
            assert((-965...(-960)).contains(m.state[3]?[12] ?? 0) && a.scalar<0.001)
            let before=m.state[3]?[12] ?? 0;try fb.setVolume(-59.5);assert(m.state[3]?[12] == before+5)
            fb.disable();try fb.setVolume(-60.5);assert(m.state[3]?[12] == before)
            try fb.enable();m.hardware(3,12,-605);a.scalar += 0.0625;t.time += 0.1;fb.tick()
            assert((-570...(-565)).contains(m.state[3]?[12] ?? 0) && a.scalar>0.04)
        }
        print("PASS: below the slider floor, keys and buttons step from the real level; no jump to the floor")
        // Picking the proxy in Control Center while native control is off enables it, or falls back to the DAC.
        do {
            let suite="local.Detent.PickTests.\(UUID())",pickDefaults=UserDefaults(suiteName:suite)!
            defer { pickDefaults.removePersistentDomain(forName:suite) }
            let m=FakeMIDI(),a=FakeAudio(),t=Clock()
            let pb=try Bridge(midi:m,audio:a,settings:Settings(pickDefaults),now:{t.time},startTimer:false)
            assert(!pb.enabled && !pb.wanted)
            a.normal=2;a.system=2;t.time += 0.1;pb.tick()
            assert(pb.enabled && pb.wanted && a.gate && a.normal==2)
            pb.disable();assert(a.normal==a.deviceID)
            m.hardware(3,13,1);a.normal=2;a.system=2;t.time += 2.1;pb.tick()
            assert(!pb.enabled && !pb.wanted && a.normal==a.deviceID && a.system==a.deviceID && pb.status.contains("實體 DAC"))
        }
        print("PASS: selecting the proxy output with native control off enables it, or routes to the physical DAC when it cannot")
        // A locked output hands audio to the physical DAC instead of leaving a silent proxy, then resumes.
        do {
            let suite="local.Detent.LockTests.\(UUID())",lockDefaults=UserDefaults(suiteName:suite)!
            defer { lockDefaults.removePersistentDomain(forName:suite) }
            let m=FakeMIDI(),a=FakeAudio(),t=Clock()
            m.state[6]?[13]=1;a.normal=3;a.system=3
            let lb=try Bridge(midi:m,audio:a,settings:Settings(lockDefaults),now:{t.time},startTimer:false)
            try lb.enable();assert(lb.enabled && a.normal==2)
            lb.select(channel:6)
            assert(!lb.enabled && lb.wanted && a.normal==a.deviceID && a.system==a.deviceID && lb.controlSummary.contains("解鎖後"))
            t.time += 2.1;lb.tick();assert(!lb.enabled && a.normal==a.deviceID)
            m.hardware(6,13,0);t.time += 2.1;lb.tick();assert(lb.enabled && a.normal==2 && a.gate)
            // Locking while active pauses the same way.
            m.hardware(6,13,1);t.time += 0.1;lb.tick();assert(!lb.enabled && lb.wanted && a.normal==a.deviceID)
            m.hardware(6,13,0);t.time += 2.1;lb.tick();assert(lb.enabled && a.normal==2)
            // The user's original output is still what Disable restores.
            lb.disable();assert(a.normal==3 && a.system==3)
        }
        print("PASS: locked output plays through the physical DAC, resumes when unlocked, and Disable still restores the original output")
        print("PASS: off-grid ceiling snaps without a clamp loop; lease renews during a continuous drag; unmute holds the gate until confirmed")
        print("PASS: range configuration/scalar failures stop renewal and roll back preferences; driver failure stops control; explicit retry recovers")
        print("PASS: startup/handshake, two-way volume, unrelated topology, reconnect with new IDs, sleep/wake, ceiling, mute without gain jump, manual routing, target persistence, restart, acknowledgement timeout")
    }
}
