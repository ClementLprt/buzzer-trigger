import SwiftUI

struct OperationView: View {
    @EnvironmentObject var e: TriggerEngine

    private var statusText: String {
        if !e.running { return "ARRÊTÉ" }
        if e.calibrating != nil { return "MESURE EN COURS (\(e.calibrating!))" }
        if e.locked { return String(format: "VERROUILLÉ  %.0f s", e.lockRemaining) }
        return e.armed ? "PRÊT, ARMÉ" : "DÉSARMÉ"
    }
    private var statusColor: Color {
        if !e.running { return .gray }
        if e.calibrating != nil { return .blue }
        if e.locked { return .orange }
        return e.armed ? .green : .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Circle().fill(statusColor).frame(width: 28, height: 28)
                Text(statusText).font(.system(size: 26, weight: .bold))
                Spacer()
                if let t = e.lastTrigger {
                    Text("Dernier déclenchement : \(t.formatted(date: .omitted, time: .standard))")
                        .foregroundColor(.secondary)
                }
            }
            LevelMeter(level: e.level, threshold: e.threshold, idle: e.idleMax, press: e.pressAvg)
                .frame(height: 34)
            HStack {
                if e.running {
                    Button("Tout arrêter") { e.stop() }
                } else {
                    Button("Démarrer") { e.start() }.keyboardShortcut(.defaultAction)
                }
                Button(e.armed ? "Désarmer" : "Armer") { e.setArmed(!e.armed) }
                Button("Déclencher à la main") { e.trigger(source: "manuel") }
                Button("Fin de verrou") { e.endLock(rearm: true) }.disabled(!e.locked)
                Spacer()
                Button("Rafraîchir les périphériques") { e.refreshDevices() }
            }

            HStack(alignment: .top, spacing: 12) {
                GroupBox("1. Carte son") { SoundCardSettings().padding(6) }
                GroupBox("2. Détection") { DetectionSettings().padding(6) }
                GroupBox("3. MIDI") { MIDISettings().padding(6) }
            }

            GroupBox("Journal") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(e.log.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 120)
            }
        }
        .padding(8)
    }
}

struct LevelMeter: View {
    let level: Double, threshold: Double
    let idle: Double?, press: Double?
    private let minDb = -100.0

    private func x(_ db: Double, _ w: CGFloat) -> CGFloat {
        CGFloat((min(0, max(minDb, db)) - minDb) / -minDb) * w
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.75))
                RoundedRectangle(cornerRadius: 6)
                    .fill(level >= threshold ? Color.green : Color.blue)
                    .frame(width: x(level, w))
                Rectangle().fill(Color.red).frame(width: 3).offset(x: x(threshold, w) - 1)
                if let i = idle { Rectangle().fill(Color.gray).frame(width: 2, height: h * 0.6).offset(x: x(i, w)) }
                if let p = press { Rectangle().fill(Color.yellow).frame(width: 2, height: h * 0.6).offset(x: x(p, w)) }
                Text(String(format: "%.1f dB   (seuil %.0f dB)", level, threshold))
                    .font(.system(.body, design: .monospaced)).foregroundColor(.white).padding(.leading, 8)
            }
        }
    }
}

struct SoundCardSettings: View {
    @EnvironmentObject var e: TriggerEngine

    var body: some View {
        Form {
            Picker("Sortie (envoi)", selection: $e.outUID) {
                Text("Choisir…").tag("")
                ForEach(e.devices.filter { $0.outputChannels > 0 }) { d in
                    Text("\(d.name) (\(d.outputChannels) can.)").tag(d.uid)
                }
            }
            Picker("Canal de sortie", selection: $e.outChannel) {
                ForEach(1...max(1, e.outDevice?.outputChannels ?? 2), id: \.self) { Text("Sortie \($0)").tag($0) }
            }
            Picker("Entrée (retour)", selection: $e.inUID) {
                Text("Choisir…").tag("")
                ForEach(e.devices.filter { $0.inputChannels > 0 }) { d in
                    Text("\(d.name) (\(d.inputChannels) can.)").tag(d.uid)
                }
            }
            Picker("Canal d'entrée", selection: $e.inChannel) {
                ForEach(1...max(1, e.inDevice?.inputChannels ?? 2), id: \.self) { Text("Entrée \($0)").tag($0) }
            }
            Toggle("Envoyer le signal", isOn: $e.toneOn)
            Stepper(value: $e.toneHz, in: 100...2000, step: 50) { Text("Fréquence : \(Int(e.toneHz)) Hz") }
            Stepper(value: $e.toneDb, in: -30...0, step: 1) { Text("Niveau : \(Int(e.toneDb)) dBFS") }
        }
    }
}

struct DetectionSettings: View {
    @EnvironmentObject var e: TriggerEngine

    var body: some View {
        Form {
            Stepper(value: $e.threshold, in: -100...0, step: 1) { Text("Seuil : \(Int(e.threshold)) dB") }
            Stepper(value: $e.hysteresis, in: 1...30, step: 1) { Text("Hystérésis : \(Int(e.hysteresis)) dB") }
            Stepper(value: $e.holdMs, in: 0...500, step: 10) { Text("Appui mini : \(Int(e.holdMs)) ms") }
            Stepper(value: $e.lockSeconds, in: 0...1800, step: 5) { Text("Verrou : \(Int(e.lockSeconds)) s") }
            Toggle("Inverser (contact fermé au repos)", isOn: $e.invert)
            HStack {
                Button("Mesurer au repos") { e.calibrate("repos") }
                Button("Mesurer en appuyant") { e.calibrate("appui") }
            }.disabled(!e.running || e.calibrating != nil)
            if let a = e.idleMax, let b = e.pressAvg {
                let gap = abs(b - a)
                Text(String(format: "Écart repos/appui : %.0f dB", gap))
                    .foregroundColor(gap >= 20 ? .green : .red)
            }
        }
    }
}

struct MIDISettings: View {
    @EnvironmentObject var e: TriggerEngine

    var body: some View {
        Form {
            Picker("Sortie MIDI (QLab, MA)", selection: $e.midiDestination) {
                Text("Port virtuel « Buzzer Trigger »").tag(Int32(0))
                ForEach(e.midiDestinations) { d in Text(d.name).tag(d.id) }
            }
            Toggle("QLab", isOn: $e.qlabOn)
            Stepper(value: $e.qlabChannel, in: 1...16) { Text("  canal \(e.qlabChannel)") }
            Stepper(value: $e.qlabNote, in: 0...127) { Text("  note \(e.qlabNote)") }
            Toggle("grandMA3", isOn: $e.maOn)
            Stepper(value: $e.maChannel, in: 1...16) { Text("  canal \(e.maChannel)") }
            Stepper(value: $e.maNote, in: 0...127) { Text("  note \(e.maNote)") }
            Toggle("Laser (PC QuickShow)", isOn: $e.laserOn)
            Picker("  sortie laser", selection: $e.laserDestination) {
                Text("Port virtuel « Buzzer Trigger »").tag(Int32(0))
                ForEach(e.midiDestinations) { d in Text(d.name).tag(d.id) }
            }
            Stepper(value: $e.laserChannel, in: 1...16) { Text("  canal \(e.laserChannel)") }
            Stepper(value: $e.laserNote, in: 0...127) { Text("  note \(e.laserNote)") }
            Button("Envoyer un test MIDI") { e.sendTest() }
        }
    }
}
