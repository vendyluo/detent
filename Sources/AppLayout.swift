import AppKit

final class FlippedDocumentView:NSView { override var isFlipped:Bool { true } }

final class NavigationRow:NSTableRowView {
 override var interiorBackgroundStyle:NSView.BackgroundStyle { .normal }
 override func drawSelection(in dirtyRect:NSRect) {
  Theme.dynamic(light:NSColor(white:0,alpha:0.07),dark:NSColor(white:1,alpha:0.09)).setFill()
  NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:2),xRadius:8,yRadius:8).fill()
 }
}

extension AppDelegate:NSTableViewDataSource,NSTableViewDelegate {
    func numberOfRows(in tableView:NSTableView)->Int { pageNames.count }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        let cell=NSTableCellView(), icon=NSImageView(), text=NSTextField(labelWithString:pageNames[row])
        icon.image=sidebarBadge(row);text.font = .systemFont(ofSize:13,weight:.medium);text.textColor = .labelColor
        for v in [icon,text] { v.translatesAutoresizingMaskIntoConstraints=false;cell.addSubview(v) }
        NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:10),icon.centerYAnchor.constraint(equalTo:cell.centerYAnchor),icon.widthAnchor.constraint(equalToConstant:26),icon.heightAnchor.constraint(equalToConstant:26),text.leadingAnchor.constraint(equalTo:icon.trailingAnchor,constant:10),text.centerYAnchor.constraint(equalTo:cell.centerYAnchor),text.trailingAnchor.constraint(lessThanOrEqualTo:cell.trailingAnchor,constant:-8)])
        cell.textField=text;cell.imageView=icon;return cell
    }
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int)->NSTableRowView? { NavigationRow() }
    func tableViewSelectionDidChange(_ notification:Notification) { displayPage(navigation.selectedRow) }
    func displayPage(_ index:Int) {
        guard pages.indices.contains(index) else { return }
        pageTitle.stringValue=pageNames[index]
        statusPill.isHidden=index==2;connectionDetail.isHidden=index==2
        pageHost.subviews.forEach { $0.removeFromSuperview() }
        let page=pages[index];page.translatesAutoresizingMaskIntoConstraints=false;pageHost.addSubview(page)
        NSLayoutConstraint.activate([page.leadingAnchor.constraint(equalTo:pageHost.leadingAnchor),page.trailingAnchor.constraint(equalTo:pageHost.trailingAnchor),page.topAnchor.constraint(equalTo:pageHost.topAnchor),page.bottomAnchor.constraint(equalTo:pageHost.bottomAnchor)])
    }
    @objc func showSettings() { navigation.selectRowIndexes(IndexSet(integer:2),byExtendingSelection:false);displayPage(2);show() }
    func stack(_ views:[NSView],spacing:CGFloat=12)->NSStackView {
        let s=NSStackView(views:views);s.orientation = .vertical;s.alignment = .leading;s.spacing=spacing;return s
    }
    func text(_ value:String,size:CGFloat=13,secondary:Bool=false)->NSTextField {
        let t=NSTextField(wrappingLabelWithString:value);t.font = .systemFont(ofSize:size);t.textColor=secondary ? .secondaryLabelColor : .labelColor;t.preferredMaxLayoutWidth=700;return t
    }
    func row(_ views:[NSView])->NSStackView { let s=NSStackView(views:views);s.spacing=12;s.alignment = .centerY;return s }
    func fixedGap(_ width:CGFloat)->NSView { let v=NSView();v.widthAnchor.constraint(equalToConstant:width).isActive=true;return v }
    func spacer()->NSView { let v=NSView();v.setContentHuggingPriority(NSLayoutConstraint.Priority(1),for:.horizontal);return v }
    func card(_ title:String?,_ views:[NSView],padding:CGFloat=20)->NSView {
        let content=stack(views,spacing:14), box=Theme.surface(content,radius:20,padding:padding)
        for v in views where v is NSTextField { v.widthAnchor.constraint(lessThanOrEqualTo:content.widthAnchor).isActive=true }
        for v in views where v is NSStackView { v.widthAnchor.constraint(equalTo:content.widthAnchor).isActive=true }
        guard let title else { return box }
        let heading=text(title,size:11);heading.font = .systemFont(ofSize:11,weight:.semibold);heading.textColor = .secondaryLabelColor
        let group=stack([heading,box],spacing:8)
        box.widthAnchor.constraint(equalTo:group.widthAnchor).isActive=true
        return group
    }
    /// Icon badge, title and explanation on the left; the control sits on the right.
    func featureRow(_ symbol:String,_ color:NSColor,_ title:String,_ detail:String,_ control:NSView)->NSStackView {
        let badge=NSImageView(image:badgeImage(symbol,color,size:34))
        let heading=text(title,size:14);heading.font = .systemFont(ofSize:14,weight:.semibold)
        let body=text(detail,size:12,secondary:true);body.preferredMaxLayoutWidth=400
        let words=stack([heading,body],spacing:3)
        body.widthAnchor.constraint(lessThanOrEqualTo:words.widthAnchor).isActive=true
        words.setContentHuggingPriority(.defaultLow,for:.horizontal);words.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let line=row([badge,words,control]);line.spacing=14
        control.setContentCompressionResistancePriority(.required,for:.horizontal)
        return line
    }
    func scrollPage(_ views:[NSView])->NSView {
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.drawsBackground=false;scroll.autohidesScrollers=true
        let document=FlippedDocumentView(), content=stack(views,spacing:22);document.translatesAutoresizingMaskIntoConstraints=false;content.translatesAutoresizingMaskIntoConstraints=false
        scroll.documentView=document;document.addSubview(content)
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),content.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:28),content.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-28),content.topAnchor.constraint(equalTo:document.topAnchor,constant:20),content.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-28)])
        for v in views { v.widthAnchor.constraint(equalTo:content.widthAnchor).isActive=true }
        return scroll
    }
    func symbolButton(_ title:String,_ symbol:String,_ action:Selector)->NSButton {
        let b=button(title,action);b.image=Theme.symbol(symbol,12,.semibold);b.imagePosition = .imageLeading;Theme.style(b,large:true);return b
    }
    func buildSidebar(_ sideView:NSView) {
        let mark=NSImageView(image:StatusKnob.image(position:0.62,amplitude:0.8));mark.contentTintColor = .controlAccentColor
        let brand=NSTextField(labelWithString:"ADI2 Native");brand.font = .systemFont(ofSize:15,weight:.bold)
        let sub=NSTextField(labelWithString:"RME ADI-2 DAC");sub.font = .systemFont(ofSize:11);sub.textColor = .secondaryLabelColor
        let title=row([mark,stack([brand,sub],spacing:1)]);title.spacing=8
        let navScroll=NSScrollView();navScroll.drawsBackground=false;navScroll.documentView=navigation
        navigation.addTableColumn(NSTableColumn(identifier:NSUserInterfaceItemIdentifier("section")));navigation.headerView=nil;navigation.rowHeight=38;navigation.style = .plain;navigation.selectionHighlightStyle = .regular;navigation.backgroundColor = .clear;navigation.dataSource=self;navigation.delegate=self;navigation.allowsEmptySelection=false;navigation.setAccessibilityLabel(L("功能分類", "Navigation"))
        // Live device summary, visible from every page.
        sideTarget.font = .systemFont(ofSize:12,weight:.semibold);sideReading.font=Theme.rounded(12,.medium);sideReading.textColor = .secondaryLabelColor
        sideKnob.image=StatusKnob.image(position:0,amplitude:0);sideKnob.contentTintColor = .tertiaryLabelColor
        let footerRow=row([sideKnob,stack([sideTarget,sideReading],spacing:1)]);footerRow.spacing=9
        // Plain tinted panel: glass on top of the glass sidebar would muddy both.
        let footer=CardView();footer.radius=14;footer.fill=Theme.dynamic(light:NSColor(white:1,alpha:0.6),dark:NSColor(white:1,alpha:0.06))
        footerRow.translatesAutoresizingMaskIntoConstraints=false;footer.addSubview(footerRow)
        NSLayoutConstraint.activate([footerRow.leadingAnchor.constraint(equalTo:footer.leadingAnchor,constant:12),footerRow.trailingAnchor.constraint(lessThanOrEqualTo:footer.trailingAnchor,constant:-12),footerRow.topAnchor.constraint(equalTo:footer.topAnchor,constant:10),footerRow.bottomAnchor.constraint(equalTo:footer.bottomAnchor,constant:-10)])
        for v in [title,navScroll,footer] { v.translatesAutoresizingMaskIntoConstraints=false;sideView.addSubview(v) }
        NSLayoutConstraint.activate([title.leadingAnchor.constraint(equalTo:sideView.leadingAnchor,constant:18),title.topAnchor.constraint(equalTo:sideView.topAnchor,constant:58),
            navScroll.topAnchor.constraint(equalTo:title.bottomAnchor,constant:18),navScroll.leadingAnchor.constraint(equalTo:sideView.leadingAnchor,constant:10),navScroll.trailingAnchor.constraint(equalTo:sideView.trailingAnchor,constant:-10),navScroll.bottomAnchor.constraint(equalTo:footer.topAnchor,constant:-12),
            footer.leadingAnchor.constraint(equalTo:sideView.leadingAnchor,constant:12),footer.trailingAnchor.constraint(equalTo:sideView.trailingAnchor,constant:-12),footer.bottomAnchor.constraint(equalTo:sideView.bottomAnchor,constant:-14)])
    }
    func buildWindow() {
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:760),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.titlebarSeparatorStyle = .none;window.isMovableByWindowBackground=true
        window.delegate=self;window.isReleasedWhenClosed=false;window.title="ADI2 Native";window.minSize=NSSize(width:900,height:660);window.center();window.setFrameAutosaveName("ADI2NativeMain")
        let split=NSSplitViewController(), side=NSViewController(), main=NSViewController()
        // macOS 26+ draws the sidebar as floating Liquid Glass; a custom material would cover it.
        let sideView:NSView
        if Theme.glass { sideView=NSView() } else { let v=NSVisualEffectView();v.material = .sidebar;v.blendingMode = .behindWindow;sideView=v }
        side.view=sideView
        buildSidebar(sideView)
        let sideItem=NSSplitViewItem(sidebarWithViewController:side);sideItem.minimumThickness=212;sideItem.maximumThickness=232;sideItem.canCollapse=false;split.addSplitViewItem(sideItem)
        main.view=CanvasView()
        let mainItem=NSSplitViewItem(viewController:main)
        // Let the ambient background run under the glass sidebar; content follows the safe area.
        if #available(macOS 26,*) { mainItem.automaticallyAdjustsSafeAreaInsets=true }
        split.addSplitViewItem(mainItem);window.contentViewController=split
        let leading=main.view.safeAreaLayoutGuide.leadingAnchor

        pageTitle.font = .systemFont(ofSize:26,weight:.bold)
        outputs.segmentCount=3;outputs.trackingMode = .selectOne;outputs.segmentStyle = .rounded;outputs.target=self;outputs.action=#selector(selectOutput);outputs.setAccessibilityLabel(L("控制目標", "Control target"))
        for (i,(name,jack)) in [("Line Out","RCA／XLR"),("Phones","6.3 mm"),("IEM","3.5 mm")].enumerated() { outputs.setLabel(name,forSegment:i);outputs.setToolTip("\(name) · \(jack)",forSegment:i);outputs.setWidth(78,forSegment:i) }
        outputs.selectedSegment=0
        let heading=row([pageTitle,spacer(),outputs])
        connectionDetail.font = .systemFont(ofSize:11);connectionDetail.textColor = .tertiaryLabelColor;connectionDetail.maximumNumberOfLines=1;connectionDetail.lineBreakMode = .byTruncatingTail
        connectionDetail.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let statusLine=row([statusPill,connectionDetail]);statusLine.spacing=10
        let header=stack([heading,statusLine],spacing:10);header.translatesAutoresizingMaskIntoConstraints=false;pageHost.translatesAutoresizingMaskIntoConstraints=false
        main.view.addSubview(header);main.view.addSubview(pageHost)
        NSLayoutConstraint.activate([header.leadingAnchor.constraint(equalTo:leading,constant:28),header.trailingAnchor.constraint(equalTo:main.view.trailingAnchor,constant:-28),header.topAnchor.constraint(equalTo:main.view.topAnchor,constant:30),heading.widthAnchor.constraint(equalTo:header.widthAnchor),statusLine.widthAnchor.constraint(lessThanOrEqualTo:header.widthAnchor),pageHost.topAnchor.constraint(equalTo:header.bottomAnchor,constant:8),pageHost.leadingAnchor.constraint(equalTo:leading),pageHost.trailingAnchor.constraint(equalTo:main.view.trailingAnchor),pageHost.bottomAnchor.constraint(equalTo:main.view.bottomAnchor)])

        // Volume: a dial that mirrors the menu bar knob, with the target and quick actions beside it.
        dial.target=self;dial.action=#selector(slide);dial.setAccessibilityLabel(L("DAC 音量，dB", "DAC volume, dB"))
        dial.widthAnchor.constraint(equalToConstant:236).isActive=true;dial.heightAnchor.constraint(equalToConstant:214).isActive=true
        toggle.target=self;toggle.action=#selector(toggleBridge);Theme.style(toggle,large:true)
        mute.target=self;mute.action=#selector(muteFromCheckbox);mute.setButtonType(.pushOnPushOff);Theme.style(mute,large:true);mute.imagePosition = .imageLeading;mute.image=Theme.symbol("speaker.wave.2.fill",13)
        stepButtons=[symbolButton("0.5 dB","minus",#selector(quieter)),symbolButton("0.5 dB","plus",#selector(louder))]
        stepButtons[0].setAccessibilityLabel(L("降低 0.5 dB", "Down 0.5 dB"));stepButtons[1].setAccessibilityLabel(L("提高 0.5 dB", "Up 0.5 dB"))
        let eyebrow=text(L("控制目標", "Control target"),size:11);eyebrow.font = .systemFont(ofSize:11,weight:.semibold);eyebrow.textColor = .secondaryLabelColor
        targetTitle.font=Theme.rounded(30,.bold);targetDetail.font = .systemFont(ofSize:14,weight:.medium);targetDetail.textColor = .tertiaryLabelColor
        let target=row([targetTitle,targetDetail]);target.alignment = .firstBaseline;target.spacing=8
        rangeCaption.font = .systemFont(ofSize:11);rangeCaption.textColor = .tertiaryLabelColor;rangeCaption.lineBreakMode = .byTruncatingTail;rangeCaption.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let note=text(L("DAC 音量設定 · 不是房間的聲壓讀值", "DAC level · Not the sound pressure in your room"),size:12,secondary:true)
        let actions=row(stepButtons+[mute]);actions.spacing=8
        let info=stack([eyebrow,target,note,actions,rangeCaption],spacing:6);info.setCustomSpacing(18,after:note);info.setCustomSpacing(12,after:actions)
        let heroRow=row([dial,info]);heroRow.spacing=36
        let live=card(nil,[heroRow],padding:24)
        let native=card(nil,[featureRow("keyboard",.systemBlue,L("Mac 原生控制", "Native Mac control"),L("啟用後，可用鍵盤音量鍵與控制中心調整。關閉此視窗後，選單列仍會繼續控制音量。", "Use volume keys and Control Center when enabled. Menu bar control continues after you close this window."),toggle)])
        let reference=card(L("建立你的聆聽基準", "Your listening reference"),[featureRow("ear",.systemTeal,L("固定其他增益，只用 DAC 調整", "Fix other gain stages; adjust with the DAC"),L("固定喇叭旋鈕、座位與播放器音量，再用 DAC 調整日常音量。Apple Watch 的「噪音」讀值可作粗略參考；dBA 不能直接換算成這裡的 dB。", "Keep speaker gain, seating and player volume fixed. Use the DAC for daily adjustments. Apple Watch Noise readings are a rough reference; dBA is not the dB shown here."),NSView()),text(L("控制目標只決定調整哪一組音量，不會切換 DAC 的實體插孔。", "The control target chooses which level to adjust. It does not switch the DAC’s physical output."),size:11,secondary:true)])
        let volumePage=scrollPage([live,native,reference])

        editor=EQEditor(bridge:bridge) { [weak self] in self?.report($0) }
        let eqPage=scrollPage([text(L("調整 DAC 內建 EQ。編輯後按「套用到 DAC」，才會改變聲音。", "Edit the DAC’s built-in EQ. Sound changes only after you apply."),size:12,secondary:true),editor.view])

        for check in [launch,restore,showDB,hideDock,openOnLaunch] { check.target=self;check.action=#selector(preferenceChanged) }
        loginStatus.font = .systemFont(ofSize:11);loginStatus.textColor = .secondaryLabelColor;loginStatus.lineBreakMode = .byWordWrapping;loginStatus.maximumNumberOfLines=0
        languagePicker.addItems(withTitles:["繁體中文","English"]);languagePicker.selectItem(at:Localization.language == "en" ? 1 : 0);languagePicker.target=self;languagePicker.action=#selector(changeLanguage)
        appearancePicker.addItems(withTitles:[L("自動", "Auto"),L("淺色", "Light"),L("深色", "Dark")]);appearancePicker.selectItem(at:["auto","light","dark"].firstIndex(of:settings.appearance) ?? 0);appearancePicker.target=self;appearancePicker.action=#selector(changeAppearance)
        let startup=card(L("一般", "General"),[settingsRows([
            settingRow(L("登入時啟動", "Open at login"),launch),
            settingRow(L("啟動時顯示控制面板", "Show control panel at launch"),openOnLaunch),
            settingRow(L("恢復原生音量控制", "Restore native volume control"),restore)
        ]),row([loginStatus,spacer(),button(L("登入項目設定…", "Login Items…"),#selector(openLoginSettings))])])
        let appearance=card(L("外觀與語言", "Appearance & language"),[settingsRows([
            settingRow(L("外觀", "Appearance"),appearancePicker),
            settingRow(L("隱藏 Dock 圖示", "Hide Dock icon"),hideDock),
            settingRow(L("選單列顯示音量", "Show volume in menu bar"),showDB),
            settingRow(L("介面語言", "Interface language"),languagePicker)
        ])])
        for f in [floor,ceiling] { f.widthAnchor.constraint(equalToConstant:80).isActive=true;f.alignment = .right;f.font=Theme.rounded(13) }
        floor.setAccessibilityLabel(L("滑桿下限 dB", "Slider minimum, dB"));ceiling.setAccessibilityLabel(L("音量上限 dB", "Volume ceiling, dB"))
        func unit()->NSTextField { let t=text("dB",secondary:true);return t }
        let range=card(L("目前輸出的音量範圍", "Volume range for this output"),[row([text(L("滑桿下限", "Slider minimum")),floor,unit(),fixedGap(20),text(L("音量上限", "Volume ceiling")),ceiling,unit(),spacer(),button(L("套用範圍", "Apply range"),#selector(applyRange))]),rangeFeedback,text(L("各輸出分別記憶。上限僅在原生控制啟用時由軟體校正；硬體旋鈕可能短暫超過上限。", "Saved per output. The ceiling is enforced by software while native control is on; the hardware knob may briefly exceed it."),size:12,secondary:true)])
        rangeFeedback.isHidden=true;rangeFeedback.font = .systemFont(ofSize:11);rangeFeedback.textColor = .systemGreen
        let device=card(L("裝置連線", "Device connection"),[text(L("USB 重接或喚醒後會先讀取 DAC 狀態，再恢復控制。手動改選其他 Mac 輸出時，不會自動搶回。", "After USB reconnect or wake, device state is read before control resumes. Selecting another Mac output prevents automatic takeover."),size:12,secondary:true),row([button(L("重新同步", "Sync now"),#selector(resync)),button(L("重新綁定 DAC", "Pair DAC again"),#selector(rebind))])])
        pages=[volumePage,eqPage,scrollPage([startup,appearance,range,device])]
        navigation.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);displayPage(0)
    }
}
