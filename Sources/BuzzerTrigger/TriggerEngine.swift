import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

final class TriggerEngine: ObservableObject {
    // MARK: état affiché
    @Published var devices: [AudioDevice] = []
    @Published var midiDestinations: [MIDIDestination] = []
    @Published var running = false
    @Published var armed = true
    @Published var locked = false
    @Published var lockRemaining: Double = 0
    @Published var level: Double = -120
    @Published var calibrating: String? = nil
    @Published var idleMax: Double? = nil
    @Published var pressAvg: Double? = nil
    @Published var log: [String] = []
    @Published var lastTrigger: Date? = nil

    // MARK: réglages (sauvegardés)
    @Published var outUID: String = "" { didSet { save(); if running && oldValue != outUID { start() } } }
    @Published var outChannel: Int = 3 { didSet { save(); rtOutCh = outChannel - 1 } }
    @Published var inUID: String = "" { didSet { save(); if running && oldValue != inUID { start() } } }
    @Published var inChannel: Int = 1 { didSet { save(); rtInCh = inChannel - 1 } }
    @Published var toneHz: Double = 300 { didSet { save(); rtToneHz = toneHz } }
    @Published var toneDb: Double = -3 { didSet { save(); rtToneAmp = pow(10, min(0, toneDb) / 20) } }
    @Published var toneOn: Bool = true { didSet { save(); rtToneOn = toneOn } }
    @Published var threshold: Double = -30 { didSet { save(); rtThreshold = threshold } }
    @Published var hysteresis: Double = 6 { didSet { save(); rtHyst = hysteresis } }
    @Published var holdMs: Double = 40 { didSet { save(); rtHold = holdMs / 1000 } }
    @Published var lockSeconds: Double = 60 { didSet { save() } }
    @Published var invert: Bool = false { didSet { save(); rtInvert = invert } }
    @Published var midiDestination: Int32 = 0 { didSet { save() } }
    @Published var qlabOn = true { didSet { save() } }
    @Published var qlabChannel = 1 { didSet { save() } }
    @Published var qlabNote = 60 { didSet { save() } }
    @Published var maOn = true { didSet { save() } }
    @Published var maChannel = 2 { didSet { save() } }
    @Published var maNote = 60 { didSet { save() } }
    @Published var laserOn = false { didSet { save() } }
    @Published var laserChannel = 3 { didSet { save() } }
    @Published var laserNote = 60 { didSet { save() } }
    @Published var laserDestination: Int32 = 0 { didSet { save() } }
    @Published var panicNote = 127 { didSet { save() } }

    // MARK: copies lues par les threads audio
    private var rtOutCh = 2
    private var rtInCh = 0
    private var rtToneHz = 300.0
    private var rtToneAmp = 0.708
    private var rtToneOn = true
    private var rtThreshold = -30.0
    private var rtHyst = 6.0
    private var rtHold = 0.04
    private var rtInvert = false
    private var rtArmed = true      // armé et pas verrouillé
    private var phase = 0.0
    private var outSampleRate = 48000.0
    private var aboveSince: Double? = nil
    private var latched = false

    private var outEngine: AVAudioEngine?
    private var inEngine: AVAudioEngine?
    private var lockTimer: Timer?
    private var calibValues: [Double] = []
    private var activity: NSObjectProtocol?
    private let midi = MIDIOut()
    private var loading = true

    init() {
        load()
        loading = false
        refreshDevices()
        if !midi.ready { addLog("Erreur : impossible de créer le port MIDI virtuel") }
        watchDeviceChanges()
    }

