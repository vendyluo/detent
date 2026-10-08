import Foundation
import CoreAudio
import os

/// Status transitions go to the unified log so field problems can be diagnosed with
/// `log show --predicate 'subsystem == "local.Detent"'`.
let bridgeLog = Logger(subsystem: "local.Detent", category: "bridge")

final class Bridge {
    let midi: MIDITransport
    let audio: AudioTransport
    let settings: Settings
    let now: () -> TimeInterval
    var channel: Int { get { settings.channel } set { settings.channel = newValue } }
    var range: VolumeRange { settings.range(channel) }
    var status = L("正在讀取 ADI-2…", "Reading ADI-2…") {
        didSet { if status != oldValue { bridgeLog.info("status: \(self.status, privacy: .public) enabled=\(self.enabled) wanted=\(self.wanted) connected=\(self.connected)") } }
    }
    private(set) var failureMessage:String? {
        didSet { if let failureMessage { bridgeLog.error("failure: \(failureMessage, privacy: .public)") } }
    }
    private(set) var routeName=L("讀取中…", "Loading…")
    private var lastPoll:TimeInterval = -1e9
    var controlSummary:String {
        if failureMessage != nil { return L("控制已停止 · 需要處理", "Control stopped · Action needed") }
        if !connected { return wanted ? L("裝置離線 · 等待自動重連", "Device offline · Reconnecting automatically") : L("裝置離線", "Device offline") }
        if !synchronized { return wanted ? L("DAC 音量已鎖定 · 解鎖後自動恢復原生控制", "DAC volume locked · Native control resumes when unlocked") : L("DAC 音量已鎖定", "DAC volume is locked") }
        if enabled { return hasPending ? L("原生控制 · 正在同步", "Native control · Syncing") : L("原生控制 · 已啟用", "Native control · Enabled") }
        return wanted ? L("正在恢復原生控制…", "Restoring native control…") : L("直接控制 DAC · 原生控制未啟用", "Direct DAC control · Native control off")
    }
    var onUpdate: (() -> Void)?
    private(set) var enabled = false
    private(set) var wanted: Bool
    private(set) var values: [Int:[Int:Int]] = [:]
    private(set) var proxy: AudioEndpoint?
    private(set) var presetNames: [Int:String] = [:]
    private(set) var emptyPresets: Set<Int> = []
    private(set) var loadedPresetNames = false
    /// Contents of DAC presets as last read back, keyed by preset number, then channel*32+index.
    private(set) var presetData: [Int:[Int:Int]] = [:]
    /// The preset whose data the device is currently sending, set by its flag word.
    private var reportingPreset: Int?
    enum PresetWrite: Equatable { case verifying(Int), saved(Int), failed(Int,String) }
    private(set) var presetWrite: PresetWrite?
    private var presetWriteExpected: [Int:Int] = [:], presetWriteName = "", presetWriteStarted: TimeInterval = 0, presetWriteDataMatched = false
    private var box: AudioObjectID = 0
    private var lastScalar: Float = 0
    private var lastMute = false
    private var lastSeen: TimeInterval = -1e9, lastConnect: TimeInterval = -1e9
    private var lastLease: TimeInterval = -1e9, lastTopologyCheck: TimeInterval = -1e9
    private var priorOutputUID: String?, priorSystemUID: String?
    private var resumeRouteUID: String?
    private var sleeping = false
    private var timer: Timer?
    private var pending: [Int:(value:Int,sent:TimeInterval)] = [:]
    private var presetQueue: [Int] = []
    private var lastPresetRequest: TimeInterval = -1e9
    private var lastActivationAttempt: TimeInterval = -1e9
    /// Set while an unmute or ceiling clamp awaits DAC confirmation; the playback lease stays closed until then.
    private var holdGate = false
    /// Native control was paused because the DAC locked this output's volume; audio was handed to the physical DAC.
    private var pausedForLock = false
    var db: Double? { values[channel]?[12].map { Double($0)/10 } }
    var hardwareMuted: Bool { values[channel]?[15] == 1 }
    var connected: Bool { now()-lastSeen < 3 && db != nil && values[channel]?[15] != nil }
    var synchronized: Bool { connected && values[channel]?[13] == 0 }
    var locked: Bool { connected && (values[channel]?[13] ?? 0) != 0 }
    var hasPending: Bool { !pending.isEmpty }
    var eqAddress: Int { channel+1 }
    var eqEnabled: Bool { values[eqAddress]?[2] == 1 }
    var btEnabled: Bool { values[eqAddress]?[20] == 1 }
    var dualEQ: Bool { values[channel]?[11] == 1 }
    var selectedPreset: Int? { values[eqAddress]?[28] }
    /// Reported on the Line Out address: 1 while the 3.5 mm IEM jack is in use.
    /// Measured on hardware; the 6.3 mm Phones jack changes no parameter, so its state is unknown.
    var iemPlugged: Bool? { values[3]?[2].map { $0 == 1 } }
    var channelName: String { [3:"Line Out",6:"Phones",9:"IEM"][channel] ?? "Line Out" }

