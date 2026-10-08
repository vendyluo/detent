import AppKit
import Foundation

let root = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let assets = root.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at:assets,withIntermediateDirectories:true)
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed:CGFloat((hex >> 16)&255)/255,green:CGFloat((hex >> 8)&255)/255,blue:CGFloat(hex&255)/255,alpha:alpha)
}
func stroke(_ points: [NSPoint], color c: NSColor, width: CGFloat) {
    let p = NSBezierPath(); p.lineWidth=width; p.lineCapStyle = .round; p.lineJoinStyle = .round
    p.move(to:points[0]); for point in points.dropFirst() { p.line(to:point) }; c.setStroke(); p.stroke()
}
func fill(_ rect: NSRect, _ radius: CGFloat, _ c: NSColor) {
    c.setFill(); NSBezierPath(roundedRect:rect,xRadius:radius,yRadius:radius).fill()
}
// One geometry drives the bitmap icon, the vector SVG, and (scaled down) the menu-bar mark.
enum Mark {
    static let level=0.68                        // lit fraction of the 270° arc
    static let center=NSPoint(x:512,y:500), arcRadius:CGFloat=272, arcWidth:CGFloat=68
    static let knobRadius:CGFloat=176, dotRadius:CGFloat=25, dotDistance:CGFloat=118
    static func angle(_ p:Double)->CGFloat { CGFloat(225-270*p) }
    static var dot:NSPoint { let a=angle(level)*CGFloat.pi/180;return NSPoint(x:center.x+dotDistance*cos(a),y:center.y+dotDistance*sin(a)) }
}
/// Superellipse (n≈5) approximates the continuous-corner macOS icon shape.
func squircle(_ rect:NSRect)->[NSPoint] {
    (0..<240).map { i in
        let t=Double(i)/240*2*Double.pi, c=cos(t), s=sin(t)
        return NSPoint(x:rect.midX+rect.width/2*CGFloat(copysign(pow(abs(c),0.4),c)),y:rect.midY+rect.height/2*CGFloat(copysign(pow(abs(s),0.4),s)))
    }
}
let body=NSRect(x:100,y:100,width:824,height:824)
func appIcon() {
    let points=squircle(body), tile=NSBezierPath();tile.move(to:points[0]);points.dropFirst().forEach(tile.line);tile.close()
    NSGraphicsContext.saveGraphicsState()
    let shadow=NSShadow();shadow.shadowColor=color(0x0A1440,0.35);shadow.shadowBlurRadius=28;shadow.shadowOffset=NSSize(width:0,height:-12);shadow.set()
    color(0x2A49E0).setFill();tile.fill();NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState();tile.addClip()
    NSGradient(colors:[color(0x6FA2FF),color(0x3D63F2),color(0x2335C4)])!.draw(in:tile,angle:-90)
    NSGradient(colors:[color(0xFFFFFF,0.32),color(0xFFFFFF,0)])!.draw(fromCenter:NSPoint(x:330,y:860),radius:0,toCenter:NSPoint(x:330,y:860),radius:560,options:[])
    NSGraphicsContext.restoreGraphicsState()
    // Lit glass edge around the tile.
    NSGraphicsContext.saveGraphicsState()
    let inner=squircle(body.insetBy(dx:4,dy:4)), edge=NSBezierPath();edge.move(to:points[0]);points.dropFirst().forEach(edge.line);edge.close()
    edge.move(to:inner[0]);inner.dropFirst().forEach(edge.line);edge.close();edge.windingRule = .evenOdd;edge.addClip()
    NSGradient(colors:[color(0xFFFFFF,0.75),color(0xFFFFFF,0.08),color(0xFFFFFF,0.25)])!.draw(in:body,angle:-90)
    NSGraphicsContext.restoreGraphicsState()
    // Level arc: track, then the lit portion.
    let c=Mark.center
    let track=NSBezierPath();track.appendArc(withCenter:c,radius:Mark.arcRadius,startAngle:Mark.angle(0),endAngle:Mark.angle(1),clockwise:true)
    track.lineWidth=Mark.arcWidth;track.lineCapStyle = .round;color(0xFFFFFF,0.22).setStroke();track.stroke()
    let lit=NSBezierPath();lit.appendArc(withCenter:c,radius:Mark.arcRadius,startAngle:Mark.angle(0),endAngle:Mark.angle(Mark.level),clockwise:true)
    lit.lineWidth=Mark.arcWidth;lit.lineCapStyle = .round
    NSGraphicsContext.saveGraphicsState()
    let glow=NSShadow();glow.shadowColor=color(0xBFE6FF,0.9);glow.shadowBlurRadius=30;glow.set()
    color(0xFFFFFF).setStroke();lit.stroke();NSGraphicsContext.restoreGraphicsState()
    // Glass knob: translucent body, specular rim, soft drop shadow.
    let knobRect=NSRect(x:c.x-Mark.knobRadius,y:c.y-Mark.knobRadius,width:Mark.knobRadius*2,height:Mark.knobRadius*2), knob=NSBezierPath(ovalIn:knobRect)
    NSGraphicsContext.saveGraphicsState()
    let drop=NSShadow();drop.shadowColor=color(0x0B1A70,0.45);drop.shadowBlurRadius=44;drop.shadowOffset=NSSize(width:0,height:-22);drop.set()
    color(0x4E72F5).setFill();knob.fill();NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors:[color(0xFFFFFF,0.55),color(0xFFFFFF,0.16),color(0xFFFFFF,0.24)])!.draw(in:knob,angle:-90)
    NSGraphicsContext.saveGraphicsState()
    let rim=NSBezierPath(ovalIn:knobRect);rim.append(NSBezierPath(ovalIn:knobRect.insetBy(dx:7,dy:7)));rim.windingRule = .evenOdd;rim.addClip()
    NSGradient(colors:[color(0xFFFFFF,0.95),color(0xFFFFFF,0.1),color(0xFFFFFF,0.45)])!.draw(in:knobRect,angle:-90)
    NSGraphicsContext.restoreGraphicsState()
    let d=Mark.dot;color(0xFFFFFF).setFill();NSBezierPath(ovalIn:NSRect(x:d.x-Mark.dotRadius,y:d.y-Mark.dotRadius,width:Mark.dotRadius*2,height:Mark.dotRadius*2)).fill()
}
/// Vector version of the same mark for READMEs and the web. SVG's y axis points down.
func svg()->String {
    func f(_ v:CGFloat)->String { String(format:"%.1f",v) }
    func pt(_ p:NSPoint)->String { "\(f(p.x)),\(f(1024-p.y))" }
    let tile="M"+squircle(body).map(pt).joined(separator:" L")+" Z"
    func arc(_ to:Double)->String {
        let c=Mark.center, r=Mark.arcRadius, a0=Mark.angle(0)*CGFloat.pi/180, a1=Mark.angle(to)*CGFloat.pi/180
        let large=270*to>180 ? 1 : 0
        return "M\(pt(NSPoint(x:c.x+r*cos(a0),y:c.y+r*sin(a0)))) A\(f(r)),\(f(r)) 0 \(large) 1 \(pt(NSPoint(x:c.x+r*cos(a1),y:c.y+r*sin(a1))))"
    }
    let c=Mark.center, d=Mark.dot
    return """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
      <defs>
        <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#6FA2FF"/><stop offset="0.5" stop-color="#3D63F2"/><stop offset="1" stop-color="#2335C4"/></linearGradient>
        <radialGradient id="sheen" cx="330" cy="164" r="560" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#fff" stop-opacity="0.32"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
        <linearGradient id="knob" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.55"/><stop offset="0.5" stop-color="#fff" stop-opacity="0.16"/><stop offset="1" stop-color="#fff" stop-opacity="0.24"/></linearGradient>
        <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.95"/><stop offset="0.5" stop-color="#fff" stop-opacity="0.1"/><stop offset="1" stop-color="#fff" stop-opacity="0.45"/></linearGradient>
        <filter id="drop" x="-30%" y="-30%" width="160%" height="170%"><feDropShadow dx="0" dy="22" stdDeviation="22" flood-color="#0B1A70" flood-opacity="0.45"/></filter>
        <filter id="glow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="0" stdDeviation="15" flood-color="#BFE6FF" flood-opacity="0.9"/></filter>
      </defs>
      <path d="\(tile)" fill="url(#bg)"/>
      <path d="\(tile)" fill="url(#sheen)"/>
      <path d="\(arc(1))" fill="none" stroke="#fff" stroke-opacity="0.22" stroke-width="\(f(Mark.arcWidth))" stroke-linecap="round"/>
      <path d="\(arc(Mark.level))" fill="none" stroke="#fff" stroke-width="\(f(Mark.arcWidth))" stroke-linecap="round" filter="url(#glow)"/>
      <circle cx="\(f(c.x))" cy="\(f(1024-c.y))" r="\(f(Mark.knobRadius))" fill="#4E72F5" filter="url(#drop)"/>
      <circle cx="\(f(c.x))" cy="\(f(1024-c.y))" r="\(f(Mark.knobRadius))" fill="url(#knob)"/>
      <circle cx="\(f(c.x))" cy="\(f(1024-c.y))" r="\(f(Mark.knobRadius-3.5))" fill="none" stroke="url(#rim)" stroke-width="7"/>
      <circle cx="\(f(d.x))" cy="\(f(1024-d.y))" r="\(f(Mark.dotRadius))" fill="#fff"/>
    </svg>

    """
}
/// Menu-bar mark: the same arc and dot, drawn as a template at 24 × 18 pt.
func tray(_ tint: NSColor) {
    let c=NSPoint(x:12,y:9), level=Mark.level
    let track=NSBezierPath();track.appendArc(withCenter:c,radius:7,startAngle:Mark.angle(0),endAngle:Mark.angle(1),clockwise:true)
    track.lineWidth=2;track.lineCapStyle = .round;tint.withAlphaComponent(0.35).setStroke();track.stroke()
    let lit=NSBezierPath();lit.appendArc(withCenter:c,radius:7,startAngle:Mark.angle(0),endAngle:Mark.angle(level),clockwise:true)
    lit.lineWidth=2;lit.lineCapStyle = .round;tint.setStroke();lit.stroke()
    let a=Mark.angle(level)*CGFloat.pi/180;tint.setFill()
    NSBezierPath(ovalIn:NSRect(x:c.x+3*cos(a)-1.6,y:c.y+3*sin(a)-1.6,width:3.2,height:3.2)).fill()
}
func png(width:Int,height:Int,logical:NSSize,draw:()->Void) throws -> Data {
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    rep.size=NSSize(width:width,height:height)
    let context=NSGraphicsContext(bitmapImageRep:rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=context
    context.cgContext.scaleBy(x:CGFloat(width)/logical.width,y:CGFloat(height)/logical.height)
    draw(); NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using:.png,properties:[:])!
}
let iconset=assets.appendingPathComponent("AppIcon.iconset",isDirectory:true)
try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
for base in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels=base*scale
        let data=try png(width:pixels,height:pixels,logical:NSSize(width:1024,height:1024),draw:appIcon)
        try data.write(to:iconset.appendingPathComponent("icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"))
        if pixels == 1024 { try data.write(to:assets.appendingPathComponent("AppIcon.png")) }
    }
}
for scale in [1,2] {
    let data=try png(width:24*scale,height:18*scale,logical:NSSize(width:24,height:18)) { tray(.black) }
    try data.write(to:assets.appendingPathComponent("StatusIconTemplate\(scale == 2 ? "@2x" : "").png"))
}
// Export a true vector PDF for NSStatusItem so arbitrary display scales stay crisp.
let pdfData=NSMutableData()
let consumer=CGDataConsumer(data:pdfData)!
var mediaBox=CGRect(x:0,y:0,width:24,height:18)
let pdf=CGContext(consumer:consumer,mediaBox:&mediaBox,nil)!
pdf.beginPDFPage(nil)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(cgContext:pdf,flipped:false)
tray(.black); NSGraphicsContext.restoreGraphicsState(); pdf.endPDFPage(); pdf.closePDF()
try (pdfData as Data).write(to:assets.appendingPathComponent("StatusIconTemplate.pdf"))
try svg().write(to:assets.appendingPathComponent("Logo.svg"),atomically:true,encoding:.utf8)
// A compact review sheet at real menu-bar scale, plus app icon sizes.
let preview=try png(width:1100,height:600,logical:NSSize(width:1100,height:600)) {
    color(0xF1F3F7).setFill(); NSBezierPath(rect:NSRect(x:0,y:0,width:1100,height:600)).fill()
    func text(_ s:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ c:NSColor) {
        (s as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:.medium),.foregroundColor:c])
    }
    text("ADI2 Native",48,538,26,color(0x1D2A3D))
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current!.cgContext.translateBy(x:25,y:100); NSGraphicsContext.current!.cgContext.scaleBy(x:0.42,y:0.42); appIcon(); NSGraphicsContext.restoreGraphicsState()
    text("APP ICON",508,477,13,color(0x57657C))
    for (index,size) in [128,64,32,16].enumerated() {
        let data=try! png(width:size*2,height:size*2,logical:NSSize(width:1024,height:1024),draw:appIcon)
        NSImage(data:data)!.draw(in:NSRect(x:508+CGFloat(index)*135,y:320,width:CGFloat(size),height:CGFloat(size)))
    }
    text("MENU BAR · LIGHT / DARK",508,256,13,color(0x57657C))
    fill(NSRect(x:508,y:185,width:250,height:44),10,color(0xDCE2EA))
    fill(NSRect(x:778,y:185,width:250,height:44),10,color(0x202736))
    for (x,c) in [(CGFloat(536),color(0x172232)),(CGFloat(806),NSColor.white)] {
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current!.cgContext.translateBy(x:x,y:198); tray(c); NSGraphicsContext.restoreGraphicsState()
    }
    text("24 × 18 pt · template PDF",508,135,15,color(0x57657C))
}
try preview.write(to:assets.appendingPathComponent("IconPreview.png"))
print("Rendered app icon, iconset, SVG logo, vector menu-bar icon, and preview.")