    /// Met à jour la liste dès qu'une carte son est branchée ou débranchée.
    private func watchDeviceChanges() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main) { [weak self] _, _ in
            guard let self = self else { return }
            let before = Set(self.devices.map { $0.uid })
            self.refreshDevices()
            let after = self.devices
            for d in after where !before.contains(d.uid) { self.addLog("Branché : \(d.name)") }
            let afterUIDs = Set(after.map { $0.uid })
            if self.running && (!afterUIDs.contains(self.outUID) || !afterUIDs.contains(self.inUID)) {
                self.addLog("ATTENTION : la carte son utilisée a été débranchée")
            }
        }
    }

    // MARK: réglages
    private let defaults = UserDefaults.standard
    private func save() {
        guard !loading else { return }
        let d: [String: Any] = [
            "outUID": outUID, "outChannel": outChannel, "inUID": inUID, "inChannel": inChannel,
            "toneHz": toneHz, "toneDb": toneDb, "toneOn": toneOn, "threshold": threshold,
            "hysteresis": hysteresis, "holdMs": holdMs, "lockSeconds": lockSeconds, "invert": invert,
            "midiDestination": Int(midiDestination), "qlabOn": qlabOn, "qlabChannel": qlabChannel,
            "qlabNote": qlabNote, "maOn": maOn, "maChannel": maChannel, "maNote": maNote,
            "laserOn": laserOn, "laserChannel": laserChannel, "laserNote": laserNote,
            "laserDestination": Int(laserDestination), "panicNote": panicNote,
        ]
        defaults.set(d, forKey: "settings.v1")
    }

    private func load() {
        let d = defaults.dictionary(forKey: "settings.v1") ?? [:]
        outUID = d["outUID"] as? String ?? ""
        outChannel = d["outChannel"] as? Int ?? 3
        inUID = d["inUID"] as? String ?? ""
        inChannel = d["inChannel"] as? Int ?? 1
        toneHz = d["toneHz"] as? Double ?? 300
        toneDb = d["toneDb"] as? Double ?? -3
        toneOn = d["toneOn"] as? Bool ?? true
        threshold = d["threshold"] as? Double ?? -30
        hysteresis = d["hysteresis"] as? Double ?? 6
        holdMs = d["holdMs"] as? Double ?? 40
        lockSeconds = d["lockSeconds"] as? Double ?? 60
        invert = d["invert"] as? Bool ?? false
        midiDestination = Int32(d["midiDestination"] as? Int ?? 0)
        qlabOn = d["qlabOn"] as? Bool ?? true
        qlabChannel = d["qlabChannel"] as? Int ?? 1
        qlabNote = d["qlabNote"] as? Int ?? 60
        maOn = d["maOn"] as? Bool ?? true
        maChannel = d["maChannel"] as? Int ?? 2
        maNote = d["maNote"] as? Int ?? 60
        laserOn = d["laserOn"] as? Bool ?? false
        laserChannel = d["laserChannel"] as? Int ?? 3
        laserNote = d["laserNote"] as? Int ?? 60
        laserDestination = Int32(d["laserDestination"] as? Int ?? 0)
        panicNote = d["panicNote"] as? Int ?? 127
    }

    // MARK: journal
    func addLog(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        log.insert("\(f.string(from: Date()))  \(text)", at: 0)
        if log.count > 300 { log.removeLast(log.count - 300) }
    }

    // MARK: périphériques
    func refreshDevices() {
        devices = AudioDevices.all()
        midiDestinations = MIDIOut.destinations()
        addLog("Cartes son vues : " + devices.map { "\($0.name) (\($0.inputChannels) ent./\($0.outputChannels) sort.)" }.joined(separator: ", "))
        if outUID.isEmpty, let d = devices.first(where: { $0.outputChannels > 2 }) ?? devices.first(where: { $0.outputChannels > 0 }) { outUID = d.uid }
        if inUID.isEmpty, let d = devices.first(where: { $0.uid == outUID && $0.inputChannels > 0 }) ?? devices.first(where: { $0.inputChannels > 0 }) { inUID = d.uid }
    }

    var outDevice: AudioDevice? { devices.first { $0.uid == outUID } }
    var inDevice: AudioDevice? { devices.first { $0.uid == inUID } }

    // MARK: démarrage / arrêt
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted { self.start() } else { self.addLog("Accès micro refusé : Réglages Système > Confidentialité et sécurité > Micro > Buzzer Trigger") }
                }
            }
            return
        case .denied, .restricted:
            addLog("Accès micro refusé : Réglages Système > Confidentialité et sécurité > Micro > Buzzer Trigger")
            return
        default: break
        }
        stopAudio()
        refreshDevices()
        guard let out = outDevice else { addLog("Choisis une sortie de carte son"); return }
        guard let inp = inDevice else { addLog("Choisis une entrée de carte son"); return }
        do {
            try startOutput(out)
            try startInput(inp)
            running = true
            if activity == nil {
                activity = ProcessInfo.processInfo.beginActivity(
                    options: [.userInitiated, .idleSystemSleepDisabled, .latencyCritical],
                    reason: "Buzzer Trigger en exploitation")
            }
            addLog("Démarré : sortie \(out.name) canal \(outChannel), entrée \(inp.name) canal \(inChannel)")
        } catch {
            stopAudio()
            addLog("Erreur audio : \(error.localizedDescription)")
        }
    }

    func stop() {
        stopAudio()
        endLock(rearm: false)
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        addLog("Arrêté")
    }

    private func stopAudio() {
        inEngine?.inputNode.removeTap(onBus: 0)
        inEngine?.stop()
        outEngine?.stop()
        inEngine = nil
        outEngine = nil
        running = false
        level = -120
    }

    private struct AudioError: LocalizedError {
        let errorDescription: String?
        init(_ s: String) { errorDescription = s }
    }

    private func setDevice(_ node: AVAudioIONode, _ id: AudioDeviceID) throws {
        guard let au = node.audioUnit else { throw AudioError("unité audio introuvable") }
        var dev = id
        let st = AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                      &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
        if st != noErr { throw AudioError("impossible de sélectionner le périphérique (code \(st))") }
    }

    private func makeFormat(sampleRate: Double, channels: AVAudioChannelCount) -> AVAudioFormat? {
        if channels <= 2 {
            return AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false)
        }
        guard let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)) else { return nil }
        return AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, interleaved: false, channelLayout: layout)
    }

    private func startOutput(_ device: AudioDevice) throws {
        let engine = AVAudioEngine()
        let output = engine.outputNode
        try setDevice(output, device.id)
        let hw = output.outputFormat(forBus: 0)
        guard hw.sampleRate > 0, hw.channelCount > 0 else { throw AudioError("sortie \(device.name) indisponible") }
        guard let fmt = makeFormat(sampleRate: hw.sampleRate, channels: hw.channelCount) else { throw AudioError("format de sortie non géré") }
        outSampleRate = hw.sampleRate
        if outChannel > Int(hw.channelCount) { outChannel = Int(hw.channelCount) }
        let source = AVAudioSourceNode(format: fmt) { [unowned self] _, _, frameCount, bufferList -> OSStatus in
            self.render(frameCount: Int(frameCount), bufferList: bufferList)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: output, format: fmt)
        engine.prepare()
        try engine.start()
        outEngine = engine
    }

    private func render(frameCount: Int, bufferList: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        for b in buffers {
            if let p = b.mData { memset(p, 0, Int(b.mDataByteSize)) }
        }
        let inc = 2 * Double.pi * rtToneHz / outSampleRate
        let ch = rtOutCh
        guard rtToneOn, ch >= 0, ch < buffers.count, let p = buffers[ch].mData else {
            phase = 0
            return
        }
        let samples = p.assumingMemoryBound(to: Float.self)
        let amp = rtToneAmp
        var ph = phase
        for i in 0..<frameCount {
            samples[i] = Float(amp * sin(ph))
            ph += inc
            if ph > 2 * Double.pi { ph -= 2 * Double.pi }
        }
        phase = ph
    }

    private func startInput(_ device: AudioDevice) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        try setDevice(input, device.id)
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else { throw AudioError("entrée \(device.name) indisponible") }
        if inChannel > Int(fmt.channelCount) { inChannel = Int(fmt.channelCount) }
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // Certains Mac refusent un moteur sans sortie : on ajoute un mixeur muet.
            engine.mainMixerNode.outputVolume = 0
            engine.connect(input, to: engine.mainMixerNode, format: fmt)
            engine.prepare()
            try engine.start()
        }
        inEngine = engine
    }

    // MARK: détection (Goertzel sur la fréquence exacte du signal)
    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let channels = Int(buffer.format.channelCount)
        let n = Int(buffer.frameLength)
        guard n > 0, channels > 0 else { return }
        let ch = min(max(rtInCh, 0), channels - 1)
        let interleaved = buffer.format.isInterleaved
        let base = interleaved ? data[0] : data[ch]
        let stride = interleaved ? channels : 1
        let offset = interleaved ? ch : 0

        let w = 2 * Double.pi * rtToneHz / buffer.format.sampleRate
        let c = 2 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for i in 0..<n {
            let s = Double(base[i * stride + offset]) + c * s1 - s2
            s2 = s1
            s1 = s
        }
        let power = s1 * s1 + s2 * s2 - c * s1 * s2
        let amp = 2 * sqrt(max(power, 0)) / Double(n)
        let lvl = 20 * log10(amp + 1e-9)

        let now = ProcessInfo.processInfo.systemUptime
        let pressed = rtInvert ? (lvl <= rtThreshold) : (lvl >= rtThreshold)
        let released = rtInvert ? (lvl > rtThreshold + rtHyst) : (lvl < rtThreshold - rtHyst)
        var fire = false
        if pressed {
            if aboveSince == nil { aboveSince = now }
            if !latched, rtArmed, let t = aboveSince, now - t >= rtHold {
                latched = true
                rtArmed = false
                fire = true
            }
        } else if released {
            aboveSince = nil
            latched = false
        }

        DispatchQueue.main.async {
            self.level = lvl
            if self.calibrating != nil { self.calibValues.append(lvl) }
            if fire { self.trigger(source: "buzzer") }
        }
    }

    // MARK: déclenchement
    func trigger(source: String) {
        rtArmed = false
        guard armed, !locked else {
            addLog("Appui ignoré (\(locked ? "verrou en cours" : "désarmé"))")
            return
        }
        let parts = sendAll()
        lastTrigger = Date()
        addLog("DÉCLENCHÉ (\(source)) : " + (parts.isEmpty ? "aucune sortie MIDI cochée" : parts.joined(separator: ", ")))
        beginLock()
    }

    /// Une sortie MIDI : (libellé, canal, note, destination).
    private func targets() -> [(String, Int, Int, Int32)] {
        var t: [(String, Int, Int, Int32)] = []
        if qlabOn { t.append(("QLab", qlabChannel, qlabNote, midiDestination)) }
        if maOn { t.append(("MA", maChannel, maNote, midiDestination)) }
        if laserOn { t.append(("Laser", laserChannel, laserNote, laserDestination)) }
        return t
    }

    /// Envoie Note On à chaque sortie cochée, puis Note Off 150 ms après.
    @discardableResult
    private func sendAll() -> [String] {
        let t = targets()
        var parts: [String] = []
        for (label, ch, n, dest) in t {
            let ok = midi.note(channel: ch, note: n, on: true, destination: dest)
            parts.append("\(label) can.\(ch) note \(n)\(ok ? "" : " ÉCHEC")")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            for (_, ch, n, dest) in t { _ = self.midi.note(channel: ch, note: n, on: false, destination: dest) }
        }
        return parts
    }

    /// PANIC : désarme, coupe le verrou, envoie la note panic + All Notes Off à chaque sortie cochée.
    func panic() {
        setArmed(false)
        endLock(rearm: false)
        let t = targets()
        let note = panicNote
        var parts: [String] = []
        for (label, ch, _, dest) in t {
            let ok = midi.note(channel: ch, note: note, on: true, destination: dest)
            parts.append("\(label) can.\(ch) note \(note)\(ok ? "" : " ÉCHEC")")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            for (_, ch, _, dest) in t {
                _ = self.midi.note(channel: ch, note: note, on: false, destination: dest)
                let c = UInt8(max(1, min(16, ch)) - 1)
                _ = self.midi.send([0xB0 | c, 123, 0], destination: dest)
            }
        }
        addLog("PANIC : buzzer désarmé, " + (parts.isEmpty ? "aucune sortie cochée" : parts.joined(separator: ", ")))
    }

    func sendTest() {
        let parts = sendAll()
        addLog("Test MIDI envoyé (sans verrou) : " + (parts.isEmpty ? "aucune sortie cochée" : parts.joined(separator: ", ")))
    }

    private func beginLock() {
        lockTimer?.invalidate()
        locked = true
        lockRemaining = lockSeconds
        let end = Date().addingTimeInterval(lockSeconds)
        lockTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            self.lockRemaining = max(0, end.timeIntervalSinceNow)
            if self.lockRemaining <= 0 { self.endLock(rearm: true) }
        }
    }

    func endLock(rearm: Bool) {
        lockTimer?.invalidate()
        lockTimer = nil
        let wasLocked = locked
        locked = false
        lockRemaining = 0
        rtArmed = armed
        if wasLocked && rearm { addLog("Fin du verrou, prêt") }
    }

    func setArmed(_ value: Bool) {
        armed = value
        rtArmed = value && !locked
        addLog(value ? "Armé" : "Désarmé")
    }

    // MARK: calibration
    func calibrate(_ mode: String) {
        guard running else { addLog("Démarre d'abord l'audio"); return }
        calibValues = []
        calibrating = mode
        let wasArmed = armed
        rtArmed = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let v = self.calibValues
            self.calibrating = nil
            self.rtArmed = wasArmed && !self.locked
            guard !v.isEmpty else { self.addLog("Calibration : aucun signal reçu"); return }
            if mode == "repos" {
                self.idleMax = v.max()
                self.addLog(String(format: "Repos : max %.1f dB", self.idleMax!))
            } else {
                self.pressAvg = v.reduce(0, +) / Double(v.count)
                self.addLog(String(format: "Appui : moyenne %.1f dB", self.pressAvg!))
            }
            if let a = self.idleMax, let b = self.pressAvg {
                self.threshold = ((a + b) / 2).rounded()
                self.invert = b < a
                let gap = abs(b - a)
                self.addLog(String(format: "Seuil réglé à %.0f dB, écart %.0f dB%@", self.threshold, gap,
                                   gap < 20 ? " : TROP FAIBLE, voir le tuto" : " : OK"))
            }
        }
    }
}
