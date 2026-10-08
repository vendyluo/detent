import AppKit
import Foundation
import ServiceManagement

final class TrackingSlider:NSSlider {
    var tracking=false
    override func mouseDown(with event:NSEvent) { tracking=true;defer { tracking=false };super.mouseDown(with:event) }
}
final class AppDelegate:NSObject,NSApplicationDelegate,NSMenuDelegate,NSWindowDelegate {
    var window:NSWindow!, bridge:Bridge!, item:NSStatusItem!, editor:EQEditor!
    var statusKnob:StatusKnob?
    var keyMonitor:Any?
    let hideDock=NSSwitch()
    let openOnLaunch=NSSwitch()
    let connectionDetail=NSTextField(wrappingLabelWithString:""), rangeFeedback=NSTextField(labelWithString:"")
    let languagePicker=NSPopUpButton()
    var menuStatus:NSMenuItem!
    var stepButtons:[NSButton]=[]
    let settings=Settings()
    let navigation=NSTableView(), pageHost=NSView(), pageTitle=NSTextField(labelWithString:L("音量", "Volume"))
    var pages:[NSView]=[]
    var pageNames:[String] { [L("音量", "Volume"), L("等化器", "Equalizer"), L("設定", "Settings")] }
    let label=NSTextField(labelWithString:L("正在連接…", "Connecting…"))
    lazy var statusPill=StatusPill(label:label)
    let outputs=NSSegmentedControl(), dial=VolumeDial()
    let toggle=NSButton(title:L("啟用原生音量", "Enable native volume"),target:nil,action:nil), mute=NSButton(title:L("靜音", "Mute"),target:nil,action:nil)
    let appearancePicker=NSPopUpButton()
    let targetTitle=NSTextField(labelWithString:"Line Out"), targetDetail=NSTextField(labelWithString:""), rangeCaption=NSTextField(labelWithString:"")
    let sideTarget=NSTextField(labelWithString:"Line Out"), sideReading=NSTextField(labelWithString:"—"), sideKnob=NSImageView()
    var refreshScheduled=false
    let launch=NSSwitch(), restore=NSSwitch()
    let showDB=NSSwitch()
    let loginStatus=NSTextField(labelWithString:""), floor=NSTextField(string:""), ceiling=NSTextField(string:"")
    var slider:TrackingSlider!, menuReading:NSTextField!
    var muteItem:NSMenuItem!, eqItem:NSMenuItem!, btItem:NSMenuItem!, enableItem:NSMenuItem!
    var outputItems:[NSMenuItem]=[], presetItems:[NSMenuItem]=[]
    var sleepObservers:[NSObjectProtocol]=[]
    var lastChannel=0, lastUIUpdate=Date.distantPast
    func applicationDidFinishLaunching(_ notification:Notification) {
        do { bridge=try Bridge(midi:RMEConnection(),audio:SystemAudio(),settings:settings) }
        catch { NSAlert(error:error).runModal();NSApp.terminate(nil);return }
        buildWindow()
        buildMenu()
        let nc=NSWorkspace.shared.notificationCenter
        sleepObservers.append(nc.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in self?.bridge.willSleep() })
        sleepObservers.append(nc.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in self?.bridge.didWake() })
        bridge.onUpdate = { [weak self] in self?.refresh() }
        refresh(force:true)
        applyDockPreference()
        keyMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let self=self, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else { return event }
            switch event.charactersIgnoringModifiers {
            case ",": self.showSettings();return nil
            case "w": self.window.performClose(nil);return nil
            case "q": self.quit();return nil
            default: return event
            }
        }
        Theme.apply(appearance:settings.appearance)
        if !settings.hasLaunchedPolish || settings.showWindowOnLaunch { show() }
        settings.hasLaunchedPolish=true
    }
    func container(_ stack:NSStackView)->NSView {
        let v=NSView();stack.translatesAutoresizingMaskIntoConstraints=false;v.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:v.leadingAnchor,constant:16),stack.trailingAnchor.constraint(lessThanOrEqualTo:v.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:v.topAnchor,constant:16),stack.bottomAnchor.constraint(lessThanOrEqualTo:v.bottomAnchor,constant:-12)])
        return v
    }
    func button(_ title:String,_ action:Selector)->NSButton { let b=NSButton(title:title,target:self,action:action);Theme.style(b);return b }
    func menuItem(_ title:String,_ action:Selector?,_ menu:NSMenu,tag:Int=0)->NSMenuItem {
        let i=NSMenuItem(title:title,action:action,keyEquivalent:"");i.target=self;i.tag=tag;menu.addItem(i);return i
    }
    func buildMenu() {
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusKnob=StatusKnob(item.button)
        item.button?.image=StatusKnob.image(position:0.5,amplitude:0)
        item.button?.imagePosition = .imageLeading;item.button?.font = .monospacedDigitSystemFont(ofSize:12,weight:.regular);item.button?.setAccessibilityLabel(L("ADI2 Native 音量控制", "ADI2 Native volume control"))
        let menu=NSMenu();menu.autoenablesItems=false;menu.delegate=self;item.menu=menu
        menuStatus=menuItem(L("連線中…", "Connecting…"),nil,menu);menuStatus.isEnabled=false
        let custom=NSMenuItem();let v=NSView(frame:NSRect(x:0,y:0,width:280,height:74))
        menuReading=NSTextField(labelWithString:"—");menuReading.frame=NSRect(x:16,y:44,width:248,height:20);menuReading.font = .monospacedDigitSystemFont(ofSize:14,weight:.medium);v.addSubview(menuReading)
        slider=TrackingSlider(value:0,minValue:-114.5,maxValue:0,target:self,action:#selector(slide));slider.frame=NSRect(x:12,y:12,width:254,height:22);slider.isContinuous=true;v.addSubview(slider);custom.view=v;menu.addItem(custom)
        muteItem=menuItem(L("靜音", "Mute"),#selector(toggleMute),menu)
        enableItem=menuItem(L("啟用原生控制", "Enable native control"),#selector(toggleBridge),menu)
        let outputParent=menuItem(L("控制目標", "Control target"),nil,menu);let sub=NSMenu();sub.autoenablesItems=false;outputParent.submenu=sub
        for (tag,title) in [(3,"Line Out"),(6,"Phones"),(9,"IEM")] { outputItems.append(menuItem(title,#selector(menuSelectOutput),sub,tag:tag)) }
        menu.addItem(.separator())
        eqItem=menuItem("EQ",#selector(toggleEQ),menu);btItem=menuItem("Bass／Treble",#selector(toggleBT),menu)
        let presetParent=menuItem(L("DAC EQ 預設", "DAC EQ presets"),nil,menu);let presets=NSMenu();presets.autoenablesItems=false;presetParent.submenu=presets
        for n in 1...20 { presetItems.append(menuItem(L("\(n). 讀取中…", "\(n). Loading…"),#selector(menuPreset),presets,tag:n)) }
        menu.addItem(.separator());_ = menuItem(L("顯示控制面板", "Open control panel"),#selector(show),menu)
        _ = menuItem(L("設定…", "Settings…"),#selector(showSettings),menu)
        let quitEntry=menuItem(L("結束並還原輸出", "Quit and restore output"),#selector(quit),menu);quitEntry.keyEquivalent="q"
        let main=NSMenu(), mainItem=NSMenuItem();main.addItem(mainItem);let appMenu=NSMenu();mainItem.submenu=appMenu
        _ = menuItem(L("顯示控制面板", "Open control panel"),#selector(show),appMenu)
        let preferences=menuItem(L("設定…", "Settings…"),#selector(showSettings),appMenu);preferences.keyEquivalent=","
        appMenu.addItem(.separator())
        let quitMain=menuItem(L("結束 ADI2 Native", "Quit ADI2 Native"),#selector(quit),appMenu);quitMain.keyEquivalent="q";NSApp.mainMenu=main
    }
    func menuWillOpen(_ menu:NSMenu) { refresh(force:true) }
    func refresh(force:Bool=false) {
        guard bridge != nil, item != nil else { return }
        let wait=0.15-Date().timeIntervalSince(lastUIUpdate)
        if !force && wait>0 {
            // Coalesce bursts but always paint the last state.
            if !refreshScheduled { refreshScheduled=true;DispatchQueue.main.asyncAfter(deadline:.now()+wait) { [weak self] in self?.refreshScheduled=false;self?.refresh(force:true) } }
            return
        }
        lastUIUpdate=Date()
        statusKnob?.update(db:bridge.db,range:bridge.range)
        label.stringValue=bridge.controlSummary
        statusPill.tone=bridge.failureMessage != nil || (bridge.connected && !bridge.synchronized) ? .warning : !bridge.connected ? .offline : bridge.enabled ? (bridge.hasPending ? .busy : .live) : bridge.wanted ? .busy : .ready
        connectionDetail.stringValue=bridge.failureMessage ?? L("控制目標：\(bridge.channelName) · Mac 輸出：\(bridge.routeName)", "Target: \(bridge.channelName) · Mac output: \(bridge.routeName)")
        menuStatus.title=bridge.controlSummary
        for b in stepButtons { b.isEnabled=bridge.synchronized }
        hideDock.state=settings.hideDock ? .on : .off
        openOnLaunch.state=settings.showWindowOnLaunch ? .on : .off
        let value=(bridge.connected ? bridge.db : nil).map { String(format:"%.1f",$0) } ?? "—"
        item.button?.title=settings.showDB ? " \(value)" : "";item.button?.appearsDisabled = !bridge.connected;item.button?.toolTip="ADI2 Native · \(Localization.translated(bridge.status))"
        menuReading.stringValue="\(bridge.channelName)  \(value) dB"
        let range=bridge.range
        let shown=min(range.maximum,max(range.minimum,bridge.db ?? range.minimum))
        slider.minValue=range.minimum;slider.maxValue=range.maximum;if !slider.tracking { slider.doubleValue=shown };slider.isEnabled=bridge.synchronized
        dial.minValue=range.minimum;dial.maxValue=range.maximum;if !dial.tracking { dial.value=shown }
        dial.hasValue=bridge.connected;dial.muted=bridge.hardwareMuted;dial.mutedText=L("靜音", "Muted");dial.isEnabled=bridge.synchronized
        targetTitle.stringValue=bridge.channelName;targetDetail.stringValue=[3:"RCA／XLR",6:"6.3 mm",9:"3.5 mm"][bridge.channel] ?? ""
        rangeCaption.stringValue=L("拖曳、捲動或方向鍵調整 · 按住 ⌥ 以 0.1 dB 微調", "Drag, scroll or use arrow keys · Hold ⌥ for 0.1 dB steps")
        sideKnob.image=StatusKnob.image(position:bridge.connected ? (shown-range.minimum)/(range.maximum-range.minimum) : 0,amplitude:0)
        sideKnob.contentTintColor=bridge.connected ? (bridge.hardwareMuted ? .systemRed : .controlAccentColor) : .tertiaryLabelColor
        sideTarget.stringValue=bridge.channelName;sideReading.stringValue=bridge.connected ? "\(Theme.formatDB(bridge.db ?? 0)) dB\(bridge.hardwareMuted ? L(" · 靜音", " · Muted") : "")" : L("離線", "Offline")
        if lastChannel != bridge.channel { lastChannel=bridge.channel;rangeFeedback.stringValue="";rangeFeedback.isHidden=true;outputs.selectedSegment=[3,6,9].firstIndex(of:bridge.channel) ?? 0;floor.stringValue=String(format:"%.1f",range.minimum);ceiling.stringValue=String(format:"%.1f",range.maximum) }
        toggle.title=bridge.wanted ? L("停用並還原輸出", "Disable and restore output") : L("啟用原生音量", "Enable native volume");toggle.isEnabled=bridge.wanted || bridge.synchronized
        Theme.setProminent(toggle,!bridge.wanted)
        mute.state=bridge.hardwareMuted ? .on : .off;mute.isEnabled=bridge.synchronized
        mute.image=Theme.symbol(bridge.hardwareMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",13);mute.contentTintColor=bridge.hardwareMuted ? .systemRed : nil
        muteItem.state=mute.state;muteItem.isEnabled=bridge.synchronized
        enableItem.title=bridge.wanted ? L("停用原生控制", "Disable native control") : L("啟用原生控制", "Enable native control");enableItem.isEnabled=toggle.isEnabled
        for i in outputItems { i.state=i.tag==bridge.channel ? .on : .off }
        eqItem.state=bridge.eqEnabled ? .on : .off;eqItem.isEnabled=bridge.connected && bridge.eqState != nil && !editor.dirty
        btItem.state=bridge.btEnabled ? .on : .off;btItem.isEnabled=eqItem.isEnabled
        for i in presetItems {
            let name=bridge.presetNames[i.tag] ?? L("讀取中…", "Loading…")
            i.title="\(i.tag). \(name.isEmpty ? L("未命名", "Unnamed") : name)\(bridge.emptyPresets.contains(i.tag) ? L("（空白）", " (empty)") : "")"
            i.isEnabled=bridge.connected && !editor.dirty && bridge.presetNames[i.tag] != nil && !bridge.emptyPresets.contains(i.tag)
            i.state=bridge.selectedPreset==i.tag+1 ? .on : .off
        }
        restore.state=settings.autoRestore ? .on : .off;showDB.state=settings.showDB ? .on : .off
        let login=SMAppService.mainApp.status
        launch.state=login == .enabled ? .on : .off
        loginStatus.stringValue=login == .requiresApproval ? L("登入啟動等待系統核准：請開啟「登入項目設定」。", "Login launch needs approval. Open Login Items to allow it.") : L("登入啟動由 macOS 登入項目管理；移動 App 後需重新設定。", "Managed by macOS Login Items. Set it up again if you move this app.")
        editor.refresh()
    }
    func report(_ error:Error) { show();let a=NSAlert(error:error);a.beginSheetModal(for:window) }
    func attempt(_ action:()throws->Void) { do { try action();refresh(force:true) } catch { report(error) } }
    @objc func slide(_ sender:NSControl) { attempt { try bridge.setVolume(sender.doubleValue) } }
    // Step from the level the UI shows (the floor, when the hardware sits below it).
    @objc func quieter() { attempt { try bridge.setVolume(max(bridge.db ?? -40,bridge.range.minimum)-0.5) } }
    @objc func louder() { attempt { try bridge.setVolume(max(bridge.db ?? -40,bridge.range.minimum)+0.5) } }
    @objc func muteFromCheckbox() { attempt { try bridge.setMuted(mute.state == .on) } }
    @objc func toggleMute() { attempt { try bridge.setMuted(!bridge.hardwareMuted) } }
    @objc func toggleEQ() { attempt { try bridge.setEQEnabled(!bridge.eqEnabled) } }
    @objc func toggleBT() { attempt { try bridge.setBTEnabled(!bridge.btEnabled) } }
    @objc func menuPreset(_ sender:NSMenuItem) { attempt { try bridge.selectPreset(sender.tag) } }
    @objc func selectOutput() {
        if editor.dirty { outputs.selectedSegment=[3,6,9].firstIndex(of:bridge.channel) ?? 0;report(BridgeError.message(L("請先套用或重新讀取 EQ，再切換控制目標", "Apply or reload your EQ edits before changing the control target.")));return }
        bridge.select(channel:[3,6,9][max(0,outputs.selectedSegment)]);refresh(force:true)
    }
    @objc func menuSelectOutput(_ sender:NSMenuItem) {
        guard !editor.dirty else { show();report(BridgeError.message(L("請先套用或重新讀取 EQ，再切換控制目標", "Apply or reload your EQ edits before changing the control target.")));return }
        bridge.select(channel:sender.tag);refresh(force:true)
    }
    @objc func toggleBridge() { if bridge.wanted { bridge.disable();refresh(force:true) } else { attempt { try bridge.enable() } } }
    @objc func applyRange() {
        attempt {
            guard let lo=Double(floor.stringValue),let hi=Double(ceiling.stringValue) else { throw BridgeError.message(L("請輸入有效 dB 數字", "Enter a valid dB value")) }
            try bridge.setRange(VolumeRange(minimum:lo,maximum:hi))
            let applied=bridge.range
            floor.stringValue=String(format:"%.1f",applied.minimum);ceiling.stringValue=String(format:"%.1f",applied.maximum)
            rangeFeedback.isHidden=false
            rangeFeedback.stringValue=L("已套用至 \(bridge.channelName)：\(applied.minimum) ～ \(applied.maximum) dB", "Applied to \(bridge.channelName): \(applied.minimum) to \(applied.maximum) dB")
        }
    }
    @objc func preferenceChanged(_ sender:NSSwitch) {
        if sender===launch { attempt { if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } }
        else if sender===restore { settings.autoRestore=sender.state == .on }
        else if sender===showDB { settings.showDB=sender.state == .on }
        else if sender===hideDock { settings.hideDock=sender.state == .on;applyDockPreference();show() }
        else if sender===openOnLaunch { settings.showWindowOnLaunch=sender.state == .on }
        refresh(force:true)
    }
    @objc func resync() { attempt { try bridge.requestSettings() } }
    @objc func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc func rebind() { bridge.rebindDevice();refresh(force:true) }
    func applyDockPreference() { NSApp.setActivationPolicy(settings.hideDock ? .accessory : .regular) }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool { show();return false }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        guard editor?.dirty == true else { return .terminateNow }
        show();let alert=NSAlert();alert.messageText=L("EQ 有尚未套用的編輯", "You have unapplied EQ edits");alert.informativeText=L("結束會捨棄草稿，DAC 目前設定不變。", "Quitting discards the draft. Current DAC settings will stay unchanged.");alert.addButton(withTitle:L("繼續編輯", "Keep editing"));alert.addButton(withTitle:L("捨棄並結束", "Discard and quit"))
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
    @objc func show() { if window.isMiniaturized { window.deminiaturize(nil) };window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true) }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }
    func applicationWillTerminate(_ notification:Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        bridge?.shutdown();let nc=NSWorkspace.shared.notificationCenter;for o in sleepObservers { nc.removeObserver(o) }
    }
}
@main struct Application {
    static func main()throws {
        if CommandLine.arguments.contains("--probe") {
            let midi=try RMEConnection();Audio.devices().forEach { print("AUDIO \($0.id) \($0.name) UID=\($0.uid)") }
            midi.onMessage = { msg in for p in RMEProtocol.parameters(msg) { print(p) } }
            try midi.connect();RunLoop.main.run(until:Date().addingTimeInterval(3));return
        }
        if let existing=NSRunningApplication.runningApplications(withBundleIdentifier:"local.ADI2Native.App").first(where:{$0.processIdentifier != ProcessInfo.processInfo.processIdentifier}), let url=existing.bundleURL {
            NSWorkspace.shared.openApplication(at:url,configuration:NSWorkspace.OpenConfiguration(),completionHandler:nil)
            return
        }
        let app=NSApplication.shared, delegate=AppDelegate();app.delegate=delegate;app.setActivationPolicy(delegate.settings.hideDock ? .accessory : .regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
