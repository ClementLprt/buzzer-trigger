import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import os

// Moteur de diffusion : un seul AVAudioEngine sur la carte de diffusion (CQ12T...),
// toutes les pistes sont lues en streaming et mixées à la main dans le rendu,
// ce qui permet d'envoyer chaque zone sur les canaux de sortie voulus.

/// Petit verrou pour les échanges entre le thread audio, le thread de lecture fichier et l'interface.
final class Lock {
    private let p: UnsafeMutablePointer<os_unfair_lock>
    init() {
        p = .allocate(capacity: 1)
        p.initialize(to: os_unfair_lock())
    }
    deinit { p.deallocate() }
    @inline(__always) func lock() { os_unfair_lock_lock(p) }
    @inline(__always) func unlock() { os_unfair_lock_unlock(p) }
    @inline(__always) func run<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(p)
        defer { os_unfair_lock_unlock(p) }
        return body()
    }
}

/// Tampon circulaire stéréo (un écrivain : le thread fichier, un lecteur : le rendu audio).
final class Ring {
    let capacity: Int
    private let data: UnsafeMutablePointer<Float>
    private var readPos = 0
    private var writePos = 0
    private let lock = Lock()

    init(frames: Int) {
        capacity = max(4096, frames)
        data = .allocate(capacity: capacity * 2)
        data.initialize(repeating: 0, count: capacity * 2)
    }
    deinit { data.deallocate() }

    var available: Int { lock.run { writePos - readPos } }
    var free: Int { capacity - available }

    func write(left: UnsafePointer<Float>, right: UnsafePointer<Float>, count: Int) -> Int {
        let (r, w) = lock.run { (readPos, writePos) }
        let n = min(count, capacity - (w - r))
        guard n > 0 else { return 0 }
        var idx = w % capacity
        for i in 0..<n {
            data[idx * 2] = left[i]
            data[idx * 2 + 1] = right[i]
            idx += 1
            if idx == capacity { idx = 0 }
        }
        lock.run { writePos += n }
        return n
    }

    func read(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, count: Int) -> Int {
        let (r, w) = lock.run { (readPos, writePos) }
        let n = min(count, w - r)
        guard n > 0 else { return 0 }
        var idx = r % capacity
        for i in 0..<n {
            left[i] = data[idx * 2]
            right[i] = data[idx * 2 + 1]
            idx += 1
            if idx == capacity { idx = 0 }
        }
        lock.run { readPos += n }
        return n
    }
}

/// Réglages d'une zone lus par le rendu audio.
final class ZoneState {
    var left = 0          // canal de sortie (0 = premier), -1 = aucun
    var right = 1         // -1 = zone mono (tout sur left)
    var gain: Float = 1
    var muted = false
    var duck: Float = 1   // baisse pendant le son du buzzer
    var peak: Float = 0   // crête depuis la dernière lecture (vu-mètre)
}

struct MarkerRT {
    let frame: Int        // position dans un passage de la piste, en échantillons de sortie
    let channel: Int
    let note: Int
    let destination: Int32
    let label: String
}

/// Une piste en cours de lecture.
final class Voice {
    let trackID: UUID
    let trackName: String
    let zone: ZoneState
    let ring: Ring
    let sampleRate: Double
    let loop: Bool
    let isBuzzer: Bool
    let iterationFrames: Int     // longueur d'un passage en échantillons de sortie
    let startFrame: Int          // décalage de départ (lecture depuis le curseur)

    var gain: Float              // volume de la piste (écrit par l'interface)
    var fadeTarget: Float = 1    // 0 = arrêt en fondu
    var rampSeconds: Float = 0.08

    // rendu audio
    fileprivate var current: Float = -1
    fileprivate let scratchL: UnsafeMutablePointer<Float>
    fileprivate let scratchR: UnsafeMutablePointer<Float>
    fileprivate static let scratchSize = 8192

    // compteurs partagés
    private let lock = Lock()
    private var consumed = 0
    private var _finished = false
    private var _eof = false
    private var _cancelled = false

