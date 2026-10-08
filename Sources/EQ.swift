import Foundation

enum FilterKind:String,CaseIterable { case peak="Peak", lowShelf="Low Shelf", highShelf="High Shelf", highPass="High Pass", lowPass="Low Pass" }
struct EQBand:Equatable {
    var kind:FilterKind
    var frequency:Double
    var gain:Double
    var q:Double
}
struct EQState:Equatable {
    var enabled:Bool, dual:Bool, btEnabled:Bool
    var left:[EQBand], right:[EQBand]
    var bass:EQBand, treble:EQBand
    static let gains=[4,7,10,13,17], frequencies=[5,8,11,14,18], qs=[6,9,12,15,19]
    init?(values:[Int:[Int:Int]],output:Int) {
        guard let l=values[output+1], let enabled=l[2], let bt=l[20], let dual=values[output]?[11] else { return nil }
        func bands(_ v:[Int:Int])->[EQBand]? {
            var result:[EQBand]=[]
            for i in 0..<5 {
                guard let f=v[Self.frequencies[i]],let g=v[Self.gains[i]],let q=v[Self.qs[i]] else { return nil }
                var kind=FilterKind.peak
                if i==0 { guard let t=v[3], (0...3).contains(t) else { return nil }; kind=[.peak,.lowShelf,.highPass,.lowPass][t] }
                if i==4 { guard let t=v[16], (0...2).contains(t) else { return nil }; kind=[.peak,.highShelf,.lowPass][t] }
                result.append(EQBand(kind:kind,frequency:Double(f),gain:Double(g)/2,q:Double(q)/10))
            }
            return result
        }
        guard let left=bands(l), let bg=l[21],let bf=l[22],let bq=l[23],let tg=l[24],let tf=l[25],let tq=l[26] else { return nil }
        let right=values[output+2].flatMap(bands)
        guard dual==0 || right != nil else { return nil }
        self.enabled=enabled==1; self.dual=dual==1; self.btEnabled=bt==1
        self.left=left; self.right=right ?? left
        bass=EQBand(kind:.lowShelf,frequency:Double(bf),gain:Double(bg)/2,q:Double(bq)/10)
        treble=EQBand(kind:.highShelf,frequency:Double(tf),gain:Double(tg)/2,q:Double(tq)/10)
    }
    func parameters(output:Int)throws->[RMEParameter] {
        var result=[RMEParameter(channel:output,index:11,value:dual ? 1 : 0),RMEParameter(channel:output+1,index:2,value:enabled ? 1 : 0),RMEParameter(channel:output+1,index:20,value:btEnabled ? 1 : 0)]
        func add(_ a:Int,_ i:Int,_ v:Double,_ scale:Double=1)throws {
            guard v.isFinite, abs(v*scale)<Double(Int.max/2) else { throw BridgeError.message(L("EQ 參數必須是有限數值", "EQ parameters must be finite numbers")) }
            let p=RMEParameter(channel:a,index:i,value:Int((v*scale).rounded()))
            guard RMEProtocol.valid(p) else { throw BridgeError.message(L("EQ 參數超出 DAC 支援範圍（參數 \(i)）", "EQ parameter out of range (parameter \(i))")) }
            result.append(p)
        }
        for (address,bands) in [(output+1,left),(output+2,right)] {
            if address==output+2 && !dual { continue }
            guard bands.count==5 else { throw BridgeError.message(L("需要 5 個 EQ 頻段", "Five EQ bands are required")) }
            for i in 0..<5 {
                let b=bands[i]
                if i==0 {
                    guard let t=[FilterKind.peak,.lowShelf,.highPass,.lowPass].firstIndex(of:b.kind) else { throw BridgeError.message(L("第一頻段類型不支援", "Unsupported filter for band 1")) }
                    try add(address,3,Double(t))
                } else if i==4 {
                    guard let t=[FilterKind.peak,.highShelf,.lowPass].firstIndex(of:b.kind) else { throw BridgeError.message(L("第五頻段類型不支援", "Unsupported filter for band 5")) }
                    try add(address,16,Double(t))
                } else if b.kind != .peak { throw BridgeError.message(L("第二至第四頻段僅支援 Peak", "Bands 2–4 support Peak filters only")) }
                try add(address,Self.gains[i],b.gain,2); try add(address,Self.frequencies[i],b.frequency); try add(address,Self.qs[i],b.q,10)
            }
        }
        try add(output+1,21,bass.gain,2); try add(output+1,22,bass.frequency); try add(output+1,23,bass.q,10)
        try add(output+1,24,treble.gain,2); try add(output+1,25,treble.frequency); try add(output+1,26,treble.q,10)
        return result
    }
    /// The same EQ written into the DAC's preset buffers (address 13 left + Bass/Treble, 14 right).
    /// Ends with the flag word, which makes the device store everything it received into `number`.
    func presetParameters(number:Int)throws->[[RMEParameter]] {
        // Ranges are identical to a live output, so validate as Line Out and move addresses 4/5 to 13/14.
        let output=try parameters(output:3).filter { ($0.channel == 4 || $0.channel == 5) && $0.index != 2 }
        let left=output.filter { $0.channel == 4 }.map { RMEParameter(channel:13,index:$0.index,value:$0.value) }
        let right=output.filter { $0.channel == 5 }.map { RMEParameter(channel:14,index:$0.index,value:$0.value) }
        var batches=[left]
        if dual { batches.append(right) }
        batches.append([RMEParameter(channel:13,index:1,value:RMEProtocol.presetFlag(number:number,dual:dual))])
        return batches
    }
    func response(frequency:Double,rightChannel:Bool=false,sampleRate:Double=44100)->Double {
        var result:Double=0
        if enabled { for b in rightChannel && dual ? right : left { result += EQResponse.decibels(b,at:frequency,sampleRate:sampleRate) } }
        if btEnabled { result += EQResponse.decibels(bass,at:frequency,sampleRate:sampleRate)+EQResponse.decibels(treble,at:frequency,sampleRate:sampleRate) }
        return result
    }
}
// RBJ biquad visualization only. The DAC performs DSP; its exact response may differ.
enum EQResponse {
    static func decibels(_ band:EQBand,at frequency:Double,sampleRate:Double)->Double {
        guard sampleRate>0, band.q>0, band.frequency>0, frequency>0 else { return 0 }
        let f=min(sampleRate*0.499,band.frequency), omega=2*Double.pi*f/sampleRate
        let c=cos(omega), s=sin(omega), alpha=s/(2*band.q), a=pow(10,band.gain/40), root=sqrt(a)
        var b0:Double=1,b1:Double=0,b2:Double=0,a0:Double=1,a1:Double=0,a2:Double=0
        switch band.kind {
        case .peak: b0=1+alpha*a; b1 = -2*c; b2=1-alpha*a; a0=1+alpha/a; a1 = -2*c; a2=1-alpha/a
        case .lowPass: b0=(1-c)/2; b1=1-c; b2=b0; a0=1+alpha; a1 = -2*c; a2=1-alpha
        case .highPass: b0=(1+c)/2; b1 = -(1+c); b2=b0; a0=1+alpha; a1 = -2*c; a2=1-alpha
        case .lowShelf:
            b0=a*((a+1)-(a-1)*c+2*root*alpha); b1=2*a*((a-1)-(a+1)*c); b2=a*((a+1)-(a-1)*c-2*root*alpha)
            a0=(a+1)+(a-1)*c+2*root*alpha; a1 = -2*((a-1)+(a+1)*c); a2=(a+1)+(a-1)*c-2*root*alpha
        case .highShelf:
            b0=a*((a+1)+(a-1)*c+2*root*alpha); b1 = -2*a*((a-1)+(a+1)*c); b2=a*((a+1)+(a-1)*c-2*root*alpha)
            a0=(a+1)-(a-1)*c+2*root*alpha; a1=2*((a-1)-(a+1)*c); a2=(a+1)-(a-1)*c-2*root*alpha
        }
        let w=2*Double.pi*min(frequency,sampleRate*0.499)/sampleRate
        let numerator=pow(b0+b1*cos(w)+b2*cos(2*w),2)+pow(b1*sin(w)+b2*sin(2*w),2)
        let denominator=pow(a0+a1*cos(w)+a2*cos(2*w),2)+pow(a1*sin(w)+a2*sin(2*w),2)
        return 10*log10(max(1e-18,numerator)/max(1e-18,denominator))
    }
}
extension Bridge {
    var eqState:EQState? { EQState(values:values,output:channel) }
    func setEQEnabled(_ enabled:Bool)throws { try send([RMEParameter(channel:eqAddress,index:2,value:enabled ? 1 : 0)]) }
    func setBTEnabled(_ enabled:Bool)throws { try send([RMEParameter(channel:eqAddress,index:20,value:enabled ? 1 : 0)]) }
    func selectPreset(_ number:Int)throws {
        guard (1...20).contains(number), !emptyPresets.contains(number) else { throw BridgeError.message(L("此 EQ 預設為空或尚未確認", "This EQ preset is empty or has not been confirmed")) }
        try send([RMEParameter(channel:eqAddress,index:28,value:number+1)])
    }
    func applyEQ(_ state:EQState)throws { try send(state.parameters(output:channel)) }
}
/// Starting-point curves derived from published listening research and common mixing practice, not from RME.
/// Each sets the five parametric bands only; Bass/Treble and the Loudness function are left as they are.
/// Boosts are kept small (≤ +6 dB) and most curves cut more than they boost to preserve headroom.
struct EQTemplate {
    let name:String, note:String
    let bands:[EQBand]
    private static func p(_ f:Double,_ g:Double,_ q:Double)->EQBand { EQBand(kind:.peak,frequency:f,gain:g,q:q) }
    private static func ls(_ f:Double,_ g:Double,_ q:Double = 0.7)->EQBand { EQBand(kind:.lowShelf,frequency:f,gain:g,q:q) }
    private static func hs(_ f:Double,_ g:Double,_ q:Double = 0.7)->EQBand { EQBand(kind:.highShelf,frequency:f,gain:g,q:q) }
    static var all:[EQTemplate] { [
        EQTemplate(name:L("平直（RME 預設）", "Flat (RME defaults)"),note:L("RME 出廠頻點，全部 0 dB", "RME factory frequencies, all 0 dB"),
                   bands:[p(100,0,1),p(500,0,1),p(1000,0,1),p(5000,0,1),p(10000,0,1)]),
        EQTemplate(name:L("Harman 風格低頻", "Harman-style bass"),note:L("Harman 研究偏好的約 +4.5 dB／105 Hz 低頻架", "≈ +4.5 dB shelf at 105 Hz preferred in Harman research"),
                   bands:[ls(105,4.5),p(500,0,1),p(1000,0,1),p(5000,0,1),p(10000,0,1)]),
        EQTemplate(name:L("小音量等響補償", "Low-volume loudness"),note:L("依 ISO 226 等響曲線補低頻與高頻；DAC 內建 Loudness 會隨音量自動調整，通常更好", "Bass and treble lift per ISO 226; the DAC's own Loudness adapts to volume and is usually better"),
                   bands:[ls(100,6),p(500,0,1),p(1000,0,1),p(3500,1,1),hs(8000,3)]),
        EQTemplate(name:L("女聲", "Female vocals"),note:L("減混濁、4 kHz 存在感、壓 7 kHz 齒音", "Less mud, 4 kHz presence, tamed 7 kHz sibilance"),
                   bands:[ls(100,-1.5),p(250,-1.5,1),p(1200,1,1),p(4000,2.5,1.2),p(7000,-1.5,3)]),
        EQTemplate(name:L("男聲", "Male vocals"),note:L("160 Hz 厚度、減 350 Hz 悶、3 kHz 清晰、壓 5 kHz 齒音", "160 Hz body, less 350 Hz boxiness, 3 kHz clarity, tamed 5 kHz sibilance"),
                   bands:[p(160,1.5,1),p(350,-1.5,1.2),p(1500,1,1),p(3000,2.5,1.2),p(5000,-1,3)]),
        EQTemplate(name:L("人聲前移", "Vocals forward"),note:L("退低頻、推 2–4 kHz 語音清晰帶", "Recessed bass, lifted 2–4 kHz intelligibility band"),
                   bands:[ls(120,-2),p(300,-1,1),p(2000,1.5,0.8),p(3500,2,1),hs(10000,-1)]),
        EQTemplate(name:L("語音／Podcast", "Speech / podcast"),note:L("切 80 Hz 以下、減混濁、加 3 kHz、壓齒音", "Cut below 80 Hz, less mud, 3 kHz lift, tamed sibilance"),
                   bands:[EQBand(kind:.highPass,frequency:80,gain:0,q:0.7),p(250,-2,1),p(1000,0,1),p(3000,2,1),p(7000,-1.5,3)]),
        EQTemplate(name:L("溫暖", "Warm"),note:L("低頻與低中頻略加、高頻略收", "A little more bass and low mids, softer treble"),
                   bands:[ls(120,2.5),p(250,1,0.8),p(1000,0,1),p(3000,-1,1),hs(8000,-2)]),
        EQTemplate(name:L("明亮清晰", "Bright and clear"),note:L("減低中頻、5 kHz 細節、10 kHz 空氣感", "Less low-mid, 5 kHz detail, 10 kHz air"),
                   bands:[ls(100,-1),p(300,-1.5,1),p(1000,0,1),p(5000,1.5,1),hs(10000,2.5)]),
        EQTemplate(name:L("低頻加強", "Bass boost"),note:L("80 Hz 低頻架 +5 dB，並減 250 Hz 避免混濁", "+5 dB shelf at 80 Hz with a 250 Hz cut against mud"),
                   bands:[ls(80,5),p(250,-1,1),p(1000,0,1),p(5000,0,1),p(10000,0,1)]),
        EQTemplate(name:L("V 型（流行／電子）", "V-shape (pop / electronic)"),note:L("低頻與高頻加、1 kHz 中頻略收", "Lifted lows and highs, slightly scooped 1 kHz"),
                   bands:[ls(90,3.5),p(500,0,1),p(1000,-1.5,0.7),p(5000,0,1),hs(9000,2.5)]),
        EQTemplate(name:L("減少刺耳", "Less harshness"),note:L("壓 3 kHz 與 6.5 kHz 齒音，高頻略收", "Tames 3 kHz and 6.5 kHz sibilance, softer top end"),
                   bands:[p(100,0,1),p(500,0,1),p(3000,-1.5,1.5),p(6500,-3,2),hs(10000,-1.5)]),
    ] }
    /// ASCII names that fit a DAC preset, in the same order as `all`.
    static let presetNames=["Flat","Harman Bass","Loudness","Female Vox","Male Vox","Vocals Fwd","Speech","Warm","Bright","Bass Boost","V-Shape","Less Harsh"]
    /// Applies this curve to both channels; the EQ is switched on, everything else is kept.
    func applied(to state:EQState)->EQState {
        var s=state;s.left=bands;s.right=bands;s.enabled=true;return s
    }
}
