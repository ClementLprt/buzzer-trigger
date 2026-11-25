import SwiftUI

/// Onglet « Diffusion » : carte de sortie (CQ12T), zones, lancement des boucles.
struct DiffusionView: View {
    @EnvironmentObject var s: ShowController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle().fill(s.running ? Color.green : Color.gray).frame(width: 22, height: 22)
                Text(s.running ? "DIFFUSION EN COURS" : "DIFFUSION ARRÊTÉE").font(.system(size: 22, weight: .bold))
                if s.running {
                    Text(String(format: "%@ · %d sorties · %.0f Hz", s.sound.deviceName, s.sound.channels, s.sound.sampleRate))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if s.ducking {
                    Text("ZONES BAISSÉES").font(.headline).foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange))
                }
            }

            HStack(spacing: 10) {
                Picker("Carte de diffusion", selection: $s.show.deviceUID) {
                    Text("Choisir…").tag("")
                    ForEach(s.devices.filter { $0.outputChannels > 0 }) { d in
                        Text("\(d.name) (\(d.outputChannels) sorties)").tag(d.uid)
                    }
                }
                .frame(width: 360)
                .disabled(s.running)
                Button("Rafraîchir") { s.refreshDevices() }.disabled(s.running)
                if s.running {
                    Button("Arrêter la diffusion") { s.stopEngine() }
                } else {
                    Button("Démarrer la diffusion") { s.start() }.keyboardShortcut(.defaultAction)
                }
                Divider().frame(height: 20)
                Button("Lancer les boucles") { s.startAutoplay() }
                    .help("Lance tous les sons cochés « Au démarrage » (onglet Sons)")
                Button("Tout couper (fondu 2 s)") { s.stopAll(fade: 2) }
                Spacer()
                Button("Ouvrir un show…") { s.openShow() }
                Button("Enregistrer sous…") { s.saveAs() }
            }

            HStack {
                Text("Zones").font(.headline)
                Spacer()
                Button("+ Ajouter une zone") {
                    let n = s.show.zones.count
                    s.show.zones.append(Zone(name: "Zone \(n + 1)", left: min(n * 2 + 1, 99), right: min(n * 2 + 2, 99)))
                }
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 12)], spacing: 12) {
                    ForEach(s.show.zones) { z in ZoneCard(zoneID: z.id) }
                }
            }
        }
        .padding(8)
    }
}

struct ZoneCard: View {
    @EnvironmentObject var s: ShowController
    let zoneID: UUID

    var body: some View {
        let zb = s.zoneBinding(zoneID)
        let z = zb.wrappedValue
        let n = max(1, s.channelCount)
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Nom de la zone", text: zb.name).font(.headline)
                    Toggle("Muet", isOn: zb.muted).toggleStyle(.button).tint(.red)
                    Button(action: { s.stopZone(zoneID) }) { Image(systemName: "stop.fill") }.help("Couper les sons de la zone (fondu 1 s)")
                    Button(action: {
                        s.stopZone(zoneID, fade: 0.05)
                        s.show.zones.removeAll { $0.id == zoneID }
                    }) { Image(systemName: "trash") }.help("Supprimer la zone")
                }
                HStack {
                    Picker("Sortie G", selection: zb.left) {
                        ForEach(1...max(n, z.left), id: \.self) { Text("\($0)").tag($0) }
                    }.frame(width: 120)
                    Picker("D", selection: zb.right) {
                        Text("Mono").tag(0)
                        ForEach(1...max(n, z.right, 1), id: \.self) { Text("\($0)").tag($0) }
                    }.frame(width: 100)
                    Spacer()
                }
                HStack {
                    Text("Volume")
                    Slider(value: zb.gainDb, in: -60...6)
                    Text(String(format: "%+.0f dB", z.gainDb)).monospacedDigit().frame(width: 56, alignment: .leading)
                }
                HStack {
                    Toggle("Se baisse", isOn: zb.duckOnBuzzer)
                        .help("Descend quand un cue lance un son avec « Baisser les autres zones »")
                    Stepper(value: zb.duckDb, in: -60...0, step: 3) { Text(String(format: "%.0f dB", z.duckDb)).monospacedDigit() }
                        .disabled(!z.duckOnBuzzer)
                }
                ZoneMeter(db: s.levels[zoneID] ?? -120).frame(height: 10)
                let tracks = s.show.tracks.filter { $0.zoneID == zoneID }
                if tracks.isEmpty {
                    Text("Aucun son dans cette zone : choisis la zone d'un son dans l'onglet Sons.")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(tracks) { t in
                        let pos = s.positions[t.id]
                        HStack(spacing: 6) {
                            Button(action: {
                                if pos != nil { s.stop(t.id, fade: 1) } else { s.play(t.id) }
                            }) {
                                Image(systemName: pos != nil ? "stop.fill" : "play.fill").frame(width: 16)
                            }
                            Text(t.name).lineLimit(1)
                            if t.loop { Image(systemName: "repeat").foregroundColor(.secondary) }
                            Spacer()
                            if let p = pos {
                                ProgressView(value: min(1, p / max(0.001, t.duration))).frame(width: 90)
                                Text(timeString(p)).font(.caption).monospacedDigit()
                            } else {
                                Text(timeString(t.duration)).font(.caption).foregroundColor(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
            }
            .padding(4)
        }
    }
}

struct ZoneMeter: View {
    let db: Double
    var body: some View {
        GeometryReader { g in
            let f = CGFloat(max(0, min(1, (db + 60) / 60)))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.7))
                RoundedRectangle(cornerRadius: 3)
                    .fill(db > -3 ? Color.red : (db > -12 ? Color.yellow : Color.green))
                    .frame(width: g.size.width * f)
            }
        }
    }
}