    // file des marqueurs (accédés seulement sur la file des marqueurs)
    var markers: [MarkerRT]
    var lastAbs: Int

    init(trackID: UUID, trackName: String, zone: ZoneState, sampleRate: Double, loop: Bool, isBuzzer: Bool,
         fileFrames: Int64, fileRate: Double, startSeconds: Double, gain: Float, markers: [MarkerRT]) {
        self.trackID = trackID
        self.trackName = trackName
        self.zone = zone
        self.sampleRate = sampleRate
        self.loop = loop
        self.isBuzzer = isBuzzer
        self.gain = gain
        self.markers = markers
        ring = Ring(frames: Int(sampleRate * 3))
        iterationFrames = max(1, Int((Double(fileFrames) * sampleRate / max(1, fileRate)).rounded()))
        startFrame = max(0, min(iterationFrames - 1, Int(startSeconds * sampleRate)))
        lastAbs = startFrame - 1
        scratchL = .allocate(capacity: Voice.scratchSize)
        scratchR = .allocate(capacity: Voice.scratchSize)
        scratchL.initialize(repeating: 0, count: Voice.scratchSize)
        scratchR.initialize(repeating: 0, count: Voice.scratchSize)
    }

    deinit {
        scratchL.deallocate()
        scratchR.deallocate()
    }

    var finished: Bool { lock.run { _finished } }
    var eof: Bool { lock.run { _eof } }
    var cancelled: Bool { lock.run { _cancelled } }
    func markFinished() { lock.run { _finished = true; _cancelled = true } }
    fileprivate func markEOF() { lock.run { _eof = true } }
    fileprivate func advance(_ n: Int) { lock.run { consumed += n } }

    /// Position absolue (échantillons de sortie depuis le début de la piste, boucles comprises).
    var absoluteFrame: Int { lock.run { startFrame + consumed } }

    /// Position dans la piste, en secondes.
    var positionSeconds: Double {
        let a = absoluteFrame
        let p = loop ? a % iterationFrames : min(a, iterationFrames)
        return Double(p) / sampleRate
    }

    // MARK: lecture du fichier (thread dédié)
    func startFilling(file: AVAudioFile) {
        let t = Thread { [self] in self.fillLoop(file) }
        t.qualityOfService = .userInitiated
        t.name = "Lecture \(trackName)"
        t.start()
    }

    private func fillLoop(_ file: AVAudioFile) {
        let src = file.processingFormat
        let srcCh = Int(src.channelCount)
        let sameRate = abs(src.sampleRate - sampleRate) < 0.5
        let chunk: AVAudioFrameCount = 4096
        var converter: AVAudioConverter? = nil
        var outFmt = src
        if !sameRate {
            guard let f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                        channels: AVAudioChannelCount(min(max(srcCh, 1), 2)), interleaved: false),
                  let c = AVAudioConverter(from: src, to: f) else { markEOF(); return }
            outFmt = f
            converter = c
        }
        guard let out = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: chunk) else { markEOF(); return }
        file.framePosition = max(0, min(file.length - 1, AVAudioFramePosition(Double(startFrame) / sampleRate * src.sampleRate)))

        while !cancelled {
            if ring.free < Int(chunk) * 2 {
                usleep(4000)
                continue
            }
            var reachedEnd = false
            out.frameLength = 0
            if let conv = converter {
                var err: NSError?
                var sawEnd = false
                let status = conv.convert(to: out, error: &err) { _, st in
                    if sawEnd { st.pointee = .endOfStream; return nil }
                    guard let inb = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: chunk) else {
                        st.pointee = .endOfStream; return nil
                    }
                    do { try file.read(into: inb, frameCount: chunk) } catch { sawEnd = true; st.pointee = .endOfStream; return nil }
                    if inb.frameLength == 0 { sawEnd = true; st.pointee = .endOfStream; return nil }
                    st.pointee = .haveData
                    return inb
                }
                if status == .endOfStream || status == .error || sawEnd && out.frameLength == 0 { reachedEnd = true }
            } else {
                do { try file.read(into: out, frameCount: chunk) } catch { out.frameLength = 0 }
                if out.frameLength == 0 || file.framePosition >= file.length { reachedEnd = true }
            }

            let n = Int(out.frameLength)
            if n > 0, let d = out.floatChannelData {
                let l = d[0]
                let r = out.format.channelCount > 1 ? d[1] : d[0]
                var written = 0
                while written < n && !cancelled {
                    written += ring.write(left: l + written, right: r + written, count: n - written)
                    if written < n { usleep(3000) }
                }
            }
            if reachedEnd {
                if loop {
                    file.framePosition = 0
                    converter?.reset()
                } else {
                    markEOF()
                    return
                }
            }
        }
    }
}

