import AppKit
import AVFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: modèle du show (sauvegardé en JSON)

struct Zone: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var left: Int = 1            // canal de sortie gauche (1 = premier)
    var right: Int = 2           // 0 = zone mono
    var gainDb: Double = 0
    var muted = false
    var duckOnBuzzer = true      // baisser cette zone pendant le son du buzzer
    var duckDb: Double = -15
}

struct Marker: Codable, Identifiable, Hashable {
    var id = UUID()
    var time: Double             // secondes depuis le début de la piste
    var label: String = ""
    var channel: Int = 2
    var note: Int = 61
    var destination: Int32 = 0   // 0 = port virtuel « Buzzer Trigger »
}

struct Track: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var path: String
    var zoneID: UUID?
    var loop = true
    var gainDb: Double = 0
    var autoplay = false
    var duration: Double = 0
    var markers: [Marker] = []

    static let empty = Track(name: "", path: "")
}

struct Show: Codable {
    var zones: [Zone]
    var tracks: [Track]
    var buzzerTrackID: UUID?
    var deviceUID: String = ""

    static var starter: Show {
        Show(zones: [
            Zone(name: "Zone 1", left: 1, right: 2),
            Zone(name: "Zone 2", left: 3, right: 4),
            Zone(name: "Zone 3", left: 5, right: 6),
        ], tracks: [], buzzerTrackID: nil)
    }
}

// MARK: contrôleur

final class ShowController: ObservableObject {
    @Published var show: Show { didSet { changed(from: oldValue) } }
    @Published var devices: [AudioDevice] = []
    @Published var running = false
    @Published var positions: [UUID: Double] = [:]    // piste → position (s)
    @Published var levels: [UUID: Double] = [:]       // zone → crête (dBFS)
    @Published var peaks: [UUID: [Float]] = [:]       // piste → forme d'onde
    @Published var buzzerPlaying = false
    @Published var showURL: URL?

    let sound = SoundEngine()
    var logger: ((String) -> Void)?
    private var uiTimer: Timer?
    private var saveWork: DispatchWorkItem?
    private var computing: Set<UUID> = []

    private static var autoSaveURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let dir = base.appendingPathComponent("Buzzer Trigger", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("show.json")
    }

