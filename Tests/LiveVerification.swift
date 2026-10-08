import Foundation
import CoreAudio
@main struct Verification {
 static func wait(_ condition:()->Bool,seconds:Double=5)->Bool {
  let end=Date().addingTimeInterval(seconds)
  while Date()<end { if condition() { return true };RunLoop.main.run(until:Date().addingTimeInterval(0.02)) };return condition()
 }
 static func require(_ condition:Bool,_ label:String)throws {
  if !condition { throw BridgeError.message("FAIL: \(label)") };print("PASS: \(label)");fflush(stdout)
 }
 static func main()throws {
  let suite="local.Detent.LiveTest.\(UUID())", defaults=UserDefaults(suiteName:suite)!
  defer { defaults.removePersistentDomain(forName:suite) }
  let settings=Settings(defaults)
  settings.channel=Int(CommandLine.arguments.dropFirst().first ?? "3") ?? 3
  let b=try Bridge(midi:RMEConnection(),audio:SystemAudio(),settings:settings)
  try require(wait { b.synchronized && b.eqState != nil },"hardware volume and full EQ state received")
  let initial=b.values[b.channel]![12]!, muted=b.hardwareMuted, originalEQ=b.eqState!
  let originalOutput=try Audio.defaultDevice(), originalSystem=try Audio.defaultDevice(true)
  try require(initial > -750 && initial <= -30,"initial volume within reversible test range")
  defer {
   // Restore only changes belonging to this verification; keep the user's other settings intact.
   try? b.setRange(VolumeRange())
   if let eq=b.eqState, eq != originalEQ { try? b.applyEQ(originalEQ);_ = wait { b.eqState==originalEQ && !b.hasPending } }
   if let current=b.values[b.channel]?[12], (initial-25...initial).contains(current) {
    try? b.send([RMEParameter(channel:b.channel,index:12,value:initial)]);_ = wait { b.values[b.channel]?[12]==initial && !b.hasPending }
   }
   if b.hardwareMuted != muted { try? b.setMuted(muted);_ = wait { b.hardwareMuted==muted } }
   b.disable();b.shutdown()
  }
  try b.enable()
  try require(try Audio.defaultDevice()==b.proxy!.id,"native proxy selected")
  try Audio.setVolume(b.proxy!.id,b.range.scalar(Double(initial-5)/10))
  try require(wait { b.values[b.channel]?[12]==initial-5 && !b.hasPending },"native slider → DAC volume (-0.5 dB)")
  try b.midi.send(RMEProtocol.set(channel:b.channel,index:12,value:initial-10));try b.requestSettings()
  try require(wait { abs(((try? Audio.volume(b.proxy!.id)) ?? 0)-b.range.scalar(Double(initial-10)/10))<0.0001 },"hardware change → native slider")
  if !muted {
   try Audio.setMute(b.proxy!.id,true);try require(wait { b.hardwareMuted && !b.hasPending },"native mute")
   try Audio.setMute(b.proxy!.id,false);try require(wait { !b.hardwareMuted && !b.hasPending },"native unmute")
  }
  let ceiling=Double(initial-20)/10
  try b.setRange(VolumeRange(minimum:-80,maximum:ceiling))
  try require(wait { b.values[b.channel]?[12]==initial-20 && !b.hasPending },"per-output ceiling lowers existing gain")
  let advertised=try Audio.read(b.proxy!.id,kAudioDevicePropertyVolumeRangeDecibels,AudioValueRange(),scope:kAudioObjectPropertyScopeOutput,element:1)
  try require(abs(advertised.mMinimum+80)<0.001 && abs(advertised.mMaximum-ceiling)<0.001,"driver advertises configured dB range")
  try b.midi.send(RMEProtocol.set(channel:b.channel,index:12,value:initial-15));try b.requestSettings()
  try require(wait { b.values[b.channel]?[12]==initial-20 && !b.hasPending },"ceiling also clamps hardware changes")
  try b.setRange(VolumeRange())
  let eqIndex=10, oldGain=b.values[b.eqAddress]![eqIndex]!, newGain=oldGain > -24 ? oldGain-1 : oldGain
  try b.send([RMEParameter(channel:b.eqAddress,index:eqIndex,value:newGain)])
  try require(wait { b.values[b.eqAddress]?[eqIndex]==newGain && !b.hasPending },"EQ band gain write/readback")
  try b.send([RMEParameter(channel:b.eqAddress,index:eqIndex,value:oldGain)])
  try require(wait { b.values[b.eqAddress]?[eqIndex]==oldGain && !b.hasPending },"EQ band gain restored")
  try b.applyEQ(originalEQ)
  try require(wait { b.eqState==originalEQ && !b.hasPending },"complete EQ/Bass/Treble settings accepted without changing sound")
  try require(wait({b.presetNames.count==20},seconds:8),"all 20 hardware EQ preset names received")
  b.willSleep();try require(!b.enabled && b.wanted,"sleep suspends bridge and remembers intent")
  b.didWake();try require(wait { b.enabled && b.synchronized },"wake reconnects and restores bridge")
  try b.send([RMEParameter(channel:b.channel,index:12,value:initial)])
  try require(wait { b.values[b.channel]?[12]==initial && !b.hasPending },"original hardware volume restored")
  try require(b.eqState==originalEQ,"original EQ preserved")
  b.disable()
  try require(try Audio.defaultDevice()==originalOutput && Audio.defaultDevice(true)==originalSystem,"original output devices restored")
 }
}