final class SoundEngine {
    private(set) var running = false
    private(set) var channels = 0
    private(set) var sampleRate = 48000.0
    private(set) var deviceName = ""

    private var engine: AVAudioEngine?
    private let lock = Lock()
    private var rtVoices: [Voice] = []
    private var zones: [UUID: ZoneState] = [:]

    let markerQueue = DispatchQueue(label: "fr.ohmylord.buzzertrigger.markers", qos: .userInteractive)
    private var markerTimer: DispatchSourceTimer?
    /// Appelé sur la file des marqueurs quand un marqueur part.
    var onMarker: ((Voice, MarkerRT) -> Void)?

    struct EngineError: LocalizedError {
        let errorDescription: String?
        init(_ s: String) { errorDescription = s }
    }

    // MARK: zones
    func zoneState(_ id: UUID) -> ZoneState {
        if let z = zones[id] { return z }
        let z = ZoneState()
        zones[id] = z
        return z
    }

    func update(zones list: [Zone]) {
        for z in list {
            let s = zoneState(z.id)
            let l = z.left - 1
            let r = z.right - 1
            s.left = (l >= 0 && (channels == 0 || l < channels)) ? l : -1
            s.right = (z.right > 0 && r != l && (channels == 0 || r < channels)) ? r : -1
            s.gain = Float(dbToLin(z.gainDb))
            s.muted = z.muted
        }
    }

    // MARK: voix
    var voices: [Voice] { lock.run { rtVoices } }

    func add(_ v: Voice) { lock.run { rtVoices.append(v) } }

    /// Retire les voix terminées et les renvoie.
    func reap() -> [Voice] {
        lock.run {
            let done = rtVoices.filter { $0.finished }
            if !done.isEmpty { rtVoices.removeAll { $0.finished } }
            return done
        }
    }

    func stopAllImmediately() {
        let vs = lock.run { () -> [Voice] in let v = rtVoices; rtVoices = []; return v }
        for v in vs { v.markFinished() }
    }

    // MARK: démarrage
    func start(device: AudioDevice) throws {
        stop()
        let engine = AVAudioEngine()
        let output = engine.outputNode
        guard let au = output.audioUnit else { throw EngineError("unité audio introuvable") }
        var dev = device.id
        let st = AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                      &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
        if st != noErr { throw EngineError("impossible de sélectionner \(device.name) (code \(st))") }
        let hw = output.outputFormat(forBus: 0)
        guard hw.sampleRate > 0, hw.channelCount > 0 else { throw EngineError("sortie \(device.name) indisponible") }
        guard let fmt = AudioDevices.format(sampleRate: hw.sampleRate, channels: hw.channelCount) else {
            throw EngineError("format de sortie non géré")
        }
        sampleRate = hw.sampleRate
        channels = Int(hw.channelCount)
        deviceName = device.name
        let source = AVAudioSourceNode(format: fmt) { [unowned self] _, _, frameCount, bufferList -> OSStatus in
            self.render(frames: Int(frameCount), bufferList: bufferList)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: output, format: fmt)
        engine.prepare()
        try engine.start()
        self.engine = engine
        running = true
        startMarkerTimer()
    }

    func stop() {
        markerTimer?.cancel()
        markerTimer = nil
        stopAllImmediately()
        engine?.stop()
        engine = nil
        running = false
    }