    convenience init() throws { try self.init(midi:RMEConnection(),audio:SystemAudio(),settings:Settings()) }
    init(midi:MIDITransport,audio:AudioTransport,settings:Settings,now:@escaping()->TimeInterval = { ProcessInfo.processInfo.systemUptime },startTimer:Bool = true) throws {
        self.midi=midi; self.audio=audio; self.settings=settings; self.now=now
        wanted=settings.autoRestore && settings.wanted
        midi.onMessage = { [weak self] in self?.receive($0) }
        midi.onTopology = { [weak self] in self?.topologyChanged() }
        reconnect()
        if startTimer {
            let t=Timer(timeInterval:0.05,repeats:true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t,forMode:.common); timer=t
        }
    }
    deinit { timer?.invalidate() }
    private func uid(_ id:AudioDeviceID) -> String? { audio.devices().first { $0.id == id }?.uid }
    private func currentRoute() -> String? { (try? audio.defaultDevice(false)).flatMap(uid) }
    private func setWanted(_ value:Bool) { wanted=value; settings.wanted=value }
    private func reconnect() {
        lastConnect=now()
        do { try midi.connect(); status=L("已找到 ADI-2，等待硬體回報…", "ADI-2 found. Waiting for device state…") }
        catch { status=wanted ? L("等待 ADI-2 USB 重連…", "Waiting for ADI-2 USB connection…") : String(describing:error) }
        onUpdate?()
    }
    func topologyChanged() {
        if !midi.topologyIsCurrent() { suspend(L("USB 連線變更，等待重新連線…", "USB connection changed. Reconnecting…")) }
    }
    func willSleep() { sleeping=true; suspend(L("休眠中；喚醒後重新同步", "Sleeping · Will sync after wake")) }
    func didWake() { sleeping=false; lastConnect = -1e9; status=L("已喚醒，等待 ADI-2…", "Awake · Waiting for ADI-2…"); onUpdate?() }
    private func suspend(_ message:String) {
        bridgeLog.notice("suspend: \(message, privacy: .public) route kept on proxy=\(self.proxy != nil)")
        if enabled || resumeRouteUID == nil { resumeRouteUID=currentRoute() }
        if box != 0 { try? audio.configure(box,"bridgeReady=0") }
        enabled=false; lastActivationAttempt = -1e9; pending.removeAll(); values.removeAll(); presetQueue.removeAll()
        loadedPresetNames=false; presetNames.removeAll(); emptyPresets.removeAll()
        midi.disconnect(); lastSeen = -1e9; lastConnect = -1e9; box=0; proxy=nil
        status=message; onUpdate?()
    }
    func select(channel:Int) {
        guard [3,6,9].contains(channel), channel != self.channel else { return }
        let resume=wanted
        stop(restore:false); self.channel=channel
        if resume && synchronized { do { try activate() } catch { fail(error) } }
        else if resume && locked { pauseForLock() }
        else { status=L("控制目標：\(channelName)", "Control target: \(channelName)") }
        onUpdate?()
    }
    func enable() throws {
        failureMessage=nil;setWanted(true)
        do { try activate() }
        catch { setWanted(false); throw error }
    }
    private func activate() throws {
        guard synchronized, let db=db else { throw BridgeError.message(L("等待完整硬體狀態，或此輸出已鎖定音量", "Waiting for complete device state, or this output has locked volume")) }
        let devices=audio.devices()
        let targets=devices.filter { $0.name.contains("ADI-2 DAC") && $0.uid != Audio.proxyUID }
        guard targets.count == 1 else { throw BridgeError.message(L("需要恰好一台 ADI-2 DAC", "Exactly one ADI-2 DAC is required")) }
        if let bound=settings.deviceUID, bound != targets[0].uid { throw BridgeError.message(L("連接的 DAC 與先前不同；請先重新綁定裝置", "This DAC differs from the paired device. Pair it again first.")) }
        guard let p=devices.first(where:{$0.uid == Audio.proxyUID}) else { throw BridgeError.message(L("找不到 Detent 驅動，請執行安裝程式", "Detent driver not found. Run the installer.")) }
        box=try audio.box(); proxy=p
        try audio.configure(box,"bridgeReady=0")
        try audio.configure(box,"outputDevice=\(targets[0].uid)")
        try audio.configure(box,"outputDeviceActiveCondition=2")
        try audio.configure(box,"outputDeviceBufferFrameSize=512")
        try audio.configure(box,"deviceName=Detent")
        try audio.configure(box,"volumeRange=\(range.minimum),\(range.maximum)")
        let route=try audio.defaultDevice(false), system=try audio.defaultDevice(true)
        // After a lock pause the route is the physical DAC we chose; keep the user's original output for later restore.
        if route != p.id && !pausedForLock { priorOutputUID=uid(route) }
        if system != p.id && !pausedForLock { priorSystemUID=uid(system) }
        pausedForLock=false
        // If a prior process crashed, the physical DAC is the recovery destination.
        if priorOutputUID == nil { priorOutputUID=targets[0].uid }
        if priorSystemUID == nil { priorSystemUID=targets[0].uid }
        lastScalar=range.scalar(min(db,range.maximum)); lastMute=hardwareMuted
        try writeProxy(p.id,lastScalar); try audio.setMute(p.id,lastMute)
        enabled=true
        do {
            try audio.setDefault(p.id,false); try audio.setDefault(p.id,true)
            settings.deviceUID=targets[0].uid; resumeRouteUID=Audio.proxyUID
            if db > range.maximum { holdGate=true; try send([RMEParameter(channel:channel,index:12,value:Int((range.maximum*10).rounded()))]) }
            else { try audio.configure(box,"bridgeReady=1"); lastLease=now() }
            status=L("原生控制已啟用 · \(channelName)", "Native control enabled · \(channelName)")
        } catch { stop(restore:true); throw error }
        onUpdate?()
    }
    private func stop(restore:Bool) {
        if box != 0 { try? audio.configure(box,"bridgeReady=0") }
        if restore, let p=proxy ?? audio.devices().first(where:{$0.uid == Audio.proxyUID}) {
            for (system,previous) in [(false,priorOutputUID),(true,priorSystemUID)] {
                if (try? audio.defaultDevice(system)) == p.id,
                   let device=audio.devices().first(where:{$0.uid == previous && $0.uid != Audio.proxyUID}) {
                    try? audio.setDefault(device.id,system)
                }
            }
        }
        enabled=false; pending.removeAll(); holdGate=false; lastLease = -1e9
    }
    /// Sets the proxy's main level while keeping the user's left/right balance.
    private func writeProxy(_ id:AudioDeviceID,_ value:Float) throws {
        if let l=try? audio.volume(id,1), let r=try? audio.volume(id,2), max(l,r)>0.00005, abs(l-r)>0.00005 {
            let peak=max(l,r); try audio.setVolume(id,left:value*l/peak,right:value*r/peak)
        } else { try audio.setVolume(id,value) }
    }
    private func adoptProxySelection() {
        lastActivationAttempt=now()
        bridgeLog.notice("proxy selected as output while native control is off; enabling")
        do { try enable() } catch {
            // Never leave a silent default: hand playback to the physical DAC with its level unchanged.
            let devices=audio.devices()
            if let p=devices.first(where:{$0.uid == Audio.proxyUID}),
               let dac=devices.first(where:{$0.uid != Audio.proxyUID && ($0.uid == settings.deviceUID || $0.name.contains("ADI-2 DAC"))}) {
                for system in [false,true] where (try? audio.defaultDevice(system)) == p.id { try? audio.setDefault(dac.id,system) }
            }
            status=L("無法啟用原生控制，已改由實體 DAC 播放：\(error)", "Couldn't enable native control; playing through the physical DAC: \(error)")
            onUpdate?()
        }
    }
    /// Keeps audio playing when the DAC locks the controlled volume: the proxy would otherwise stay
    /// the default output with its gate closed. Hardware gain is unchanged, so there is no level jump.
    private func pauseForLock() {
        let proxyDevice=proxy ?? audio.devices().first(where:{$0.uid == Audio.proxyUID})
        stop(restore:false)
        if let p=proxyDevice, let dac=audio.devices().first(where:{$0.uid == settings.deviceUID && $0.uid != Audio.proxyUID}) {
            for system in [false,true] where (try? audio.defaultDevice(system)) == p.id { try? audio.setDefault(dac.id,system) }
        }
        pausedForLock=true; resumeRouteUID=Audio.proxyUID
        status=L("此輸出音量已在 DAC 上鎖定 · 已改由實體 DAC 播放，解鎖後自動恢復", "This output's volume is locked on the DAC · Playing through the physical DAC; resumes when unlocked")
        onUpdate?()
    }
    func disable() { pausedForLock=false; failureMessage=nil;setWanted(false); stop(restore:true); resumeRouteUID=nil; status=L("原生控制已停用", "Native control off"); onUpdate?() }
    func shutdown() { timer?.invalidate(); stop(restore:true); midi.disconnect() }
    func rebindDevice() { disable(); settings.deviceUID=nil; status=L("已解除裝置綁定，下次啟用會綁定目前 DAC", "Device pairing cleared. The next activation will pair the connected DAC."); onUpdate?() }
    func setRange(_ newRange:VolumeRange) throws {
        let newRange=newRange.snapped
        guard newRange.valid else { throw BridgeError.message(L("音量範圍無效", "Invalid volume range")) }
        let previous=range
        do {
            // Persist only after the driver accepts the mapping. Any partial failure
            // stops control; the next explicit activation reapplies the saved mapping.
            if enabled, let p=proxy, let db=db {
                try audio.configure(box,"bridgeReady=0")
                try audio.configure(box,"volumeRange=\(newRange.minimum),\(newRange.maximum)")
                lastScalar=newRange.scalar(min(db,newRange.maximum))
                try writeProxy(p.id,lastScalar)
                try settings.setRange(newRange,channel:channel)
                if db > newRange.maximum { holdGate=true; try send([RMEParameter(channel:channel,index:12,value:Int((newRange.maximum*10).rounded()))]) }
                lastLease = -1e9
            } else { try settings.setRange(newRange,channel:channel) }
        } catch {
            try? settings.setRange(previous,channel:channel)
            fail(error)
            throw error
        }
        onUpdate?()
    }
    func setVolume(_ value:Double) throws {
        guard synchronized, value.isFinite else { throw BridgeError.message(L("DAC 尚未同步或音量無效", "DAC is not synchronized, or volume is invalid")) }
        // Below the slider floor the UI shows the floor. Move relative to the real hardware level so
        // one step is one step, instead of jumping straight up to the floor.
        let below=(db ?? range.minimum) < range.minimum
        var v=value
        if below, let current=db { v=current+(value-range.minimum) }
        v=min(range.maximum,max(below ? -114.5 : range.minimum,v))
        if enabled, let p=proxy, v >= range.minimum { try writeProxy(p.id,range.scalar(v)) }
        else { try send([RMEParameter(channel:channel,index:12,value:Int((v*10).rounded()))]) }
    }
    func setMuted(_ value:Bool) throws {
        guard synchronized else { throw BridgeError.message(L("DAC 尚未同步", "DAC is not synchronized")) }
        if enabled, let p=proxy { try audio.setMute(p.id,value) }
        else { try send([RMEParameter(channel:channel,index:15,value:value ? 1 : 0)]) }
    }
    func requestSettings() throws { try midi.send(RMEProtocol.request) }
    func send(_ parameters:[RMEParameter]) throws {
        guard connected else { throw BridgeError.message(L("DAC 尚未連接", "DAC is not connected")) }
        let bytes=try RMEProtocol.message(parameters)
        for item in parameters { let p=RMEProtocol.normalized(item); pending[p.channel*32+p.index]=(p.value,now()) }
        do { try midi.send(bytes); try midi.send(RMEProtocol.request) }
        catch { for p in parameters { pending.removeValue(forKey:p.channel*32+p.index) }; throw error }
    }
    func receive(_ msg:[UInt8]) {
        guard RMEProtocol.isDeviceMessage(msg) else { return }
        lastSeen=now()
        if let (number,name)=RMEProtocol.presetName(msg) { presetNames[number]=name }
        for p in RMEProtocol.parameters(msg) {
            // EQ-Preset flags. RME's table lists them at index 2, but the ADI-2 DAC sends them at index 1
            // (verified on hardware, firmware 2023): bits 8..4 are the preset number, all four low bits set means empty.
            if p.channel == 13 && p.index == 1 {
                let number=(p.value >> 4)+1
                if p.value & 15 == 15 { emptyPresets.insert(number);reportingPreset=nil;presetData[number]=nil }
                else { emptyPresets.remove(number);reportingPreset=number;presetData[number]=[:] }
            } else if p.channel == 13 || p.channel == 14, let n=reportingPreset {
                presetData[n,default:[:]][p.channel*32+p.index]=p.value
            }
            guard p.channel <= 12 else { continue } // Preset transfer buffers are not live settings.
            values[p.channel,default:[:]][p.index]=p.value
            if pending[p.channel*32+p.index]?.value == p.value { pending.removeValue(forKey:p.channel*32+p.index) }
        }
        checkPresetWrite()
        if synchronized && !loadedPresetNames {
            loadedPresetNames=true; presetQueue=Array(1...20)
        }
        if enabled, pending.isEmpty, let p=proxy, let db=db {
            if db > range.maximum {
                do { holdGate=true; try audio.configure(box,"bridgeReady=0"); try send([RMEParameter(channel:channel,index:12,value:Int((range.maximum*10).rounded()))]) }
                catch { fail(error) }
            } else if let l=try? audio.volume(p.id,1), let r=try? audio.volume(p.id,2), let m=try? audio.muted(p.id),
                      abs(max(l,r)-lastScalar)<0.00005, m==lastMute {
                do { lastScalar=range.scalar(db); lastMute=hardwareMuted; try writeProxy(p.id,lastScalar); try audio.setMute(p.id,lastMute) }
                catch { fail(error) }
            }
        }
        if !enabled && synchronized && !wanted && failureMessage == nil { status=L("已連接 · \(channelName)", "Connected · \(channelName)") }
        onUpdate?()
    }
    private func fail(_ error:Error) { failureMessage=String(describing:error);setWanted(false); stop(restore:true); status=String(describing:error); onUpdate?() }
    func tick() {
        guard !sleeping else { return }
        if now()-lastTopologyCheck > 1 {
            lastTopologyCheck=now()
            if let id=try? audio.defaultDevice(false) { routeName=audio.devices().first(where:{$0.id==id})?.name ?? L("未知輸出", "Unknown output") }
            if enabled {
                do { try audio.checkPlayback(box) } catch { fail(error);return }
                let devices=audio.devices()
                if !midi.topologyIsCurrent() || !devices.contains(where:{$0.uid == settings.deviceUID}) || !devices.contains(where:{$0.id == proxy?.id}) {
                    suspend(L("裝置暫時離線，等待重新連線…", "Device temporarily offline. Reconnecting…"))
                }
            }
        }
        if let overdue=pending.values.first(where:{now()-$0.sent>2.5}) {
            _ = overdue; fail(BridgeError.message(L("DAC 未確認設定，已停止自動控制；請重新同步後再試", "DAC did not confirm the settings. Control has stopped. Sync and try again."))); return
        }
        if connected && now()-lastPoll>1 {
            lastPoll=now()
            do { try requestSettings() } catch { suspend(L("MIDI 回報中斷，等待重新連線…", "MIDI connection interrupted. Reconnecting…")) }
        }
        if now()-lastSeen >= 3, enabled { suspend(L("硬體回報中斷，等待重新同步…", "Device updates stopped. Syncing again…")) }
        if !connected {
            if now()-lastConnect > 3 { reconnect() }
            if !connected { return }
        }
        if case .verifying(let n)? = presetWrite, now()-presetWriteStarted > 4 {
            // Matching EQ data is what matters; a name the device reformatted is not a failed save.
            if presetWriteDataMatched { presetWrite = .saved(n) }
            else {
                presetWrite = .failed(n,L("DAC 沒有回報存入的內容", "The DAC did not report the saved preset back"))
                bridgeLog.error("preset \(n, privacy: .public) write not confirmed")
            }
        }
        if !presetQueue.isEmpty && now()-lastPresetRequest>0.15 {
            let next=presetQueue.removeFirst(); lastPresetRequest=now()
            do { try midi.send(RMEProtocol.requestPreset(next)) } catch { status=String(describing:error) }
        }
        if !enabled {
            // The proxy only plays while this app renews its lease. If the user picks it in Control
            // Center or Sound settings while native control is off, treat that as asking for it.
            if !wanted && now()-lastActivationAttempt >= 2 && currentRoute() == Audio.proxyUID { adoptProxySelection(); return }
            if wanted && synchronized {
                if let resume=resumeRouteUID, let current=currentRoute(), current != resume && current != Audio.proxyUID && current != settings.deviceUID {
                    setWanted(false); stop(restore:true); status=L("偵測到其他音訊輸出，已取消自動恢復", "Another audio output was selected. Automatic restoration cancelled."); onUpdate?(); return
                }
                if now()-lastActivationAttempt < 2 { return }
                lastActivationAttempt=now()
                do { try activate() } catch { status=String(describing:error); onUpdate?() }
            }
            return
        }
        if locked { pauseForLock(); return }
        guard synchronized, let p=proxy else { suspend(L("音量鎖定或狀態未同步，等待恢復…", "Volume locked or not synchronized. Waiting…")); return }
        do {
            guard try audio.defaultDevice(false)==p.id else { disable(); status=L("已切換至其他音訊輸出", "Switched to another audio output"); onUpdate?(); return }
            let l=try audio.volume(p.id,1), r=try audio.volume(p.id,2), m=try audio.muted(p.id)
            guard l.isFinite && r.isFinite else { throw BridgeError.message(L("系統音量數值無效", "Invalid system volume value")) }
            // The louder channel is the main level; the other side only carries the user's balance.
            let peak=max(l,r)
            let volumeChanged=abs(peak-lastScalar)>0.00005
            if volumeChanged || m != lastMute {
                if lastMute && !m { holdGate=true; try audio.configure(box,"bridgeReady=0") }
                var changes:[RMEParameter]=[]
                var target=range.decibels(peak), level=peak
                // Below the floor every slider position near zero means "the floor"; step from the
                // real hardware level instead so one key press cannot jump tens of dB.
                if volumeChanged, let current=db, current < range.minimum {
                    target=max(-114.5,current+range.decibels(peak)-range.decibels(lastScalar))
                    level=range.scalar(target)
                }
                if volumeChanged { changes.append(RMEParameter(channel:channel,index:12,value:Int((target*10).rounded()))) }
                let mute=m || peak<=0
                changes.append(RMEParameter(channel:channel,index:15,value:mute ? 1 : 0))
                lastScalar=level; lastMute=mute
                if abs(level-peak)>0.00005 { try writeProxy(p.id,level) }
                try audio.setMute(p.id,mute)
                try send(changes); lastLease = -1e9
            }
            // Plain volume changes keep the lease alive while their acknowledgements are in flight;
            // otherwise a continuous Control Center drag would starve the 2 s lease and drop audio.
            if pending.isEmpty { holdGate=false }
            if !holdGate && now()-lastLease>0.4 { try audio.configure(box,"bridgeReady=1"); lastLease=now() }
            status=L("原生控制已啟用", "Native control enabled")+" · \(channelName) · \(String(format:"%.1f",db ?? 0)) dB\(hardwareMuted ? L(" · 靜音", " · Muted") : "")"
        } catch { fail(error) }
        onUpdate?()
    }
}

