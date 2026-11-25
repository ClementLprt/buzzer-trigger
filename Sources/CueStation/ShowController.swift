import AppKit
import AVFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Cœur de l'appli : le show (cues, sorties MIDI, zones, sons), l'exécution des cues et la diffusion.
final class ShowController: ObservableObject {
    @Published var show: Show { didSet { changed(from: oldValue) } }
    @Published var devices: [AudioDevice] = []
    @Published var midiDestinations: [MIDIDestination] = []
    @Published var running = false
    @Published var positions: [UUID: Double] = [:]    // son → position (s)
    @Published var levels: [UUID: Double] = [:]       // zone → crête (dBFS)
    @Published var peaks: [UUID: [Float]] = [:]       // son → forme d'onde
    @Published var ducking = false
    @Published var lastCue: (id: UUID, date: Date)?
    @Published var log: [String] = []

    let sound = SoundEngine()
    private var uiTimer: Timer?
    private var saveWork: DispatchWorkItem?
    private var computing: Set<UUID> = []
    private var pending: [DispatchWorkItem] = []

    private static func supportDir(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent(name, isDirectory: true)
    }

    private static var autoSaveURL: URL {
        let dir = supportDir("Cue Station")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("show.json")
    }

    init() {
        let legacy = ShowController.supportDir("Buzzer Trigger").appendingPathComponent("show.json")
        let data = (try? Data(contentsOf: ShowController.autoSaveURL)) ?? (try? Data(contentsOf: legacy))
        var s = data.flatMap { try? JSONDecoder().decode(Show.self, from: $0) } ?? .starter
        if s.outputs.isEmpty && s.cues.isEmpty {
            let st = Show.starter
            s.outputs = st.outputs
            s.cues = st.cues
            s.buzzerCueID = st.buzzerCueID
            s.panicCueID = st.panicCueID
        }
        if s.zones.isEmpty { s.zones = Show.starter.zones }
        show = s
        refreshDevices()
        sound.update(zones: show.zones)
        sound.onMarker = { [weak self] _, m in
            DispatchQueue.main.async { self?.go(m.cueID, from: "repère « \(m.label) »") }
        }
        uiTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.tick() }
    }

    // MARK: journal
    func addLog(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        log.insert("\(f.string(from: Date()))  \(text)", at: 0)
        if log.count > 400 { log.removeLast(log.count - 400) }
    }

    // MARK: sauvegarde
    private func changed(from old: Show) {
        sound.update(zones: show.zones)
        for v in sound.voices {
            guard let t = track(v.trackID) else { continue }
            v.gain = Float(dbToLin(t.gainDb))
            if let ot = old.tracks.first(where: { $0.id == t.id }), ot.markers != t.markers {
                sound.setMarkers(markersRT(t), for: v)
            }
        }
        saveWork?.cancel()
        let snapshot = show
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: ShowController.autoSaveURL, options: .atomic)
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Show Cue Station.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(show).write(to: url, options: .atomic)
            addLog("Show enregistré : \(url.lastPathComponent)")
        } catch {
            addLog("Erreur d'enregistrement : \(error.localizedDescription)")
        }
    }

    func openShow() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let s = try JSONDecoder().decode(Show.self, from: Data(contentsOf: url))
            stopAll(fade: 0.3)
            show = s
            addLog("Show ouvert : \(url.lastPathComponent)")
            let missing = s.tracks.filter { !FileManager.default.fileExists(atPath: $0.path) }
            if !missing.isEmpty { addLog("ATTENTION : sons introuvables : " + missing.map { $0.name }.joined(separator: ", ")) }
        } catch {
            addLog("Show illisible : \(error.localizedDescription)")
        }
    }

    // MARK: accès et bindings
    func track(_ id: UUID?) -> Track? { show.tracks.first { $0.id == id } }
    func zone(_ id: UUID?) -> Zone? { show.zones.first { $0.id == id } }
    func cue(_ id: UUID?) -> Cue? { show.cues.first { $0.id == id } }
    func output(_ id: UUID?) -> MIDIOutput? { show.outputs.first { $0.id == id } }

    func binding(_ id: UUID) -> Binding<Track> {
        Binding(
            get: { self.track(id) ?? .empty },
            set: { nv in if let i = self.show.tracks.firstIndex(where: { $0.id == id }) { self.show.tracks[i] = nv } })
    }

    func zoneBinding(_ id: UUID) -> Binding<Zone> {
        Binding(
            get: { self.zone(id) ?? Zone(name: "") },
            set: { nv in if let i = self.show.zones.firstIndex(where: { $0.id == id }) { self.show.zones[i] = nv } })
    }

    func cueBinding(_ id: UUID) -> Binding<Cue> {
        Binding(
            get: { self.cue(id) ?? Cue(name: "") },
            set: { nv in if let i = self.show.cues.firstIndex(where: { $0.id == id }) { self.show.cues[i] = nv } })
    }

    func outputBinding(_ id: UUID) -> Binding<MIDIOutput> {
        Binding(
            get: { self.output(id) ?? MIDIOutput(name: "") },
            set: { nv in if let i = self.show.outputs.firstIndex(where: { $0.id == id }) { self.show.outputs[i] = nv } })
    }

    func markerBinding(_ trackID: UUID, _ markerID: UUID) -> Binding<Marker> {
        Binding(
            get: { self.track(trackID)?.markers.first { $0.id == markerID } ?? Marker(time: 0) },
            set: { nv in
                guard let ti = self.show.tracks.firstIndex(where: { $0.id == trackID }),
                      let mi = self.show.tracks[ti].markers.firstIndex(where: { $0.id == markerID }) else { return }
                var m = nv
                m.time = max(0, min(self.show.tracks[ti].duration, m.time))
                self.show.tracks[ti].markers[mi] = m
            })
    }

    // MARK: cues
    func updateCue(_ id: UUID, _ change: (inout Cue) -> Void) {
        guard let i = show.cues.firstIndex(where: { $0.id == id }) else { return }
        change(&show.cues[i])
    }

    @discardableResult
    func addCue() -> UUID {
        var c = Cue(name: "Cue \(show.cues.count + 1)", color: Cue.colors[show.cues.count % Cue.colors.count])
        var a = CueAction(kind: .note)
        a.outputID = show.outputs.first?.id
        a.number = 60 + show.cues.count
        c.actions = [a]
        show.cues.append(c)
        return c.id
    }

    @discardableResult
    func duplicateCue(_ id: UUID) -> UUID? {
        guard var c = cue(id) else { return nil }
        c.id = UUID()
        c.name += " (copie)"
        c.actions = c.actions.map { var a = $0; a.id = UUID(); return a }
        if let i = show.cues.firstIndex(where: { $0.id == id }) { show.cues.insert(c, at: i + 1) } else { show.cues.append(c) }
        return c.id
    }

    func deleteCue(_ id: UUID) {
        show.cues.removeAll { $0.id == id }
        if show.buzzerCueID == id { show.buzzerCueID = nil }
        if show.panicCueID == id { show.panicCueID = nil }
        for ti in show.tracks.indices {
            for mi in show.tracks[ti].markers.indices where show.tracks[ti].markers[mi].cueID == id {
                show.tracks[ti].markers[mi].cueID = nil
            }
        }
    }

    func moveCue(_ id: UUID, by delta: Int) {
        guard let i = show.cues.firstIndex(where: { $0.id == id }) else { return }
        let j = max(0, min(show.cues.count - 1, i + delta))
        guard i != j else { return }
        let c = show.cues.remove(at: i)
        show.cues.insert(c, at: j)
    }

    /// Lance un cue : chaque action part après son délai.
    func go(_ id: UUID?, from origin: String) {
        guard let c = cue(id) else {
            if id != nil { addLog("Cue introuvable (\(origin))") }
            return
        }
        lastCue = (c.id, Date())
        var parts: [String] = []
        for a in c.actions {
            if a.delay <= 0 {
                parts.append(perform(a))
            } else {
                parts.append(String(format: "%@ à +%.1f s", describe(a), a.delay))
                let work = DispatchWorkItem { [weak self] in _ = self?.perform(a) }
                pending.append(work)
                DispatchQueue.main.asyncAfter(deadline: .now() + a.delay, execute: work)
            }
        }
        pending.removeAll { $0.isCancelled }
        addLog("GO « \(c.name) » (\(origin)) : " + (parts.isEmpty ? "aucune action" : parts.joined(separator: ", ")))
    }

    /// Exécute une action et renvoie un texte pour le journal.
    @discardableResult
    func perform(_ a: CueAction) -> String {
        let ch = UInt8(max(1, min(16, a.channel)) - 1)
        switch a.kind {
        case .note, .cc, .program:
            guard let o = output(a.outputID) else { return "\(a.kind.label) : sortie MIDI non choisie" }
            var ok = false
            switch a.kind {
            case .note:
                let n = UInt8(max(0, min(127, a.number))), v = UInt8(max(1, min(127, a.value)))
                ok = MIDIOut.shared.send([0x90 | ch, n, v], destination: o.destination)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    _ = MIDIOut.shared.send([0x80 | ch, n, 0], destination: o.destination)
                }
            case .cc:
                ok = MIDIOut.shared.send([0xB0 | ch, UInt8(max(0, min(127, a.number))), UInt8(max(0, min(127, a.value)))], destination: o.destination)
            default:
                ok = MIDIOut.shared.send([0xC0 | ch, UInt8(max(0, min(127, a.value)))], destination: o.destination)
            }
            return describe(a) + (ok ? "" : " ÉCHEC (sortie absente ?)")
        case .playSound:
            guard let t = track(a.trackID) else { return "son non choisi" }
            return play(t.id, ducks: a.duck) ? describe(a) : "« \(t.name) » ÉCHEC"
        case .stopSound:
            if let id = a.trackID { stop(id, fade: a.fade) }
            return describe(a)
        case .stopZone:
            if let id = a.zoneID { stopZone(id, fade: a.fade) }
            return describe(a)
        case .stopAll:
            stopAll(fade: a.fade)
            return describe(a)
        }
    }

    func describe(_ a: CueAction) -> String {
        switch a.kind {
        case .note: return "\(output(a.outputID)?.name ?? "?") can.\(a.channel) note \(a.number)"
        case .cc: return "\(output(a.outputID)?.name ?? "?") can.\(a.channel) CC\(a.number)=\(a.value)"
        case .program: return "\(output(a.outputID)?.name ?? "?") can.\(a.channel) PC \(a.value)"
        case .playSound: return "son « \(track(a.trackID)?.name ?? "?") »" + (a.duck ? " (baisse les zones)" : "")
        case .stopSound: return "stop « \(track(a.trackID)?.name ?? "?") »"
        case .stopZone: return "coupe la zone « \(zone(a.zoneID)?.name ?? "?") »"
        case .stopAll: return "tout couper"
        }
    }

    /// PANIC : annule les actions en attente, coupe les sons lancés par des cues (hors boucles),
    /// envoie All Notes Off sur chaque sortie et lance le cue PANIC choisi.
    func panic() {
        for w in pending { w.cancel() }
        pending = []
        for v in sound.voices where !v.loop {
            v.rampSeconds = 0.05
            v.fadeTarget = 0
        }
        applyDuck(false)
        for o in show.outputs {
            for c in 0..<16 { _ = MIDIOut.shared.send([0xB0 | UInt8(c), 123, 0], destination: o.destination) }
        }
        if let id = show.panicCueID { go(id, from: "PANIC") } else { addLog("PANIC : sons coupés, All Notes Off envoyé") }
    }

    // MARK: sorties MIDI
    func refreshMIDI() { midiDestinations = MIDIOut.destinations() }

    func destinationName(_ id: Int32) -> String {
        id == 0 ? "Port virtuel « \(MIDIOut.virtualName) »" : (midiDestinations.first { $0.id == id }?.name ?? "absente")
    }

    func testOutput(_ o: MIDIOutput) {
        let ok = MIDIOut.shared.send([0x90, 60, 127], destination: o.destination)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { _ = MIDIOut.shared.send([0x80, 60, 0], destination: o.destination) }
        addLog("Test « \(o.name) » : can.1 note 60" + (ok ? "" : " ÉCHEC"))
    }

    // MARK: sons
    func importTracks(done: @escaping ([UUID]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio]
        panel.message = "Choisis un ou plusieurs sons (wav, aiff, mp3, m4a...)"
        guard panel.runModal() == .OK else { return }
        var ids: [UUID] = []
        for url in panel.urls {
            do {
                let f = try AVAudioFile(forReading: url)
                let dur = Double(f.length) / f.fileFormat.sampleRate
                let t = Track(name: url.deletingPathExtension().lastPathComponent, path: url.path,
                              zoneID: show.zones.first?.id, loop: true, duration: dur)
                show.tracks.append(t)
                ids.append(t.id)
                addLog(String(format: "Son ajouté : %@ (%.1f s)", t.name, dur))
            } catch {
                addLog("Son illisible : \(url.lastPathComponent) (\(error.localizedDescription))")
            }
        }
        done(ids)
    }

    func removeTrack(_ id: UUID) {
        stop(id, fade: 0.1)
        show.tracks.removeAll { $0.id == id }
        peaks[id] = nil
    }

    func addMarker(_ trackID: UUID, at time: Double) {
        guard let i = show.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        var m = Marker(time: max(0, min(show.tracks[i].duration, time)))
        m.label = "Repère \(show.tracks[i].markers.count + 1)"
        m.cueID = show.tracks[i].markers.last?.cueID
        show.tracks[i].markers.append(m)
        show.tracks[i].markers.sort { $0.time < $1.time }
    }

    private func markersRT(_ t: Track) -> [MarkerRT] {
        let sr = sound.sampleRate
        return t.markers.sorted { $0.time < $1.time }.compactMap { m in
            guard let c = m.cueID else { return nil }
            return MarkerRT(frame: Int(m.time * sr), cueID: c, label: m.label)
        }
    }

    // MARK: forme d'onde
    func requestPeaks(_ t: Track) {
        guard peaks[t.id] == nil, !computing.contains(t.id) else { return }
        computing.insert(t.id)
        let id = t.id, path = t.path
        DispatchQueue.global(qos: .userInitiated).async {
            let p = ShowController.computePeaks(path: path, buckets: 4000)
            DispatchQueue.main.async {
                self.computing.remove(id)
                self.peaks[id] = p
            }
        }
    }

    private static func computePeaks(path: String, buckets: Int) -> [Float] {
        guard let f = try? AVAudioFile(forReading: URL(fileURLWithPath: path)), f.length > 0 else { return [] }
        let total = Int(f.length)
        let per = max(1, total / buckets)
        let n = min(buckets, total)
        var out = [Float](repeating: 0, count: n)
        let chunk: AVAudioFrameCount = 65536
        guard let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: chunk) else { return [] }
        var frame = 0
        while frame < total {
            do { try f.read(into: buf, frameCount: chunk) } catch { break }
            let len = Int(buf.frameLength)
            if len == 0 { break }
            guard let d = buf.floatChannelData else { break }
            let chs = Int(buf.format.channelCount)
            for i in 0..<len {
                let b = min(n - 1, (frame + i) / per)
                var m: Float = 0
                for c in 0..<min(chs, 2) { m = max(m, abs(d[c][i])) }
                if m > out[b] { out[b] = m }
            }
            frame += len
        }
        return out
    }

    // MARK: diffusion
    func refreshDevices() {
        devices = AudioDevices.all()
        refreshMIDI()
        if show.deviceUID.isEmpty, let d = devices.first(where: { $0.outputChannels > 2 }) ?? devices.first(where: { $0.outputChannels > 0 }) {
            show.deviceUID = d.uid
        }
    }

    var device: AudioDevice? { devices.first { $0.uid == show.deviceUID } }
    var channelCount: Int { sound.running ? sound.channels : (device?.outputChannels ?? 2) }

    func start() {
        refreshDevices()
        guard let d = device else { addLog("Diffusion : choisis la carte de sortie"); return }
        do {
            try sound.start(device: d)
            sound.update(zones: show.zones)
            running = true
            addLog(String(format: "Diffusion démarrée : %@, %d sorties, %.0f Hz", d.name, sound.channels, sound.sampleRate))
            for z in show.zones where z.left > sound.channels || z.right > sound.channels {
                addLog("ATTENTION : la zone « \(z.name) » vise une sortie absente (\(sound.channels) sorties)")
            }
        } catch {
            running = false
            addLog("Diffusion : erreur \(error.localizedDescription)")
        }
    }

    func stopEngine() {
        sound.stop()
        running = false
        ducking = false
        positions = [:]
        addLog("Diffusion arrêtée")
    }

    func startAutoplay() {
        if !sound.running { start() }
        let list = show.tracks.filter { $0.autoplay }
        if list.isEmpty { addLog("Aucun son coché « Au démarrage »"); return }
        for t in list where positions[t.id] == nil { play(t.id) }
    }

    @discardableResult
    func play(_ id: UUID, from: Double = 0, ducks: Bool = false) -> Bool {
        guard let t = track(id) else { return false }
        if !sound.running { start() }
        guard sound.running else { return false }
        guard let z = zone(t.zoneID) else { addLog("« \(t.name) » n'a pas de zone"); return false }
        stop(id, fade: 0.03)
        do {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: t.path))
            let v = Voice(trackID: t.id, trackName: t.name, zone: sound.zoneState(z.id), sampleRate: sound.sampleRate,
                          loop: t.loop, ducks: ducks, fileFrames: file.length,
                          fileRate: file.processingFormat.sampleRate, startSeconds: from,
                          gain: Float(dbToLin(t.gainDb)), markers: markersRT(t))
            v.startFilling(file: file)
            sound.add(v)
            if ducks { applyDuck(true) }
            return true
        } catch {
            addLog("Lecture impossible : \(t.name) (\(error.localizedDescription))")
            return false
        }
    }

    func stop(_ id: UUID, fade: Double = 0.3) {
        for v in sound.voices where v.trackID == id {
            v.rampSeconds = Float(max(0.01, fade))
            v.fadeTarget = 0
        }
    }

    func stopAll(fade: Double = 2) {
        for v in sound.voices {
            v.rampSeconds = Float(max(0.01, fade))
            v.fadeTarget = 0
        }
        applyDuck(false)
    }

    func stopZone(_ zoneID: UUID, fade: Double = 1) {
        for t in show.tracks where t.zoneID == zoneID { stop(t.id, fade: fade) }
    }

    private func applyDuck(_ on: Bool) {
        for z in show.zones {
            sound.zoneState(z.id).duck = (on && z.duckOnBuzzer) ? Float(dbToLin(z.duckDb)) : 1
        }
        ducking = on
    }

    // MARK: rafraîchissement de l'interface
    private func tick() {
        let done = sound.reap()
        if ducking && done.contains(where: { $0.ducks }) && !sound.voices.contains(where: { $0.ducks && $0.fadeTarget > 0 }) {
            applyDuck(false)
        }
        var pos: [UUID: Double] = [:]
        for v in sound.voices where !v.finished && v.fadeTarget > 0 { pos[v.trackID] = v.positionSeconds }
        if pos != positions { positions = pos }
        var lv: [UUID: Double] = [:]
        for z in show.zones {
            let s = sound.zoneState(z.id)
            let p = s.peak
            s.peak = 0
            let db = p > 0 ? 20 * log10(Double(p)) : -120
            let prev = levels[z.id] ?? -120
            lv[z.id] = max(db, prev - 3)
        }
        if lv != levels { levels = lv }
    }
}

func timeString(_ s: Double) -> String {
    let t = max(0, s)
    let m = Int(t) / 60
    let sec = t - Double(m * 60)
    return String(format: "%d:%06.3f", m, sec)
}

extension Color {
    static func cue(_ name: String) -> Color {
        switch name {
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "pink": return .pink
        case "teal": return .teal
        case "gray": return .gray
        default: return .blue
        }
    }
}