    // MARK: rendu (thread audio)
    private func render(frames n: Int, bufferList: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        for b in buffers {
            if let p = b.mData { memset(p, 0, Int(b.mDataByteSize)) }
        }
        let vs = lock.run { rtVoices }
        guard !vs.isEmpty else { return }
        let count = min(n, Voice.scratchSize)
        let sr = Float(sampleRate)

        for v in vs {
            if v.finished { continue }
            let got = v.ring.read(left: v.scratchL, right: v.scratchR, count: count)
            let z = v.zone
            var target = v.fadeTarget * v.gain * z.gain * (z.muted ? 0 : 1)
            if !v.isBuzzer { target *= z.duck }
            if v.current < 0 { v.current = target }
            let start = v.current
            let ramp = max(0.005, v.fadeTarget == 0 ? v.rampSeconds : 0.08)
            let maxDelta = Float(count) / (ramp * sr)
            var end = target
            if end > start + maxDelta { end = start + maxDelta } else if end < start - maxDelta { end = start - maxDelta }
            v.current = end

            if got > 0 {
                let step = (end - start) / Float(got)
                let l = z.left, r = z.right
                let lp: UnsafeMutablePointer<Float>? = (l >= 0 && l < buffers.count) ? buffers[l].mData?.assumingMemoryBound(to: Float.self) : nil
                let rp: UnsafeMutablePointer<Float>? = (r >= 0 && r < buffers.count) ? buffers[r].mData?.assumingMemoryBound(to: Float.self) : nil
                var g = start
                var peak: Float = 0
                for i in 0..<got {
                    g += step
                    let a = v.scratchL[i] * g
                    let b = v.scratchR[i] * g
                    if let lp = lp {
                        if let rp = rp {
                            lp[i] += a
                            rp[i] += b
                        } else {
                            lp[i] += 0.5 * (a + b)
                        }
                    } else if let rp = rp {
                        rp[i] += 0.5 * (a + b)
                    }
                    let m = max(abs(a), abs(b))
                    if m > peak { peak = m }
                }
                if peak > z.peak { z.peak = peak }
                v.advance(got)
            }
            if v.fadeTarget == 0 && end <= 0.0001 { v.markFinished() }
            else if got < count && v.eof && v.ring.available == 0 { v.markFinished() }
        }
    }

    // MARK: marqueurs MIDI (toutes les 5 ms)
    private func startMarkerTimer() {
        let t = DispatchSource.makeTimerSource(queue: markerQueue)
        t.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.checkMarkers() }
        t.resume()
        markerTimer = t
    }

    private func checkMarkers() {
        for v in voices {
            if v.finished || v.fadeTarget == 0 || v.markers.isEmpty { continue }
            let now = v.absoluteFrame
            let last = v.lastAbs
            guard now > last else { continue }
            v.lastAbs = now
            let len = v.iterationFrames
            let firstIt = v.loop ? max(0, last) / len : 0
            let lastIt = v.loop ? now / len : 0
            for m in v.markers {
                var it = firstIt
                while it <= lastIt {
                    let occ = it * len + m.frame
                    if occ > last && occ <= now { fire(m, voice: v) }
                    it += 1
                }
            }
        }
    }

    private func fire(_ m: MarkerRT, voice: Voice) {
        _ = MIDIOut.shared.note(channel: m.channel, note: m.note, on: true, destination: m.destination)
        markerQueue.asyncAfter(deadline: .now() + 0.15) {
            _ = MIDIOut.shared.note(channel: m.channel, note: m.note, on: false, destination: m.destination)
        }
        onMarker?(voice, m)
    }

    /// Remplace les marqueurs d'une voix en cours (depuis l'éditeur).
    func setMarkers(_ markers: [MarkerRT], for v: Voice) {
        markerQueue.async { v.markers = markers }
    }
}

func dbToLin(_ db: Double) -> Double { db <= -80 ? 0 : pow(10, db / 20) }