extension Bridge {
    /// Stores `state` in DAC EQ preset `number` under `name`, then reads the preset back to confirm it.
    /// This writes the DAC's own preset memory; the caller confirms overwriting a preset that is not empty.
    func savePreset(_ number:Int,name:String,state:EQState) throws {
        guard connected else { throw BridgeError.message(L("DAC 尚未連接", "DAC is not connected")) }
        if case .verifying? = presetWrite { throw BridgeError.message(L("上一個預設還在儲存中", "Still saving the previous preset")) }
        guard let nameMessage=RMEProtocol.presetNameMessage(number,name) else {
            throw BridgeError.message(L("名稱需為 1～\(RMEProtocol.presetNameLength) 個英數字元", "The name must be 1–\(RMEProtocol.presetNameLength) plain ASCII characters"))
        }
        let batches=try state.presetParameters(number:number)
        // Ignore echoes of the buffer writes; only a flag word from the read-back starts collecting.
        reportingPreset=nil;presetData[number]=nil
        presetWriteExpected=[:]
        for p in batches.dropLast().joined() { let n=RMEProtocol.normalized(p);presetWriteExpected[n.channel*32+n.index]=n.value }
        presetWriteName=name;presetWriteDataMatched=false
        for batch in batches { try midi.send(RMEProtocol.message(batch)) }
        try midi.send(nameMessage)
        presetWrite = .verifying(number);presetWriteStarted=now()
        bridgeLog.notice("saving EQ preset \(number, privacy: .public)")
        // Give the device a moment to store, then ask for the preset and its name.
        presetQueue.removeAll { $0 == number };presetQueue.insert(number,at:0);lastPresetRequest=now()+0.35
    }
    fileprivate func checkPresetWrite() {
        guard case .verifying(let n)? = presetWrite, reportingPreset == n || presetData[n] != nil, let data=presetData[n] else { return }
        guard presetWriteExpected.allSatisfy({ data[$0.key] == $0.value }) else {
            if data.count >= presetWriteExpected.count {
                presetWrite = .failed(n,L("讀回的內容與送出的不同", "The saved preset does not match what was sent"))
                bridgeLog.error("preset \(n, privacy: .public) read-back mismatch")
            }
            return
        }
        presetWriteDataMatched=true
        guard presetNames[n] == presetWriteName else { return }
        presetWrite = .saved(n)
    }
}
