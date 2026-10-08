import AppKit

/// Shared palette. Every color resolves per appearance, so Light, Dark and Auto all stay legible.
enum Theme {
    static func dynamic(light:NSColor,dark:NSColor)->NSColor {
        NSColor(name:nil) { $0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? dark : light }
    }
    static func rgb(_ hex:UInt32,_ alpha:CGFloat=1)->NSColor {
        NSColor(srgbRed:CGFloat(hex>>16&255)/255,green:CGFloat(hex>>8&255)/255,blue:CGFloat(hex&255)/255,alpha:alpha)
    }
    static let canvas=dynamic(light:rgb(0xF3F3F5),dark:rgb(0x1C1C1E))
    static let card=dynamic(light:.white,dark:rgb(0x2A2A2D))
    static let cardBorder=dynamic(light:NSColor(white:0,alpha:0.07),dark:NSColor(white:1,alpha:0.06))
    static let display=dynamic(light:NSColor(white:1,alpha:0.55),dark:NSColor(white:0,alpha:0.22))
    /// Soft ambient light behind the content so glass has something to refract.
    static let glowA=dynamic(light:rgb(0x8FB4FF,0.55),dark:rgb(0x2F5BFF,0.30))
    static let glowB=dynamic(light:rgb(0xD7B8FF,0.45),dark:rgb(0x7B3FE4,0.22))
    static let glowC=dynamic(light:rgb(0x9FE7E0,0.40),dark:rgb(0x0FA3A3,0.16))
    static let track=dynamic(light:NSColor(white:0,alpha:0.08),dark:NSColor(white:1,alpha:0.09))
    static let tick=dynamic(light:NSColor(white:0,alpha:0.22),dark:NSColor(white:1,alpha:0.22))
    static let knobFace=dynamic(light:NSColor(white:1,alpha:0.92),dark:NSColor(white:1,alpha:0.10))
    static let knobEdge=dynamic(light:NSColor(white:0,alpha:0.10),dark:NSColor(white:1,alpha:0.10))
    /// Five EQ bands, then Bass and Treble. Hues are spaced for both appearances.
    static let bands:[NSColor]=[
        dynamic(light:rgb(0xE5484D),dark:rgb(0xFF6369)), dynamic(light:rgb(0xF18A00),dark:rgb(0xFFA94D)),
        dynamic(light:rgb(0x2E9E5B),dark:rgb(0x4CC38A)), dynamic(light:rgb(0x0B84D8),dark:rgb(0x52A9FF)),
        dynamic(light:rgb(0x8E4EC6),dark:rgb(0xB283F0)), dynamic(light:rgb(0x7A6A55),dark:rgb(0xB8A890)),
        dynamic(light:rgb(0x5B6B7A),dark:rgb(0x9AABBD))]
    static func rounded(_ size:CGFloat,_ weight:NSFont.Weight = .regular)->NSFont {
        let base=NSFont.systemFont(ofSize:size,weight:weight)
        let descriptor=(base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor).addingAttributes([.featureSettings:[[NSFontDescriptor.FeatureKey.typeIdentifier:kNumberSpacingType,NSFontDescriptor.FeatureKey.selectorIdentifier:kMonospacedNumbersSelector]]])
        return NSFont(descriptor:descriptor,size:size) ?? base
    }
    static func symbol(_ name:String,_ size:CGFloat,_ weight:NSFont.Weight = .medium)->NSImage? {
        NSImage(systemSymbolName:name,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:size,weight:weight))
    }
    static var glass:Bool { if #available(macOS 26,*) { return true };return false }
    /// Liquid Glass on macOS 26+, a solid hairline card on earlier systems.
    static func surface(_ content:NSView,radius:CGFloat=18,padding:CGFloat=20)->NSView {
        let host=NSView();content.translatesAutoresizingMaskIntoConstraints=false;host.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo:host.leadingAnchor,constant:padding),content.trailingAnchor.constraint(equalTo:host.trailingAnchor,constant:-padding),content.topAnchor.constraint(equalTo:host.topAnchor,constant:padding),content.bottomAnchor.constraint(equalTo:host.bottomAnchor,constant:-padding)])
        if #available(macOS 26,*) {
            let glass=NSGlassEffectView();glass.cornerRadius=radius;glass.contentView=host;return glass
        }
        let card=CardView();card.radius=radius;host.translatesAutoresizingMaskIntoConstraints=false;card.addSubview(host)
        NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo:card.leadingAnchor),host.trailingAnchor.constraint(equalTo:card.trailingAnchor),host.topAnchor.constraint(equalTo:card.topAnchor),host.bottomAnchor.constraint(equalTo:card.bottomAnchor)])
        return card
    }
    static func style(_ button:NSButton,large:Bool=false) {
        if #available(macOS 26,*) { button.bezelStyle = .glass } else { button.bezelStyle = .rounded }
        if large { button.controlSize = .large }
    }
    /// Marks the one action a surface is asking for.
    static func setProminent(_ button:NSButton,_ prominent:Bool) {
        if #available(macOS 26,*) { button.tintProminence=prominent ? .primary : .automatic }
        else { button.bezelColor=prominent ? .controlAccentColor : nil }
    }
    static func apply(appearance:String) {
        NSApp.appearance=appearance == "light" ? NSAppearance(named:.aqua) : appearance == "dark" ? NSAppearance(named:.darkAqua) : nil
    }
    static func formatDB(_ db:Double)->String { String(format:"%.1f",db).replacingOccurrences(of:"-",with:"−") }
}

