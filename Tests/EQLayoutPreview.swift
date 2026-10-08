import AppKit
import Foundation
@main struct Preview {
    static func main()throws {
        _ = NSApplication.shared
        let defaults=UserDefaults(suiteName:"local.Detent.LayoutPreview")!
        defer { defaults.removePersistentDomain(forName:"local.Detent.LayoutPreview") }
        let midi=FakeMIDI(), audio=FakeAudio()
        let eq:[Int:Int]=[2:1,3:1,4:0,5:100,6:5,7:0,8:500,9:10,10:0,11:1000,12:10,13:0,14:5000,15:10,16:1,17:0,18:10000,19:10,20:1,21:-2,22:85,23:9,24:0,25:6500,26:7,28:0]
        midi.state[3]?[11]=0;midi.state[4]=eq;midi.state[5]=eq
        let b=try Bridge(midi:midi,audio:audio,settings:Settings(defaults),startTimer:false)
        let editor=EQEditor(bridge:b) { print($0) }
        let host=NSView(frame:NSRect(x:0,y:0,width:780,height:690));host.wantsLayer=true;host.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor
        editor.view.translatesAutoresizingMaskIntoConstraints=false;host.addSubview(editor.view)
        NSLayoutConstraint.activate([editor.view.leadingAnchor.constraint(equalTo:host.leadingAnchor,constant:16),editor.view.topAnchor.constraint(equalTo:host.topAnchor,constant:16)])
        host.layoutSubtreeIfNeeded()
        guard let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw BridgeError.message("Cannot render preview") }
        host.cacheDisplay(in:host.bounds,to:rep)
        try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
    }
}
