import AppKit

/// The top of the menu bar menu: everything for everyday listening in one glance,
/// laid out like the Sound module in Control Center.
final class MenuPanel:NSView {
    let title=NSTextField(labelWithString:"ADI-2 DAC")
    let nativeLabel=NSTextField(labelWithString:"")
    let native=NSSwitch()
    let statusText=NSTextField(labelWithString:"")
    lazy var status=StatusPill(label:statusText)
    let reading=NSTextField(labelWithString:"—")
    let unit=NSTextField(labelWithString:"dB")
    let mute=NSButton()
    let slider=TrackingSlider(value:0,minValue:-114.5,maxValue:0,target:nil,action:nil)
    let outputs=NSSegmentedControl()
    let hint=NSTextField(labelWithString:"")
    static let width:CGFloat=300

    init() {
        super.init(frame:NSRect(x:0,y:0,width:Self.width,height:10))
        title.font = .systemFont(ofSize:13,weight:.semibold)
        nativeLabel.font = .systemFont(ofSize:11);nativeLabel.textColor = .secondaryLabelColor
        native.controlSize = .mini
        reading.font=Theme.rounded(30,.semibold);reading.textColor = .labelColor
        unit.font=Theme.rounded(13,.medium);unit.textColor = .secondaryLabelColor
        mute.bezelStyle = .circular;mute.isBordered=true;mute.setButtonType(.momentaryPushIn);mute.imagePosition = .imageOnly
        mute.widthAnchor.constraint(equalToConstant:30).isActive=true;mute.heightAnchor.constraint(equalToConstant:30).isActive=true
        slider.isContinuous=true;slider.controlSize = .regular
        outputs.segmentCount=3;outputs.trackingMode = .selectOne;outputs.controlSize = .regular
        for (i,name) in ["Line Out","Phones","IEM"].enumerated() { outputs.setLabel(name,forSegment:i);outputs.setWidth((Self.width-32-6)/3,forSegment:i) }
        hint.font = .systemFont(ofSize:11);hint.textColor = .secondaryLabelColor;hint.lineBreakMode = .byTruncatingTail

        func line(_ views:[NSView],spacing:CGFloat=8)->NSStackView {
            let s=NSStackView(views:views);s.orientation = .horizontal;s.spacing=spacing;s.alignment = .centerY;return s
        }
        let spacer=NSView();spacer.setContentHuggingPriority(.init(1),for:.horizontal)
        let header=line([title,spacer,nativeLabel,native],spacing:6)
        let spacer2=NSView();spacer2.setContentHuggingPriority(.init(1),for:.horizontal)
        let value=line([reading,unit],spacing:4);value.alignment = .firstBaseline
        let levelRow=line([value,spacer2,mute])
        let stack=NSStackView(views:[header,status,levelRow,slider,outputs,hint])
        stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=8
        stack.setCustomSpacing(12,after:status);stack.setCustomSpacing(4,after:levelRow);stack.setCustomSpacing(12,after:slider)
        stack.translatesAutoresizingMaskIntoConstraints=false;addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo:leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-16),
            stack.topAnchor.constraint(equalTo:topAnchor,constant:10),stack.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-8),
            widthAnchor.constraint(equalToConstant:Self.width)
        ])
        for v in [header,levelRow,slider,outputs,hint] { v.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true }
        status.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        status.widthAnchor.constraint(lessThanOrEqualTo:stack.widthAnchor).isActive=true
        setFrameSize(fittingSize)
    }
    required init?(coder:NSCoder) { nil }
    // Controls inside a menu must not let a drag move anything but themselves.
    override var mouseDownCanMoveWindow: Bool { false }
}

