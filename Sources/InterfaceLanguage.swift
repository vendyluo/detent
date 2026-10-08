import AppKit

extension AppDelegate {
    @objc func changeAppearance() {
        settings.appearance=["auto","light","dark"][max(0,appearancePicker.indexOfSelectedItem)]
        Theme.apply(appearance:settings.appearance)
    }
    @objc func changeLanguage() {
        Localization.language=languagePicker.indexOfSelectedItem==1 ? "en" : "zh-Hant"
        settings.defaults.set(Localization.language,forKey:"interfaceLanguage")
        let selected=max(0,navigation.selectedRow)
        navigation.reloadData();navigation.selectRowIndexes(IndexSet(integer:selected),byExtendingSelection:false)
        pageTitle.stringValue=pageNames[selected]
        localizeInterface()
        refresh(force:true)
    }
    func localizeInterface() {
        func menu(_ m:NSMenu) {
            for i in m.items {
                if !(1...20).contains(i.tag) { i.title=Localization.translated(i.title) }
                if let sub=i.submenu { menu(sub) }
            }
        }
        func walk(_ v:NSView) {
            if let f=v as? NSTextField, !f.isEditable { f.stringValue=Localization.translated(f.stringValue) }
            if let p=v as? NSPopUpButton {
                if p === editor.template { editor.fillTemplates() }
                else if p === editor.preset { editor.refresh() } // Its titles are built from live DAC state.
                else if p !== languagePicker, let m=p.menu { menu(m) }
            } else if let b=v as? NSButton { b.title=Localization.translated(b.title) }
            if let label=v.accessibilityLabel() { v.setAccessibilityLabel(Localization.translated(label)) }
            for child in v.subviews { walk(child) }
        }
        if let content=window?.contentView { walk(content) }
        for page in pages { walk(page) }
        if let m=item?.menu { menu(m) }
        if let m=NSApp.mainMenu { menu(m) }
    }
    func sidebarBadge(_ index:Int)->NSImage {
        badgeImage(["speaker.wave.2.fill","slider.horizontal.3","gearshape.fill"][index],[NSColor.systemBlue,.systemPurple,.systemGray][index],size:26)
    }
    func badgeImage(_ symbol:String,_ color:NSColor,size:CGFloat)->NSImage {
        NSImage(size:NSSize(width:size,height:size),flipped:false) { rect in
            let shape=NSBezierPath(roundedRect:rect.insetBy(dx:1,dy:1),xRadius:size*0.25,yRadius:size*0.25)
            NSGradient(starting:color.blended(withFraction:0.18,of:.white) ?? color,ending:color)?.draw(in:shape,angle:-90)
            let icon=NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:size*0.42,weight:.semibold).applying(.init(paletteColors:[.white])))
            if let icon { let s=icon.size;icon.draw(in:NSRect(x:(size-s.width)/2,y:(size-s.height)/2,width:s.width,height:s.height)) }
            return true
        }
    }
    func settingRow(_ title:String,_ control:NSView)->NSView {
        let label=text(title),spacer=NSView(),line=row([label,spacer,control])
        label.font = .systemFont(ofSize:13)
        control.setAccessibilityLabel(title)
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1),for:.horizontal)
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant:16).isActive=true
        line.heightAnchor.constraint(greaterThanOrEqualToConstant:38).isActive=true
        return line
    }
    func settingsRows(_ rows:[NSView])->NSStackView {
        let group=stack([],spacing:0)
        for (index,row) in rows.enumerated() {
            if index>0 { let line=NSBox();line.boxType = .separator;line.heightAnchor.constraint(equalToConstant:1).isActive=true;group.addArrangedSubview(line);line.widthAnchor.constraint(equalTo:group.widthAnchor).isActive=true }
            group.addArrangedSubview(row);row.widthAnchor.constraint(equalTo:group.widthAnchor).isActive=true
        }
        return group
    }
}
