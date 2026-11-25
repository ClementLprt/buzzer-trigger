import SwiftUI

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
    @EnvironmentObject var e: BuzzerInput

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
    @EnvironmentObject var e: BuzzerInput

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

/// Onglet Réglages : sorties MIDI nommées et entrée buzzer.
struct SettingsView: View {
    @EnvironmentObject var s: ShowController
    @EnvironmentObject var b: BuzzerInput

    private var buzzerStatus: (String, Color) {
        if !b.running { return ("ARRÊTÉ", .gray) }
        if b.calibrating != nil { return ("MESURE…", .blue) }
        if b.locked { return (String(format: "VERROU %.0f s", b.lockRemaining), .orange) }
        return b.armed ? ("PRÊT", .green) : ("DÉSARMÉ", .gray)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Sorties MIDI").font(.headline)
                            Spacer()
                            Button("Rafraîchir") { s.refreshMIDI() }
                            Button("+ Ajouter une sortie") { s.show.outputs.append(MIDIOutput(name: "Nouvelle sortie")) }
                        }
                        Text("Une sortie = un logiciel qui reçoit. « Port virtuel » pour grandMA3 et QLab sur ce Mac, la session réseau pour le PC QuickShow.")
                            .font(.caption).foregroundColor(.secondary)
                        ForEach(s.show.outputs) { o in
                            let ob = s.outputBinding(o.id)
                            HStack {
                                TextField("Nom", text: ob.name).frame(width: 220)
                                Picker("", selection: ob.destination) {
                                    Text("Port virtuel « \(MIDIOut.virtualName) »").tag(Int32(0))
                                    ForEach(s.midiDestinations) { d in Text(d.name).tag(d.id) }
                                    if o.destination != 0 && !s.midiDestinations.contains(where: { $0.id == o.destination }) {
                                        Text("Absente (débranchée ?)").tag(o.destination)
                                    }
                                }.frame(width: 300)
                                Button("Tester") { s.testOutput(o) }.help("Envoie la note 60 sur le canal 1")
                                Button(action: { s.show.outputs.removeAll { $0.id == o.id } }) { Image(systemName: "trash") }
                                Spacer()
                            }
                        }
                    }.padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text("Buzzer").font(.headline)
                            Text(buzzerStatus.0).font(.headline).foregroundColor(buzzerStatus.1)
                            Spacer()
                            Picker("Lance le cue", selection: $s.show.buzzerCueID) {
                                Text("Aucun").tag(UUID?.none)
                                ForEach(s.show.cues) { c in Text(c.name).tag(UUID?.some(c.id)) }
                            }.frame(width: 300)
                        }
                        HStack {
                            if b.running {
                                Button("Arrêter l'écoute") { b.stop() }
                            } else {
                                Button("Démarrer l'écoute") { b.start() }
                            }
                            Button(b.armed ? "Désarmer" : "Armer") { b.setArmed(!b.armed) }
                            Button("Simuler un appui") { b.trigger(source: "appui simulé") }
                            Button("Fin de verrou") { b.endLock(rearm: true) }.disabled(!b.locked)
                            Spacer()
                            Button("Rafraîchir les cartes") { b.refreshDevices() }
                        }
                        LevelMeter(level: b.level, threshold: b.threshold, idle: b.idleMax, press: b.pressAvg)
                            .frame(height: 30)
                        HStack(alignment: .top, spacing: 12) {
                            GroupBox("Carte son du buzzer") { SoundCardSettings().padding(6) }
                            GroupBox("Détection") { DetectionSettings().padding(6) }
                        }
                    }.padding(6)
                }
            }
            .padding(8)
        }
    }
}