extension AppDelegate {
    func buildMenu() {
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusKnob=StatusKnob(item.button)
        item.button?.image=StatusKnob.image(position:0.5,amplitude:0)
        item.button?.imagePosition = .imageLeading;item.button?.font = .monospacedDigitSystemFont(ofSize:12,weight:.regular);item.button?.setAccessibilityLabel(L("ADI2 Native 音量控制", "ADI2 Native volume control"))
        let menu=NSMenu();menu.autoenablesItems=false;menu.delegate=self;item.menu=menu

        let panel=MenuPanel();menuPanel=panel;slider=panel.slider
        panel.slider.target=self;panel.slider.action=#selector(slide)
        panel.mute.target=self;panel.mute.action=#selector(toggleMute)
        panel.native.target=self;panel.native.action=#selector(menuNativeChanged)
        panel.outputs.target=self;panel.outputs.action=#selector(menuOutputChanged)
        let top=NSMenuItem();top.view=panel;menu.addItem(top)

        menu.addItem(.separator())
        menu.addItem(sectionHeader(L("等化器", "Equalizer")))
        eqItem=menuItem(L("啟用 EQ", "EQ on"),#selector(toggleEQ),menu)
        btItem=menuItem("Bass／Treble",#selector(toggleBT),menu)
        presetParent=menuItem(L("DAC 預設", "DAC presets"),nil,menu);let presets=NSMenu();presets.autoenablesItems=false;presetParent.submenu=presets
        for n in 1...20 { presetItems.append(menuItem(L("\(n). 讀取中…", "\(n). Loading…"),#selector(menuPreset),presets,tag:n)) }
        _ = menuItem(L("編輯 EQ…", "Edit EQ…"),#selector(showEQ),menu)

        menu.addItem(.separator())
        _ = menuItem(L("開啟 ADI2 Native", "Open ADI2 Native"),#selector(show),menu)
        let prefs=menuItem(L("設定…", "Settings…"),#selector(showSettings),menu);prefs.keyEquivalent=","
        let quitEntry=menuItem(L("結束並還原輸出", "Quit and restore output"),#selector(quit),menu);quitEntry.keyEquivalent="q"

        let main=NSMenu(), mainItem=NSMenuItem();main.addItem(mainItem);let appMenu=NSMenu();mainItem.submenu=appMenu
        _ = menuItem(L("顯示控制面板", "Open control panel"),#selector(show),appMenu)
        let preferences=menuItem(L("設定…", "Settings…"),#selector(showSettings),appMenu);preferences.keyEquivalent=","
        appMenu.addItem(.separator())
        let quitMain=menuItem(L("結束 ADI2 Native", "Quit ADI2 Native"),#selector(quit),appMenu);quitMain.keyEquivalent="q";NSApp.mainMenu=main
    }
    func sectionHeader(_ title:String)->NSMenuItem {
        if #available(macOS 14,*) { return .sectionHeader(title:title) }
        let i=NSMenuItem(title:title,action:nil,keyEquivalent:"");i.isEnabled=false;return i
    }
    func refreshMenu(value:String,shown:Double) {
        guard let p=menuPanel else { return }
        let connected=bridge.connected, ready=bridge.synchronized
        p.nativeLabel.stringValue=L("原生音量", "Native volume")
        p.native.state=bridge.wanted ? .on : .off;p.native.isEnabled=toggle.isEnabled
        p.native.setAccessibilityLabel(L("原生音量控制", "Native volume control"))
        p.statusText.stringValue=bridge.controlSummary;p.status.tone=statusPill.tone
        p.reading.stringValue=connected ? Theme.formatDB(bridge.db ?? 0) : "—"
        p.reading.textColor=bridge.hardwareMuted ? .secondaryLabelColor : .labelColor
        p.slider.minValue=bridge.range.minimum;p.slider.maxValue=bridge.range.maximum
        if !p.slider.tracking { p.slider.doubleValue=shown };p.slider.isEnabled=ready
        p.mute.image=Theme.symbol(bridge.hardwareMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",13)
        p.mute.contentTintColor=bridge.hardwareMuted ? .systemRed : nil;p.mute.isEnabled=ready
        p.mute.toolTip=bridge.hardwareMuted ? L("取消靜音", "Unmute") : L("靜音", "Mute")
        p.mute.setAccessibilityLabel(p.mute.toolTip)
        p.outputs.selectedSegment=[3,6,9].firstIndex(of:bridge.channel) ?? 0;p.outputs.isEnabled=connected
        p.outputs.setAccessibilityLabel(L("控制目標", "Control target"))
        let range=bridge.range
        p.hint.stringValue=bridge.hardwareMuted ? L("已靜音 · 點喇叭取消", "Muted · Click the speaker to unmute")
            : jackNote(bridge.channel).map { "\(bridge.channelName) · \($0)" }
            ?? L("滑桿範圍 \(Theme.formatDB(range.minimum)) ～ \(Theme.formatDB(range.maximum)) dB", "Slider range \(Theme.formatDB(range.minimum)) to \(Theme.formatDB(range.maximum)) dB")
        let eqReady=connected && bridge.eqState != nil && !editor.dirty
        eqItem.state=bridge.eqEnabled ? .on : .off;eqItem.isEnabled=eqReady
        btItem.state=bridge.btEnabled ? .on : .off;btItem.isEnabled=eqReady
        let current=bridge.selectedPreset.map { $0-1 }.flatMap { (1...20).contains($0) ? $0 : nil }
        let currentName=current.flatMap { bridge.presetNames[$0] }.map { $0.isEmpty ? L("未命名", "Unnamed") : $0 }
        presetParent.title=currentName.map { L("DAC 預設：\($0)", "DAC preset: \($0)") } ?? L("DAC 預設", "DAC presets")
        presetParent.isEnabled=eqReady
    }
    @objc func menuNativeChanged() { toggleBridge() }
    @objc func menuOutputChanged() {
        let channel=[3,6,9][max(0,menuPanel.outputs.selectedSegment)]
        guard !editor.dirty else {
            menuPanel.outputs.selectedSegment=[3,6,9].firstIndex(of:bridge.channel) ?? 0
            item.menu?.cancelTracking();show();report(BridgeError.message(L("請先套用或重新讀取 EQ，再切換控制目標", "Apply or reload your EQ edits before changing the control target.")));return
        }
        bridge.select(channel:channel);refresh(force:true)
    }
    @objc func showEQ() { navigation.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false);displayPage(1);show() }
}