/// Rounded card surface with a hairline edge that tracks appearance changes.
final class CardView:NSView {
    var fill=Theme.card { didSet { needsDisplay=true } }
    var radius:CGFloat=12 { didSet { needsDisplay=true } }
    override func draw(_ dirtyRect:NSRect) {
        let path=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:radius,yRadius:radius)
        fill.setFill();path.fill();Theme.cardBorder.setStroke();path.lineWidth=1;path.stroke()
    }
}
final class CanvasView:NSView {
    override func setFrameSize(_ newSize:NSSize) { super.setFrameSize(newSize);needsDisplay=true }
    override func draw(_ dirtyRect:NSRect) {
        Theme.canvas.setFill();bounds.fill()
        let reach=max(bounds.width,bounds.height)
        for (color,x,y,r) in [(Theme.glowA,0.18,0.92,0.62),(Theme.glowB,0.92,0.78,0.5),(Theme.glowC,0.7,0.0,0.55)] as [(NSColor,CGFloat,CGFloat,CGFloat)] {
            let c=NSPoint(x:bounds.minX+bounds.width*x,y:bounds.minY+bounds.height*y)
            NSGradient(colors:[color,color.withAlphaComponent(0)])?.draw(fromCenter:c,radius:0,toCenter:c,radius:reach*r,options:[])
        }
    }
}

/// Connection state as a colored dot plus the existing summary label.
final class StatusPill:NSView {
    enum Tone { case live, ready, busy, warning, offline }
    let label:NSTextField
    private let dot=NSView()
    var tone:Tone = .offline { didSet { needsDisplay=true;dot.needsDisplay=true;updateDot() } }
    init(label:NSTextField) {
        self.label=label;super.init(frame:.zero)
        dot.wantsLayer=true;dot.layer?.cornerRadius=4
        label.font = .systemFont(ofSize:12,weight:.medium);label.textColor = .labelColor;label.maximumNumberOfLines=1;label.lineBreakMode = .byTruncatingTail
        for v in [dot,label] { v.translatesAutoresizingMaskIntoConstraints=false;addSubview(v) }
        NSLayoutConstraint.activate([dot.widthAnchor.constraint(equalToConstant:8),dot.heightAnchor.constraint(equalToConstant:8),dot.leadingAnchor.constraint(equalTo:leadingAnchor,constant:10),dot.centerYAnchor.constraint(equalTo:centerYAnchor),label.leadingAnchor.constraint(equalTo:dot.trailingAnchor,constant:7),label.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-11),label.centerYAnchor.constraint(equalTo:centerYAnchor),heightAnchor.constraint(equalToConstant:24)])
        updateDot()
    }
    required init?(coder:NSCoder) { nil }
    var color:NSColor { switch tone { case .live:return .systemGreen; case .ready:return .controlAccentColor; case .busy:return .systemYellow; case .warning:return .systemOrange; case .offline:return .tertiaryLabelColor } }
    private func updateDot() { effectiveAppearance.performAsCurrentDrawingAppearance { dot.layer?.backgroundColor=color.cgColor } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance();updateDot() }
    override func draw(_ dirtyRect:NSRect) {
        color.withAlphaComponent(0.13).setFill();NSBezierPath(roundedRect:bounds,xRadius:bounds.height/2,yRadius:bounds.height/2).fill()
    }
}

