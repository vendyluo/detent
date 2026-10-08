import Foundation

struct VolumeRange: Equatable {
    var minimum: Double = -114.5
    var maximum: Double = 0
    var valid: Bool { minimum.isFinite && maximum.isFinite && minimum >= -114.5 && maximum <= 0 && maximum - minimum >= 6 }
    /// The DAC stores volume in 0.1 dB steps. Off-grid limits would make the ceiling clamp
    /// round back above the ceiling and resend forever, so every stored range is snapped.
    var snapped: VolumeRange { VolumeRange(minimum:(minimum*10).rounded()/10,maximum:(maximum*10).rounded()/10) }
    func clamp(_ db: Double) -> Double { min(maximum, max(-114.5, db)) }
    // Zero is mute; a hardware value below the display range remains audible and unchanged.
    func scalar(_ db: Double) -> Float { Float(max(0.0001,min(1,(db-minimum)/(maximum-minimum)))) }
    func decibels(_ scalar: Float) -> Double { minimum + Double(min(1,max(0,scalar)))*(maximum-minimum) }
}
final class Settings {
    let defaults: UserDefaults
    init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if !defaults.bool(forKey:"iconOnlyDefaultApplied") {
            defaults.set(false,forKey:"showDB")
            defaults.set(true,forKey:"iconOnlyDefaultApplied")
        }
    }
    var channel: Int {
        get { let c=defaults.integer(forKey:"channel"); return [3,6,9].contains(c) ? c : 3 }
        set { if [3,6,9].contains(newValue) { defaults.set(newValue,forKey:"channel") } }
    }
    var wanted: Bool { get { defaults.bool(forKey:"bridgeWanted") } set { defaults.set(newValue,forKey:"bridgeWanted") } }
    var autoRestore: Bool { get { defaults.object(forKey:"autoRestore") as? Bool ?? true } set { defaults.set(newValue,forKey:"autoRestore") } }
    var showDB: Bool { get { defaults.object(forKey:"showDB") as? Bool ?? false } set { defaults.set(newValue,forKey:"showDB") } }
    var hideDock: Bool { get { defaults.object(forKey:"hideDock") as? Bool ?? true } set { defaults.set(newValue,forKey:"hideDock") } }
    /// "auto" follows macOS; "light" and "dark" pin the app's appearance.
    var appearance: String {
        get { let v=defaults.string(forKey:"appearance") ?? "auto"; return ["auto","light","dark"].contains(v) ? v : "auto" }
        set { if ["auto","light","dark"].contains(newValue) { defaults.set(newValue,forKey:"appearance") } }
    }
    var showWindowOnLaunch: Bool { get { defaults.bool(forKey:"showWindowOnLaunch") } set { defaults.set(newValue,forKey:"showWindowOnLaunch") } }
    var hasLaunchedPolish: Bool { get { defaults.bool(forKey:"hasLaunchedPolish") } set { defaults.set(newValue,forKey:"hasLaunchedPolish") } }
    var deviceUID: String? { get { defaults.string(forKey:"deviceUID") } set { defaults.set(newValue,forKey:"deviceUID") } }
    func range(_ channel: Int) -> VolumeRange {
        let r=VolumeRange(minimum:defaults.object(forKey:"minimum.\(channel)") as? Double ?? -114.5,maximum:defaults.object(forKey:"maximum.\(channel)") as? Double ?? 0)
        return r.valid && r.snapped.valid ? r.snapped : VolumeRange()
    }
    func setRange(_ range: VolumeRange, channel: Int) throws {
        let range=range.snapped
        guard range.valid else { throw BridgeError.message(L("範圍需介於 −114.5～0 dB，且上下限至少相差 6 dB", "The range must be within −114.5 to 0 dB and at least 6 dB wide.")) }
        defaults.set(range.minimum,forKey:"minimum.\(channel)"); defaults.set(range.maximum,forKey:"maximum.\(channel)")
    }
}