    init() {
        if let data = try? Data(contentsOf: ShowController.autoSaveURL),
           let s = try? JSONDecoder().decode(Show.self, from: data) {
            show = s
        } else {
            show = .starter
        }
        refreshDevices()
        sound.update(zones: show.zones)
        sound.onMarker = { [weak self] voice, m in
            guard voice.isBuzzer else { return }
            let name = m.label.isEmpty ? "marqueur" : m.label
            DispatchQueue.main.async {
                self?.log("Marqueur « \(name) » : can.\(m.channel) note \(m.note)")
            }
        }
        uiTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.tick() }
    }

    func log(_ s: String) { logger?(s) }

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
        panel.nameFieldStringValue = "Show Buzzer Trigger.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(show).write(to: url, options: .atomic)
            showURL = url
            log("Show enregistré : \(url.lastPathComponent)")
        } catch {
            log("Erreur d'enregistrement : \(error.localizedDescription)")
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
            showURL = url
            log("Show ouvert : \(url.lastPathComponent)")
            let missing = s.tracks.filter { !FileManager.default.fileExists(atPath: $0.path) }
            if !missing.isEmpty { log("ATTENTION : fichiers introuvables : " + missing.map { $0.name }.joined(separator: ", ")) }
        } catch {
            log("Show illisible : \(error.localizedDescription)")
        }
    }

    // MARK: accès
    func track(_ id: UUID) -> Track? { show.tracks.first { $0.id == id } }
    func zone(_ id: UUID?) -> Zone? { show.zones.first { $0.id == id } }

    func binding(_ id: UUID) -> Binding<Track> {
        Binding(
            get: { self.track(id) ?? .empty },
            set: { nv in if let i = self.show.tracks.firstIndex(where: { $0.id == id }) { self.show.tracks[i] = nv } })
    }

    func zoneBinding(_ id: UUID) -> Binding<Zone> {
        Binding(
            get: { self.show.zones.first { $0.id == id } ?? Zone(name: "") },
            set: { nv in if let i = self.show.zones.firstIndex(where: { $0.id == id }) { self.show.zones[i] = nv } })
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

    // MARK: pistes
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
                log(String(format: "Son ajouté : %@ (%.1f s)", t.name, dur))
            } catch {
                log("Son illisible : \(url.lastPathComponent) (\(error.localizedDescription))")
            }
        }
        done(ids)
    }

    func removeTrack(_ id: UUID) {
        stop(id, fade: 0.1)
        show.tracks.removeAll { $0.id == id }
        if show.buzzerTrackID == id { show.buzzerTrackID = nil }
        peaks[id] = nil
    }

    func addMarker(_ trackID: UUID, at time: Double) {
        guard let i = show.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let existing = show.tracks[i].markers
        let lastNote = existing.max(by: { $0.note < $1.note })?.note
        var m = Marker(time: max(0, min(show.tracks[i].duration, time)))
        if let last = existing.last {
            m.channel = last.channel
            m.destination = last.destination
        }
        m.note = min(127, (lastNote ?? 60) + 1)
        m.label = "Cue \(existing.count + 1)"
        show.tracks[i].markers.append(m)
        show.tracks[i].markers.sort { $0.time < $1.time }
    }

    func testMarker(_ m: Marker) {
        _ = MIDIOut.shared.note(channel: m.channel, note: m.note, on: true, destination: m.destination)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            _ = MIDIOut.shared.note(channel: m.channel, note: m.note, on: false, destination: m.destination)
        }
        log("Test marqueur « \(m.label) » : can.\(m.channel) note \(m.note)")
    }

    private func markersRT(_ t: Track) -> [MarkerRT] {
        let sr = sound.sampleRate
        return t.markers.sorted { $0.time < $1.time }.map {
            MarkerRT(frame: Int($0.time * sr), channel: $0.channel, note: $0.note, destination: $0.destination, label: $0.label)
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
        if show.deviceUID.isEmpty, let d = devices.first(where: { $0.outputChannels > 2 }) ?? devices.first(where: { $0.outputChannels > 0 }) {
            show.deviceUID = d.uid
        }
    }

    var device: AudioDevice? { devices.first { $0.uid == show.deviceUID } }
    var channelCount: Int { sound.running ? sound.channels : (device?.outputChannels ?? 2) }

    func start() {
        refreshDevices()
        guard let d = device else { log("Diffusion : choisis la carte de sortie"); return }
        do {
            try sound.start(device: d)
            sound.update(zones: show.zones)
            running = true
            log(String(format: "Diffusion démarrée : %@, %d sorties, %.0f Hz", d.name, sound.channels, sound.sampleRate))
            for z in show.zones where z.left > sound.channels || z.right > sound.channels {
                log("ATTENTION : la zone « \(z.name) » vise une sortie absente (\(sound.channels) sorties)")
            }
        } catch {
            running = false
            log("Diffusion : erreur \(error.localizedDescription)")
        }
    }

    func stopEngine() {
        sound.stop()
        running = false
        buzzerPlaying = false
        positions = [:]
        log("Diffusion arrêtée")
    }

    func startAutoplay() {
        if !sound.running { start() }
        let list = show.tracks.filter { $0.autoplay }
        if list.isEmpty { log("Aucune piste « au démarrage » cochée"); return }
        for t in list where !isPlaying(t.id) { play(t.id) }
    }

    func isPlaying(_ id: UUID) -> Bool { sound.voices.contains { $0.trackID == id && !$0.finished && $0.fadeTarget > 0 } }

    @discardableResult
    func play(_ id: UUID, from: Double = 0, buzzer: Bool = false) -> Bool {
        guard let t = track(id) else { return false }
        if !sound.running { start() }
        guard sound.running else { return false }
        guard let z = zone(t.zoneID) else { log("« \(t.name) » n'a pas de zone"); return false }
        stop(id, fade: 0.03)
        do {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: t.path))
            let v = Voice(trackID: t.id, trackName: t.name, zone: sound.zoneState(z.id), sampleRate: sound.sampleRate,
                          loop: t.loop && !buzzer, isBuzzer: buzzer, fileFrames: file.length,
                          fileRate: file.processingFormat.sampleRate, startSeconds: from,
                          gain: Float(dbToLin(t.gainDb)), markers: markersRT(t))
            v.startFilling(file: file)
            sound.add(v)
            if buzzer { applyDuck(true) }
            return true
        } catch {
            log("Lecture impossible : \(t.name) (\(error.localizedDescription))")
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
        buzzerPlaying = on
    }

    /// Appelé par le buzzer. Renvoie un texte pour le journal.
    func buzzerFired() -> String? {
        guard let id = show.buzzerTrackID, let t = track(id) else { return nil }
        return play(id, buzzer: true) ? "son « \(t.name) »" : "son « \(t.name) » ÉCHEC"
    }

    /// PANIC : coupe le son du buzzer tout de suite et remonte les zones.
    func panicBuzzer() {
        for v in sound.voices where v.isBuzzer {
            v.rampSeconds = 0.05
            v.fadeTarget = 0
        }
        applyDuck(false)
    }

    // MARK: rafraîchissement de l'interface
    private func tick() {
        let done = sound.reap()
        if done.contains(where: { $0.isBuzzer }) && !sound.voices.contains(where: { $0.isBuzzer }) {
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
            lv[z.id] = max(db, prev - 3)   // retombée douce
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