/// Large rotary volume control. Drag vertically, scroll, or use arrow keys; ⌥ gives 0.1 dB steps.
final class VolumeDial:NSControl {
    var minValue = -114.5 { didSet { needsDisplay=true } }
    var maxValue = 0.0 { didSet { needsDisplay=true } }
    var value = -114.5 { didSet { needsDisplay=true } }
    var hasValue=false { didSet { needsDisplay=true } }
    var muted=false { didSet { needsDisplay=true } }
    var mutedText="Muted" { didSet { needsDisplay=true } }
    private(set) var tracking=false
    private var dragOrigin:NSPoint = .zero, dragStart=0.0
    override var doubleValue:Double { get { value } set { value=newValue } }
    override var isEnabled:Bool { didSet { needsDisplay=true } }
    override var intrinsicContentSize:NSSize { NSSize(width:236,height:214) }
    override var acceptsFirstResponder:Bool { isEnabled }
    override var focusRingMaskBounds:NSRect { dialRect }
    override func drawFocusRingMask() { NSBezierPath(ovalIn:dialRect).fill() }
    private var dialRect:NSRect { let s=bounds.width;return NSRect(x:bounds.midX-s/2,y:bounds.maxY-s,width:s,height:s) }
    private var position:Double { maxValue>minValue ? min(1,max(0,(value-minValue)/(maxValue-minValue))) : 0 }
    private func angle(_ p:Double)->CGFloat { CGFloat(225-270*p) }

