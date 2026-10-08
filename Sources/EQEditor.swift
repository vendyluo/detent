import AppKit

final class EQCurveView:NSView {
    var state:EQState? { didSet { needsDisplay=true } }
    var reference:EQState? { didSet { needsDisplay=true } }
    var rightChannel=false { didSet { needsDisplay=true } }
    var editable=false
    /// Called while dragging a handle: band index (0–4 EQ, 5 Bass, 6 Treble), frequency, gain.
    var onDrag:((Int,Double,Double)->Void)?
    private var dragging:Int?
    private var hovered:Int? { didSet { if hovered != oldValue { needsDisplay=true } } }
    override var intrinsicContentSize:NSSize { NSSize(width:NSView.noIntrinsicMetric,height:220) }
    private var plot:NSRect { bounds.inset(left:40,right:18,top:18,bottom:28) }
    private func x(_ hz:Double)->CGFloat { plot.minX+CGFloat(log10(max(20,hz)/20)/3)*plot.width }
    private func y(_ gain:Double)->CGFloat { plot.midY+CGFloat(max(-15,min(15,gain))/30)*plot.height }
    private func hz(_ x:CGFloat)->Double { 20*pow(1000,Double((x-plot.minX)/plot.width)) }
    private func gain(_ y:CGFloat)->Double { Double((y-plot.midY)/plot.height)*30 }
    private func curve(_ s:EQState)->NSBezierPath {
        let path=NSBezierPath()
        for i in 0...360 {
            let f=20*pow(1000,Double(i)/360), p=NSPoint(x:x(f),y:y(s.response(frequency:f,rightChannel:rightChannel)))
            if i==0 { path.move(to:p) } else { path.line(to:p) }
        }
        return path
    }
    /// Handles sit on the combined curve so they read as "grab the curve here".
    private func handles()->[(index:Int,band:EQBand,point:NSPoint)] {
        guard let s=state else { return [] }
        var result:[(Int,EQBand)]=[]
        if s.enabled { result += (rightChannel && s.dual ? s.right : s.left).enumerated().map { ($0.offset,$0.element) } }
        if s.btEnabled { result += [(5,s.bass),(6,s.treble)] }
        return result.map { i,b in (i,b,NSPoint(x:x(b.frequency),y:y(s.response(frequency:b.frequency,rightChannel:rightChannel)))) }
    }
    override func draw(_ dirtyRect:NSRect) {
        // The host surface supplies the edge; this only tints the plot area for contrast.
        Theme.display.setFill();NSBezierPath(roundedRect:bounds,xRadius:20,yRadius:20).fill()
        let attrs:[NSAttributedString.Key:Any]=[.font:Theme.rounded(10,.medium),.foregroundColor:NSColor.tertiaryLabelColor]
        for g in [-12,-6,0,6,12] {
            let p=NSBezierPath();p.move(to:NSPoint(x:plot.minX,y:y(Double(g))));p.line(to:NSPoint(x:plot.maxX,y:y(Double(g))))
            (g==0 ? NSColor.separatorColor : Theme.track).setStroke();p.lineWidth=g==0 ? 1 : 0.6;p.stroke()
            let label=NSAttributedString(string:g>0 ? "+\(g)" : g<0 ? "−\(-g)" : "0",attributes:attrs)
            label.draw(at:NSPoint(x:plot.minX-8-label.size().width,y:y(Double(g))-label.size().height/2))
        }
        for f in [20.0,50,100,200,500,1000,2000,5000,10000,20000] {
            let p=NSBezierPath();p.move(to:NSPoint(x:x(f),y:plot.minY));p.line(to:NSPoint(x:x(f),y:plot.maxY));Theme.track.setStroke();p.lineWidth=0.6;p.stroke()
            let label=NSAttributedString(string:f>=1000 ? "\(Int(f/1000))k" : "\(Int(f))",attributes:attrs)
            label.draw(at:NSPoint(x:min(plot.maxX-label.size().width,max(plot.minX,x(f)-label.size().width/2)),y:plot.minY-18))
        }
        if let reference {
            let original=curve(reference);original.lineWidth=1.3;original.setLineDash([4,3],count:2,phase:0)
            NSColor.secondaryLabelColor.setStroke();original.stroke()
        }
        guard let state else { return }
        let line=curve(state), area=line.copy() as! NSBezierPath
        area.line(to:NSPoint(x:plot.maxX,y:y(0)));area.line(to:NSPoint(x:plot.minX,y:y(0)));area.close()
        NSGraphicsContext.saveGraphicsState();NSBezierPath(rect:plot).addClip()
        NSGradient(starting:NSColor.controlAccentColor.withAlphaComponent(0.28),ending:NSColor.controlAccentColor.withAlphaComponent(0.04))?.draw(in:area,angle:-90)
        line.lineWidth=2.4;line.lineJoinStyle = .round;NSColor.controlAccentColor.setStroke();line.stroke()
        NSGraphicsContext.restoreGraphicsState()
        for h in handles() {
            let active=h.index==dragging || h.index==hovered, r:CGFloat=active ? 9 : 7.5
            let dot=NSBezierPath(ovalIn:NSRect(x:h.point.x-r,y:h.point.y-r,width:r*2,height:r*2))
            Theme.bands[h.index].setFill();dot.fill();Theme.display.setStroke();dot.lineWidth=2;dot.stroke()
            let tag=NSAttributedString(string:h.index<5 ? "\(h.index+1)" : h.index==5 ? "B" : "T",attributes:[.font:Theme.rounded(9,.bold),.foregroundColor:NSColor.white])
            tag.draw(at:NSPoint(x:h.point.x-tag.size().width/2,y:h.point.y-tag.size().height/2))
            if active {
                let readout=NSAttributedString(string:"\(h.band.frequency>=1000 ? String(format:"%.2gk",h.band.frequency/1000) : String(format:"%.0f",h.band.frequency)) Hz  \(Theme.formatDB(h.band.gain)) dB",attributes:[.font:Theme.rounded(11,.semibold),.foregroundColor:NSColor.labelColor])
                let box=NSRect(x:min(plot.maxX-readout.size().width-12,max(plot.minX,h.point.x-readout.size().width/2-6)),y:min(plot.maxY-20,h.point.y+14),width:readout.size().width+12,height:20)
                Theme.card.setFill();NSBezierPath(roundedRect:box,xRadius:6,yRadius:6).fill()
                readout.draw(at:NSPoint(x:box.minX+6,y:box.minY+2))
            }
        }
    }
    private func hit(_ event:NSEvent)->Int? {
        let p=convert(event.locationInWindow,from:nil)
        return handles().min { hypot($0.point.x-p.x,$0.point.y-p.y)<hypot($1.point.x-p.x,$1.point.y-p.y) }.flatMap { hypot($0.point.x-p.x,$0.point.y-p.y)<14 ? $0.index : nil }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect:bounds,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow],owner:self))
    }
    override func mouseMoved(with event:NSEvent) { hovered=editable ? hit(event) : nil }
    override func mouseExited(with event:NSEvent) { hovered=nil }
    override func resetCursorRects() { if editable { for h in handles() { addCursorRect(NSRect(x:h.point.x-9,y:h.point.y-9,width:18,height:18),cursor:.openHand) } } }
    // The window moves by its background; a drag here edits instead of moving the window.
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event:NSEvent) { dragging=editable ? hit(event) : nil;if dragging != nil { NSCursor.closedHand.push() } }
    override func mouseDragged(with event:NSEvent) {
        guard let index=dragging else { return }
        let p=convert(event.locationInWindow,from:nil)
        // Ranges follow the DAC protocol so a drag can never produce a value Apply would reject.
        let limits:(Double,Double)=index==5 ? (20,150) : index==6 ? (3000,10000) : index>=3 ? (200,20000) : (20,20000)
        var f=min(limits.1,max(limits.0,hz(p.x)))
        f=f>=1000 ? (f/10).rounded()*10 : f.rounded()
        let g=min(12,max(-12,(gain(p.y)*2).rounded()/2))
        onDrag?(index,f,g)
    }
    override func mouseUp(with event:NSEvent) { if dragging != nil { NSCursor.pop() };dragging=nil;window?.invalidateCursorRects(for:self);needsDisplay=true }
}
private extension NSRect {
    func inset(left:CGFloat,right:CGFloat,top:CGFloat,bottom:CGFloat)->NSRect { NSRect(x:minX+left,y:minY+bottom,width:width-left-right,height:height-top-bottom) }
}
final class EQEditor:NSObject,NSTextFieldDelegate {
    let view=NSStackView()
    let bridge:Bridge
    let report:(Error)->Void
    var draft:EQState?, baseline:EQState?
    var output:Int=0, dirty=false, pendingApply=false
    var shownRight=false
    var expected:[RMEParameter]=[]
    var validationMessage:String?
    var applyFailure:String?
    let discard=NSButton(title:L("撤銷草稿", "Discard edits"),target:nil,action:nil)
    let compare=NSButton(checkboxWithTitle:L("對照原始曲線", "Compare original curve"),target:nil,action:nil)
    let curve=EQCurveView(), message=NSTextField(wrappingLabelWithString:L("等待 EQ 設定…", "Waiting for EQ settings…"))
    let enabled=NSButton(checkboxWithTitle:"EQ",target:nil,action:nil)
    let dual=NSButton(checkboxWithTitle:L("左右獨立 EQ", "Separate left / right EQ"),target:nil,action:nil)
    let bt=NSButton(checkboxWithTitle:"Bass／Treble",target:nil,action:nil)
    let side=NSPopUpButton(), preset=NSPopUpButton(), template=NSPopUpButton()
    var types:[NSPopUpButton]=[], frequencies:[NSTextField]=[], gains:[NSTextField]=[], qs:[NSTextField]=[]
    var btFields:[NSTextField]=[]
    let apply=NSButton(title:L("套用到 DAC", "Apply to DAC"),target:nil,action:nil)
    let reload=NSButton(title:L("重新讀取", "Reload"),target:nil,action:nil)
    let savePreset=NSButton(title:L("存成 DAC 預設…", "Save as DAC preset…"),target:nil,action:nil)
    let presetStatus=NSTextField(labelWithString:"")
    var lastTemplate:Int?
    init(bridge:Bridge,report:@escaping(Error)->Void) {
        self.bridge=bridge;self.report=report;super.init()
        view.orientation = .vertical;view.alignment = .leading;view.spacing=12
        let header=NSStackView(); header.spacing=14
        for button in [enabled,dual,bt] { button.target=self;button.action=#selector(changed);header.addArrangedSubview(button) }
        side.addItems(withTitles:[L("左／雙聲道", "Left / stereo"),L("右聲道", "Right")]);side.target=self;side.action=#selector(sideChanged);header.addArrangedSubview(side)
        preset.addItem(withTitle:L("載入 DAC EQ 預設…", "Load DAC EQ preset…"))
        for n in 1...20 { preset.addItem(withTitle:L("\(n). 讀取中…", "\(n). Loading…"));preset.lastItem?.tag=n }
        preset.target=self;preset.action=#selector(presetChanged);header.addArrangedSubview(preset)
        fillTemplates()
        template.target=self;template.action=#selector(templateChanged);header.addArrangedSubview(template)
        view.addArrangedSubview(header)
        let curveHost=Theme.surface(curve,radius:20,padding:0)
        view.addArrangedSubview(curveHost);curveHost.widthAnchor.constraint(equalTo:view.widthAnchor).isActive=true;curveHost.widthAnchor.constraint(greaterThanOrEqualToConstant:600).isActive=true;curve.heightAnchor.constraint(equalToConstant:230).isActive=true
        curve.onDrag={ [weak self] in self?.dragged(band:$0,frequency:$1,gain:$2) }
        let caption=NSTextField(labelWithString:L("頻率響應示意（RBJ 模型）；實際聲音由 DAC 處理，曲線不含 Loudness 等其他 DSP。可直接拖曳圓點調整頻率與增益。", "Approximate response (RBJ model). DSP runs on the DAC; Loudness and other processing are not shown. Drag the dots to adjust frequency and gain."))
        caption.font = .systemFont(ofSize:11);caption.textColor = .secondaryLabelColor;view.addArrangedSubview(caption)
        var rows:[[NSView]]=[[NSTextField(labelWithString:L("頻段", "Band")),NSTextField(labelWithString:L("類型", "Type")),NSTextField(labelWithString:L("頻率 Hz", "Frequency Hz")),NSTextField(labelWithString:L("增益 dB", "Gain dB")),NSTextField(labelWithString:"Q")]]
        for i in 0..<5 {
            let type=NSPopUpButton()
            let kinds:[FilterKind]=i==0 ? [.peak,.lowShelf,.highPass,.lowPass] : (i==4 ? [.peak,.highShelf,.lowPass] : [.peak])
            type.addItems(withTitles:kinds.map(\.rawValue));type.target=self;type.action=#selector(changed)
            type.widthAnchor.constraint(equalToConstant:145).isActive=true
            let f=field(),g=field(),q=field();types.append(type);frequencies.append(f);gains.append(g);qs.append(q)
            rows.append([bandLabel("Band \(i+1)",i),type,f,g,q])
        }
        for name in ["Bass","Treble"] {
            let f=field(),g=field(),q=field();btFields += [f,g,q]
            rows.append([bandLabel(name,name == "Bass" ? 5 : 6),NSTextField(labelWithString:name == "Bass" ? "Low Shelf" : "High Shelf"),f,g,q])
        }
        for header in rows[0] { (header as? NSTextField)?.font = .systemFont(ofSize:11,weight:.semibold);(header as? NSTextField)?.textColor = .secondaryLabelColor }
        let grid=NSGridView(views:rows);grid.rowSpacing=8;grid.columnSpacing=16;grid.rowAlignment = .firstBaseline
        for (index,width) in [70.0,150.0,140.0,140.0,120.0].enumerated() { grid.column(at:index).width=CGFloat(width);grid.column(at:index).xPlacement = .leading }
        let gridRow=NSStackView(views:[grid,NSView()]);gridRow.alignment = .top
        let gridHost=Theme.surface(gridRow,radius:20,padding:18)
        view.addArrangedSubview(gridHost);gridHost.widthAnchor.constraint(equalTo:view.widthAnchor).isActive=true
        let actions=NSStackView();actions.spacing=12
        for b in [apply,discard,reload,savePreset] { Theme.style(b) }
        savePreset.target=self;savePreset.action=#selector(savePresetClicked)
        presetStatus.font = .systemFont(ofSize:12);presetStatus.textColor = .secondaryLabelColor
        apply.target=self;apply.action=#selector(applyChanges);reload.target=self;reload.action=#selector(reloadHardware)
        discard.target=self;discard.action=#selector(discardDraft);compare.target=self;compare.action=#selector(compareChanged)
        actions.addArrangedSubview(apply);actions.addArrangedSubview(discard);actions.addArrangedSubview(reload);actions.addArrangedSubview(compare);actions.addArrangedSubview(savePreset);actions.addArrangedSubview(presetStatus);view.addArrangedSubview(actions)
        message.font = .systemFont(ofSize:12);message.textColor = .secondaryLabelColor
        message.preferredMaxLayoutWidth=730;view.addArrangedSubview(message)
        refresh()
    }
    func bandLabel(_ title:String,_ color:Int)->NSTextField {
        let s=NSMutableAttributedString(string:"●  ",attributes:[.foregroundColor:Theme.bands[color],.font:NSFont.systemFont(ofSize:11)])
        s.append(NSAttributedString(string:title,attributes:[.foregroundColor:NSColor.labelColor,.font:NSFont.systemFont(ofSize:13,weight:.medium)]))
        let label=NSTextField(labelWithAttributedString:s);return label
    }
    func dragged(band:Int,frequency:Double,gain:Double) {
        let (f,g)=band<5 ? (frequencies[band],gains[band]) : (btFields[band==5 ? 0 : 3],btFields[band==5 ? 1 : 4])
        f.stringValue=String(format:"%.0f",frequency);g.stringValue=String(format:"%.1f",gain);changed()
    }
    func field()->NSTextField {
        let f=NSTextField(string:"");f.alignment = .right;f.font=Theme.rounded(13);f.widthAnchor.constraint(equalToConstant:95).isActive=true
        f.delegate=self;f.target=self;f.action=#selector(changed);return f
    }
    func number(_ f:NSTextField)throws->Double {
        guard let d=Double(f.stringValue.trimmingCharacters(in:.whitespaces)),d.isFinite else { throw BridgeError.message(L("請輸入有效數字", "Enter a valid number")) };return d
    }
    func capture()throws->EQState {
        guard var state=draft else { throw BridgeError.message(L("尚未讀取 EQ", "EQ has not been loaded")) }
        var bands=shownRight ? state.right : state.left
        for i in 0..<5 {
            bands[i]=EQBand(kind:FilterKind(rawValue:types[i].titleOfSelectedItem ?? "Peak") ?? .peak,frequency:try number(frequencies[i]),gain:try number(gains[i]),q:try number(qs[i]))
        }
        if shownRight { state.right=bands } else { state.left=bands }
        state.enabled=enabled.state == .on;state.dual=dual.state == .on;state.btEnabled=bt.state == .on
        state.bass=EQBand(kind:.lowShelf,frequency:try number(btFields[0]),gain:try number(btFields[1]),q:try number(btFields[2]))
        state.treble=EQBand(kind:.highShelf,frequency:try number(btFields[3]),gain:try number(btFields[4]),q:try number(btFields[5]))
        _ = try state.parameters(output:bridge.channel)
        return state
    }
    func paintFields() {
        guard let s=draft else { return }
        enabled.state=s.enabled ? .on : .off;dual.state=s.dual ? .on : .off;bt.state=s.btEnabled ? .on : .off
        side.isEnabled=s.dual;side.selectItem(at:shownRight ? 1 : 0)
        let bands=shownRight ? s.right : s.left
        for i in 0..<5 { types[i].selectItem(withTitle:bands[i].kind.rawValue);frequencies[i].stringValue=String(format:"%.0f",bands[i].frequency);gains[i].stringValue=String(format:"%.1f",bands[i].gain);qs[i].stringValue=String(format:"%.1f",bands[i].q) }
        for (offset,b) in [(0,s.bass),(3,s.treble)] { btFields[offset].stringValue=String(format:"%.0f",b.frequency);btFields[offset+1].stringValue=String(format:"%.1f",b.gain);btFields[offset+2].stringValue=String(format:"%.1f",b.q) }
        curve.state=s;curve.rightChannel=shownRight
    }
    func refresh() {
        let state=bridge.eqState
        if output != bridge.channel { output=bridge.channel;dirty=false;baseline=nil;draft=nil;shownRight=false }
        if pendingApply && !bridge.hasPending {
            pendingApply=false
            if !expected.isEmpty && expected.allSatisfy({ bridge.values[$0.channel]?[$0.index] == $0.value }) {
                dirty=false;baseline=nil;applyFailure=nil
            } else { dirty=true;applyFailure=L("DAC 尚未確認全部設定；草稿已保留。請重新連線或讀取後再試。", "DAC has not confirmed all settings. Your draft is kept. Reconnect or reload before trying again.") }
            expected=[]
        }
        if !dirty && state != baseline { baseline=state;draft=state;paintFields() }
        let editable=bridge.connected && state != nil && !pendingApply
        for c in [enabled,dual,bt] { c.isEnabled=editable }
        for f in frequencies+gains+qs+btFields { f.isEnabled=editable }
        for t in types { t.isEnabled=editable }
        side.isEnabled=editable && (draft?.dual ?? false)
        apply.isEnabled=editable && dirty && validationMessage == nil && state==baseline
        Theme.setProminent(apply,apply.isEnabled)
        curve.editable=editable
        discard.isEnabled=dirty && !pendingApply
        compare.isEnabled=baseline != nil
        curve.reference=compare.state == .on ? baseline : nil
        reload.isEnabled=bridge.connected
        preset.isEnabled=bridge.connected && !dirty && !pendingApply
        template.isEnabled=editable && draft != nil
        var writing=false
        switch bridge.presetWrite {
        case .verifying(let n)?: writing=true;presetStatus.stringValue=L("正在存入第 \(n) 組並讀回確認…", "Saving preset \(n) and reading it back…");presetStatus.textColor = .secondaryLabelColor
        case .saved(let n)?: presetStatus.stringValue=L("已存入第 \(n) 組並確認", "Saved to preset \(n) and verified");presetStatus.textColor = .systemGreen
        case .failed(let n,let why)?: presetStatus.stringValue=L("第 \(n) 組儲存失敗：\(why)", "Preset \(n) failed: \(why)");presetStatus.textColor = .systemOrange
        case nil: presetStatus.stringValue=""
        }
        savePreset.isEnabled=editable && draft != nil && validationMessage == nil && !writing && bridge.loadedPresetNames && bridge.presetNames.count == 20
        for n in 1...20 {
            let name=bridge.presetNames[n] ?? L("讀取中…", "Loading…")
            preset.item(at:n)?.title="\(n). \(name.isEmpty ? L("未命名", "Unnamed") : name)\(bridge.emptyPresets.contains(n) ? L("（空白）", " (empty)") : "")"
            preset.item(at:n)?.isEnabled=bridge.presetNames[n] != nil && !bridge.emptyPresets.contains(n)
        }
        if let validationMessage { message.stringValue=validationMessage }
        else if let applyFailure { message.stringValue=applyFailure }
        else if pendingApply { message.stringValue=L("等待 DAC 確認 EQ 設定…", "Waiting for DAC to confirm EQ…") }
        else if dirty && state != baseline { message.stringValue=L("硬體 EQ 已在別處變更；請先重新讀取，再套用編輯。", "EQ changed on the device. Reload before applying your edits.") }
        else if dirty { message.stringValue=L("尚未套用。增益步階 0.5 dB、Q 步階 0.1；高頻依硬體協定以 10 Hz 編碼。", "Not applied · Gain: 0.5 dB steps; Q: 0.1 steps; high frequencies: 10 Hz steps.") }
        else { message.stringValue=state == nil ? L("等待完整 EQ 資料…", "Waiting for complete EQ data…") : L("已同步 \(bridge.channelName)。套用只變更目前 EQ，不覆寫 DAC 儲存的預設。", "Synced with \(bridge.channelName). Apply changes the current EQ, not stored presets.") }
    }
    func controlTextDidChange(_ notification:Notification) { changed() }
    @objc func changed() {
        guard draft != nil else { return }
        dirty=true;applyFailure=nil
        do { let state=try capture();draft=state;if !state.dual && shownRight { shownRight=false;paintFields() };curve.state=state;side.isEnabled=state.dual;validationMessage=nil }
        catch { validationMessage=L("輸入尚未完成或超出範圍：\(error)", "Incomplete or out-of-range input: \(error)") }
        refresh()
    }
    @objc func sideChanged() {
        do { draft=try capture();shownRight=side.indexOfSelectedItem==1;paintFields() }
        catch { side.selectItem(at:shownRight ? 1 : 0);report(error) }
    }
    @objc func compareChanged() { curve.reference=compare.state == .on ? baseline : nil }
    @objc func discardDraft() {
        dirty=false;validationMessage=nil;applyFailure=nil;draft=bridge.eqState;baseline=bridge.eqState;paintFields();refresh()
    }
    @objc func reloadHardware() {
        validationMessage=nil;applyFailure=nil;expected=[]
        dirty=false;pendingApply=false;baseline=nil;draft=bridge.eqState;refresh()
        do { try bridge.requestSettings() } catch { report(error) }
    }
    @objc func applyChanges() {
        do {
            guard bridge.eqState==baseline else { throw BridgeError.message(L("硬體 EQ 已變動，請先重新讀取", "Device EQ changed. Reload first.")) }
            let state=try capture();expected=try state.parameters(output:bridge.channel).map(RMEProtocol.normalized);applyFailure=nil;pendingApply=true;try bridge.applyEQ(state);refresh()
        } catch { pendingApply=false;expected=[];applyFailure=String(describing:error);refresh();report(error) }
    }
    /// Rebuilt on language change; template tags overlap the preset tags the generic menu localizer skips.
    func fillTemplates() {
        template.removeAllItems();template.addItem(withTitle:L("套用範本…", "Template…"))
        for (i,t) in EQTemplate.all.enumerated() { template.addItem(withTitle:t.name);template.lastItem?.tag=i+1;template.lastItem?.toolTip=t.note }
    }
    /// Loads a template into the draft only; nothing reaches the DAC until Apply.
    @objc func templateChanged() {
        let n=template.selectedTag();template.selectItem(at:0)
        guard n>0, let current=draft else { return }
        let t=EQTemplate.all[n-1]
        lastTemplate=n-1
        draft=t.applied(to:current);dirty=true;applyFailure=nil;validationMessage=nil;paintFields();changed()
    }
    /// Writes the draft (applied or not) into a DAC preset slot. The live EQ is not changed.
    @objc func savePresetClicked() {
        guard let window=view.window else { return }
        let state:EQState
        do { state=try capture() } catch { report(error);return }
        let slots=NSPopUpButton(),name=NSTextField(string:lastTemplate.map { EQTemplate.presetNames[$0] } ?? "My EQ")
        for n in 1...20 {
            let empty=bridge.emptyPresets.contains(n),label=bridge.presetNames[n] ?? ""
            slots.addItem(withTitle:"\(n). \(empty ? L("（空白）", "(empty)") : label)");slots.lastItem?.tag=n
        }
        if let free=(1...20).first(where:{ bridge.emptyPresets.contains($0) }) { slots.selectItem(withTag:free) }
        name.placeholderString=L("最多 \(RMEProtocol.presetNameLength) 個英數字元", "Up to \(RMEProtocol.presetNameLength) ASCII characters")
        let form=NSGridView(views:[[NSTextField(labelWithString:L("存入", "Slot")),slots],[NSTextField(labelWithString:L("名稱", "Name")),name]])
        form.rowSpacing=8;form.columnSpacing=10;name.widthAnchor.constraint(equalToConstant:220).isActive=true
        form.frame=NSRect(x:0,y:0,width:290,height:60)
        let alert=NSAlert();alert.messageText=L("存成 DAC 預設", "Save as DAC preset")
        alert.informativeText=L("把目前編輯中的 EQ（含未套用的草稿）存進 DAC 的預設，之後可以直接在 DAC 上切換。目前的聲音不會改變。", "Stores the EQ being edited, including unapplied changes, in a DAC preset you can recall on the device. What you hear now does not change.")
        alert.accessoryView=form;alert.addButton(withTitle:L("儲存", "Save"));alert.addButton(withTitle:L("取消", "Cancel"))
        alert.window.initialFirstResponder=name
        alert.beginSheetModal(for:window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let n=slots.selectedTag(),title=name.stringValue.trimmingCharacters(in:.whitespaces)
            let save={ do { try self.bridge.savePreset(n,name:title,state:state);self.refresh() } catch { self.report(error) } }
            guard !self.bridge.emptyPresets.contains(n) else { save();return }
            let confirm=NSAlert();confirm.alertStyle = .warning
            confirm.messageText=L("覆蓋第 \(n) 組「\(self.bridge.presetNames[n] ?? "")」？", "Replace preset \(n), “\(self.bridge.presetNames[n] ?? "")”?")
            confirm.informativeText=L("這一組已經有內容，覆蓋後無法復原。", "This preset is not empty. Replacing it cannot be undone.")
            confirm.addButton(withTitle:L("覆蓋", "Replace")).hasDestructiveAction=true;confirm.addButton(withTitle:L("取消", "Cancel"))
            DispatchQueue.main.async { confirm.beginSheetModal(for:window) { if $0 == .alertFirstButtonReturn { save() } } }
        }
    }
    @objc func presetChanged() {
        let n=preset.selectedTag();preset.selectItem(at:0)
        guard n>0 else { return }
        do { try bridge.selectPreset(n) } catch { report(error) }
    }
}
