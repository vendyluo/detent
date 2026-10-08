import AppKit

/// A template image keeps system tint, contrast and highlighted-menu appearance.
final class StatusKnob {
    weak var button:NSStatusBarButton?
    private var timer:Timer?
    private var position=0.5, target=0.5, amplitude=0.0
    private var last=Date(), motionUntil=Date.distantPast
    private var initialized=false
    init(_ button:NSStatusBarButton?) { self.button=button }
    deinit { timer?.invalidate() }
    func update(db:Double?,range:VolumeRange) {
        guard let db else { return }
        let next=min(1,max(0,(db-range.minimum)/(range.maximum-range.minimum)))
        guard initialized else { initialized=true;position=next;target=next;render();return }
        guard abs(next-target)>0.00001 else { return }
        target=next
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { position=target;amplitude=0;timer?.invalidate();timer=nil;render();return }
        motionUntil=Date().addingTimeInterval(0.3)
        guard timer == nil else { return }
        last=Date()
        let t=Timer(timeInterval:1.0/30,repeats:true) { [weak self] _ in self?.tick() }
        timer=t;RunLoop.main.add(t,forMode:.common)
    }
    private func tick() {
        let now=Date(),dt=min(0.1,now.timeIntervalSince(last));last=now
        position += (target-position)*(1-exp(-dt*14))
        let moving=now<motionUntil || abs(target-position)>0.001
        amplitude += ((moving ? 1.0 : 0)-amplitude)*(1-exp(-dt*12))
        if !moving && amplitude<0.01 { position=target;amplitude=0;timer?.invalidate();timer=nil }
        render()
    }
    private func render() { button?.image=Self.image(position:position,amplitude:amplitude) }
    /// Same arc-and-dot mark as the app icon; the lit arc tracks the volume and thickens slightly while moving.
    static func image(position:Double,amplitude:Double)->NSImage {
        let image=NSImage(size:NSSize(width:24,height:18),flipped:false) { _ in
            let c=NSPoint(x:12,y:9), p=min(1,max(0,position))
            func angle(_ v:Double)->CGFloat { CGFloat(225-270*v) }
            let track=NSBezierPath();track.appendArc(withCenter:c,radius:7,startAngle:angle(0),endAngle:angle(1),clockwise:true)
            track.lineWidth=2;track.lineCapStyle = .round;NSColor.black.withAlphaComponent(0.35).setStroke();track.stroke()
            if p>0.005 {
                let lit=NSBezierPath();lit.appendArc(withCenter:c,radius:7,startAngle:angle(0),endAngle:angle(p),clockwise:true)
                lit.lineWidth=2+0.5*CGFloat(amplitude);lit.lineCapStyle = .round;NSColor.black.setStroke();lit.stroke()
            }
            let a=angle(p)*CGFloat.pi/180;NSColor.black.setFill()
            NSBezierPath(ovalIn:NSRect(x:c.x+3*cos(a)-1.6,y:c.y+3*sin(a)-1.6,width:3.2,height:3.2)).fill()
            return true
        }
        image.isTemplate=true;return image
    }
}
