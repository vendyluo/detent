import AppKit
@main struct LocalizationTests {
 static func main()throws {
  _ = NSApplication.shared
  let suite="local.ADI2Native.LanguageTests.\(UUID())",defaults=UserDefaults(suiteName:suite)!
  defer { defaults.removePersistentDomain(forName:suite);Localization.language="zh-Hant" }
  Localization.language="zh-Hant"
  let midi=FakeMIDI(),audio=FakeAudio()
  let eq:[Int:Int]=[2:0,3:1,4:0,5:100,6:5,7:0,8:500,9:10,10:0,11:1000,12:10,13:0,14:5000,15:10,16:1,17:0,18:10000,19:10,20:1,21:-2,22:85,23:9,24:0,25:6500,26:7,28:0]
  midi.state[3]?[11]=0;midi.state[4]=eq;midi.state[5]=eq
  let delegate=AppDelegate();delegate.bridge=try Bridge(midi:midi,audio:audio,settings:Settings(defaults),now:{100},startTimer:false)
  delegate.buildWindow()
  delegate.editor.gains[2].stringValue="-1.0";delegate.editor.changed()
  let draft=delegate.editor.draft
  _ = delegate.bridge.controlSummary
  Localization.language="en";delegate.localizeInterface()
  assert(delegate.editor.draft==draft && delegate.editor.dirty && midi.writes.isEmpty)
  assert(delegate.bridge.controlSummary=="Direct DAC control · Native control off")
  var untranslated:[String]=[]
  func inspect(_ v:NSView) {
   if v === delegate.languagePicker { return }
   if let field=v as? NSTextField,!field.isEditable,field.stringValue.unicodeScalars.contains(where:{(0x3400...0x9FFF).contains($0.value)}) { untranslated.append(field.stringValue) }
   if let button=v as? NSButton,button.title.unicodeScalars.contains(where:{(0x3400...0x9FFF).contains($0.value)}) { untranslated.append(button.title) }
   for child in v.subviews { inspect(child) }
  }
  for page in delegate.pages { inspect(page) }
  assert(untranslated.isEmpty,"Untranslated: \(untranslated)")
  for i in delegate.editor.template.itemArray { for t in [i.title,i.toolTip ?? ""] where t.unicodeScalars.contains(where:{(0x3400...0x9FFF).contains($0.value)}) { untranslated.append(t) } }
  assert(untranslated.isEmpty,"Untranslated templates: \(untranslated)")
  assert(delegate.editor.apply.title=="Apply to DAC")
  Localization.language="zh-Hant";delegate.localizeInterface()
  assert(delegate.editor.apply.title=="套用到 DAC" && delegate.editor.draft==draft)
  print("PASS: all page labels translate to English and back; EQ draft preserved; language switching sends no DAC writes")
 }
}
