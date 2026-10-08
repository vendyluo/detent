import AppKit
@main struct PolishTests {
 static func main()throws {
  _ = NSApplication.shared
  let suite="local.Detent.PolishTests.\(UUID())",defaults=UserDefaults(suiteName:suite)!
  defer { defaults.removePersistentDomain(forName:suite) }
  let settings=Settings(defaults)
  assert(settings.hideDock && !settings.showWindowOnLaunch && !settings.showDB)
  settings.hideDock=false;settings.showWindowOnLaunch=true;settings.showDB=true
  let reread=Settings(defaults);assert(!reread.hideDock && reread.showWindowOnLaunch && reread.showDB)
  let midi=FakeMIDI(),audio=FakeAudio(),clock=Clock()
  let eq:[Int:Int]=[2:1,3:0,4:0,5:100,6:10,7:0,8:500,9:10,10:0,11:1000,12:10,13:0,14:5000,15:10,16:0,17:0,18:10000,19:10,20:0,21:0,22:85,23:9,24:0,25:6500,26:7,28:0]
  midi.state[3]?[11]=0;midi.state[4]=eq;midi.state[5]=eq
  let b=try Bridge(midi:midi,audio:audio,settings:settings,now:{clock.time},startTimer:false)
  let editor=EQEditor(bridge:b) { fatalError("Unexpected error: \($0)") }
  assert(!editor.apply.isEnabled)
  editor.gains[2].stringValue="-";editor.changed();assert(editor.dirty && !editor.apply.isEnabled && editor.validationMessage != nil)
  editor.discardDraft();assert(!editor.dirty && editor.gains[2].stringValue=="0.0")
  editor.frequencies[3].stringValue="5023";editor.changed();editor.applyChanges()
  assert(!editor.dirty && !editor.pendingApply && editor.frequencies[3].stringValue=="5020")
  editor.gains[2].stringValue="-1.0";editor.changed()
  midi.hardware(4,10,2);editor.refresh();assert(!editor.apply.isEnabled && editor.dirty)
  editor.discardDraft();assert(editor.gains[2].stringValue=="1.0")
  editor.gains[2].stringValue="-1.0";editor.changed();midi.acknowledge=false;editor.applyChanges()
  assert(editor.pendingApply)
  clock.time += 2.6;b.tick();editor.refresh()
  assert(editor.dirty && !editor.pendingApply && editor.applyFailure != nil && editor.gains[2].stringValue=="-1.0")
  print("PASS: Dock/startup preferences persist; invalid EQ blocked; discard; quantized acknowledgement; external conflict; failed apply retains draft")
 }
}