    override func draw(_ dirtyRect:NSRect) {
        let r=dialRect, c=NSPoint(x:r.midX,y:r.midY), outer=r.width/2-6
        let alpha:CGFloat=isEnabled && hasValue ? 1 : 0.45
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        // Ticks: 0.5 dB feel without implying a scale the DAC does not have.
        for i in 0...40 {
            let a=angle(Double(i)/40)*CGFloat.pi/180, major=i%10==0
            let p=NSBezierPath();p.lineWidth=major ? 1.6 : 1;p.lineCapStyle = .round
            p.move(to:NSPoint(x:c.x+(outer-(major ? 9 : 6))*cos(a),y:c.y+(outer-(major ? 9 : 6))*sin(a)));p.line(to:NSPoint(x:c.x+outer*cos(a),y:c.y+outer*sin(a)))
            Theme.tick.setStroke();p.stroke()
        }
        let ring=outer-20
        let track=NSBezierPath();track.appendArc(withCenter:c,radius:ring,startAngle:angle(0),endAngle:angle(1),clockwise:true);track.lineWidth=10;track.lineCapStyle = .round
        Theme.track.setStroke();track.stroke()
        let accent:NSColor=muted ? .systemRed : .controlAccentColor
        if hasValue && position>0.002 {
            let arc=NSBezierPath();arc.appendArc(withCenter:c,radius:ring,startAngle:angle(0),endAngle:angle(position),clockwise:true);arc.lineWidth=10;arc.lineCapStyle = .round
            (muted ? accent.withAlphaComponent(0.55) : accent).setStroke();arc.stroke()
        }
        // Knob face with a soft shadow and a pointer that matches the menu bar icon.
        let faceRadius=ring-17, face=NSRect(x:c.x-faceRadius,y:c.y-faceRadius,width:faceRadius*2,height:faceRadius*2)
        NSGraphicsContext.saveGraphicsState()
        let shadow=NSShadow();shadow.shadowBlurRadius=14;shadow.shadowOffset=NSSize(width:0,height:-4);shadow.shadowColor=NSColor.black.withAlphaComponent(0.16);shadow.set()
        Theme.knobFace.setFill();NSBezierPath(ovalIn:face).fill()
        NSGraphicsContext.restoreGraphicsState()
        // Specular rim: bright at the top, fading toward the bottom, like a lit glass edge.
        NSGraphicsContext.saveGraphicsState()
        let rim=NSBezierPath(ovalIn:face);rim.append(NSBezierPath(ovalIn:face.insetBy(dx:1.5,dy:1.5)));rim.windingRule = .evenOdd;rim.addClip()
        NSGradient(colors:[NSColor(white:1,alpha:0.95),NSColor(white:1,alpha:0.05),Theme.knobEdge])?.draw(in:face,angle:-90)
        NSGraphicsContext.restoreGraphicsState()
        if hasValue {
            let a=angle(position)*CGFloat.pi/180, at=NSPoint(x:c.x+(faceRadius-9)*cos(a),y:c.y+(faceRadius-9)*sin(a))
            accent.setFill();NSBezierPath(ovalIn:NSRect(x:at.x-3.5,y:at.y-3.5,width:7,height:7)).fill()
        }
        let number=hasValue ? Theme.formatDB(value) : "—"
        let big=NSAttributedString(string:number,attributes:[.font:Theme.rounded(30,.semibold),.foregroundColor:NSColor.labelColor])
        let unit=NSAttributedString(string:muted ? mutedText : "dB",attributes:[.font:NSFont.systemFont(ofSize:12,weight:.semibold),.foregroundColor:muted ? NSColor.systemRed : NSColor.secondaryLabelColor])
        big.draw(at:NSPoint(x:c.x-big.size().width/2,y:c.y-big.size().height/2+7))
        unit.draw(at:NSPoint(x:c.x-unit.size().width/2,y:c.y-big.size().height/2-12))
        let small:[NSAttributedString.Key:Any]=[.font:Theme.rounded(10,.medium),.foregroundColor:NSColor.tertiaryLabelColor]
        for (p,text) in [(0.0,Theme.formatDB(minValue)),(1.0,Theme.formatDB(maxValue))] {
            let s=NSAttributedString(string:text,attributes:small), a=angle(p)*CGFloat.pi/180
            s.draw(at:NSPoint(x:c.x+(ring-6)*cos(a)-s.size().width/2,y:c.y+outer*sin(a)-s.size().height-2))
        }
    }
    private func commit(_ next:Double) {
        let clamped=min(maxValue,max(minValue,next))
        guard abs(clamped-value)>0.0001 else { return }
        value=clamped;sendAction(action,to:target)
    }
    private func step(_ event:NSEvent?)->Double { event?.modifierFlags.contains(.option) == true ? 0.1 : 0.5 }
    override func mouseDown(with event:NSEvent) {
        guard isEnabled, hasValue else { return }
        window?.makeFirstResponder(self);tracking=true;dragOrigin=convert(event.locationInWindow,from:nil);dragStart=value
    }
    override func mouseDragged(with event:NSEvent) {
        guard tracking else { return }
        let p=convert(event.locationInWindow,from:nil), delta=Double((p.y-dragOrigin.y)+(p.x-dragOrigin.x)*0.5)
        let span=maxValue-minValue, s=step(event), raw=dragStart+delta/320*span*(s<0.5 ? 0.2 : 1)
        commit((raw/s).rounded()*s)
    }
    override func mouseUp(with event:NSEvent) { tracking=false }
    override func scrollWheel(with event:NSEvent) {
        guard isEnabled, hasValue, event.scrollingDeltaY != 0 else { return }
        let s=step(event), units=event.hasPreciseScrollingDeltas ? event.scrollingDeltaY/12 : event.scrollingDeltaY
        commit(((value+Double(units)*s)/s).rounded()*s)
    }
    override func keyDown(with event:NSEvent) {
        guard isEnabled, hasValue else { return super.keyDown(with:event) }
        switch event.specialKey {
        case .upArrow?, .rightArrow?: commit(value+step(event))
        case .downArrow?, .leftArrow?: commit(value-step(event))
        default: super.keyDown(with:event)
        }
    }
    override func isAccessibilityElement()->Bool { true }
    override func accessibilityRole()->NSAccessibility.Role? { .slider }
    override func accessibilityValue()->Any? { hasValue ? "\(Theme.formatDB(value)) dB\(muted ? ", \(mutedText)" : "")" : "—" }
    override func accessibilityPerformIncrement()->Bool { commit(value+0.5);return true }
    override func accessibilityPerformDecrement()->Bool { commit(value-0.5);return true }
}
