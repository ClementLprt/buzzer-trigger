import SwiftUI

/// Onglet « Éditeur » : liste des sons à gauche, forme d'onde et marqueurs MIDI à droite.
struct EditorView: View {
    @EnvironmentObject var s: ShowController
    @State private var selection: UUID?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sons").font(.headline)
                List(selection: $selection) {
                    ForEach(s.show.tracks) { t in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                if s.positions[t.id] != nil { Image(systemName: "speaker.wave.2.fill").foregroundColor(.green) }
                                Text(t.name).fontWeight(.semibold)
                            }
                            Text(subtitle(t)).font(.caption).foregroundColor(.secondary)
                        }
                        .tag(t.id)
                    }
                }
                HStack {
                    Button("Ajouter des sons…") { s.importTracks { ids in if let f = ids.first { selection = f } } }
                    Button("Supprimer") {
                        if let id = selection { s.removeTrack(id); selection = nil }
                    }.disabled(selection == nil)
                }
            }
            .padding(8)
            .frame(minWidth: 230, idealWidth: 270, maxWidth: 340)

            Group {
                if let id = selection, s.track(id) != nil {
                    TrackEditor(trackID: id).id(id)
                } else {
                    VStack(spacing: 10) {
                        Text("Choisis un son à gauche, ou ajoute des fichiers audio.").foregroundColor(.secondary)
                        Text("Chaque son a sa zone de sortie, peut tourner en boucle et porter des marqueurs MIDI.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 600)
        }
    }

    private func subtitle(_ t: Track) -> String {
        var parts = [s.zone(t.zoneID)?.name ?? "sans zone", timeString(t.duration)]
        if t.loop { parts.append("boucle") }
        if !t.markers.isEmpty { parts.append("\(t.markers.count) marqueur\(t.markers.count > 1 ? "s" : "")") }
        if s.show.buzzerTrackID == t.id { parts.append("BUZZER") }
        return parts.joined(separator: " · ")
    }
}

struct TrackEditor: View {
    @EnvironmentObject var s: ShowController
    @EnvironmentObject var e: TriggerEngine
    let trackID: UUID
    @State private var cursor: Double = 0
    @State private var zoom: Double = 1

    var body: some View {
        let track = s.binding(trackID)
        let t = track.wrappedValue
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TextField("Nom", text: track.name).font(.title3).frame(maxWidth: 320)
                Picker("Zone", selection: track.zoneID) {
                    Text("Aucune").tag(UUID?.none)
                    ForEach(s.show.zones) { z in Text(z.name).tag(UUID?.some(z.id)) }
                }.frame(width: 240)
                Toggle("Boucle", isOn: track.loop)
                Toggle("Au démarrage", isOn: track.autoplay)
                    .help("Lancée par « Lancer les boucles » dans l'onglet Diffusion")
            }
            HStack(spacing: 10) {
                Text("Volume")
                Slider(value: track.gainDb, in: -40...6).frame(width: 220)
                Text(String(format: "%+.0f dB", t.gainDb)).monospacedDigit().frame(width: 60, alignment: .leading)
                Spacer()
                Button(s.show.buzzerTrackID == trackID ? "Son du buzzer (oui)" : "En faire le son du buzzer") {
                    s.show.buzzerTrackID = (s.show.buzzerTrackID == trackID) ? nil : trackID
                }
            }
            Text(t.path).font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)

            WaveformArea(peaks: s.peaks[trackID] ?? [], duration: max(0.001, t.duration), markers: t.markers,
                         cursor: $cursor, playhead: s.positions[trackID], zoom: zoom) { id, time in
                let b = s.markerBinding(trackID, id)
                var m = b.wrappedValue
                m.time = time
                b.wrappedValue = m
            }
            .frame(height: 210)
            .onAppear { s.requestPeaks(t) }

            HStack(spacing: 8) {
                Button("Lire depuis le curseur") { s.play(trackID, from: cursor) }
                Button("Depuis le début") { s.play(trackID, from: 0) }
                Button("Stop") { s.stop(trackID, fade: 0.1) }
                Divider().frame(height: 18)
                Button("Marqueur au curseur") { s.addMarker(trackID, at: cursor) }
                Button("Marqueur à la lecture (⇧⌘M)") {
                    if let p = s.positions[trackID] { s.addMarker(trackID, at: p) }
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(s.positions[trackID] == nil)
                Spacer()
                Text("Zoom")
                Slider(value: $zoom, in: 1...40).frame(width: 140)
            }
            HStack {
                Text("Curseur \(timeString(cursor))").monospacedDigit()
                if let p = s.positions[trackID] { Text("Lecture \(timeString(p))").monospacedDigit().foregroundColor(.green) }
                Text("Durée \(timeString(t.duration))").monospacedDigit().foregroundColor(.secondary)
            }

            GroupBox("Marqueurs MIDI (envoyés à chaque passage de la lecture)") {
                if t.markers.isEmpty {
                    Text("Clique dans la forme d'onde pour placer le curseur, puis « Marqueur au curseur ». Pendant la lecture, ⇧⌘M pose un marqueur au vol. Glisse un marqueur orange pour le déplacer.")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(t.markers.sorted { $0.time < $1.time }) { m in
                                MarkerRow(marker: s.markerBinding(trackID, m.id), destinations: e.midiDestinations,
                                          test: { s.testMarker(m) },
                                          go: { cursor = m.time },
                                          delete: {
                                              if let i = s.show.tracks.firstIndex(where: { $0.id == trackID }) {
                                                  s.show.tracks[i].markers.removeAll { $0.id == m.id }
                                              }
                                          })
                            }
                        }.padding(4)
                    }.frame(minHeight: 120)
                }
            }
        }
        .padding(12)
    }
}

struct MarkerRow: View {
    @Binding var marker: Marker
    let destinations: [MIDIDestination]
    let test: () -> Void
    let go: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("s", value: $marker.time, format: .number.precision(.fractionLength(3)))
                .frame(width: 80)
                .help("Position en secondes")
            Text(timeString(marker.time)).monospacedDigit().foregroundColor(.secondary).frame(width: 80, alignment: .leading)
            TextField("Nom", text: $marker.label).frame(width: 150)
            Picker("", selection: $marker.destination) {
                Text("Port virtuel").tag(Int32(0))
                ForEach(destinations) { d in Text(d.name).tag(d.id) }
            }.frame(width: 190)
            Stepper(value: $marker.channel, in: 1...16) { Text("can. \(marker.channel)").monospacedDigit() }
            Stepper(value: $marker.note, in: 0...127) { Text("note \(marker.note)").monospacedDigit() }
            Button("Tester", action: test)
            Button("Aller", action: go)
            Button(action: delete) { Image(systemName: "trash") }.help("Supprimer le marqueur")
            Spacer(minLength: 0)
        }
    }
}

/// Forme d'onde avec curseur (bleu), tête de lecture (vert) et marqueurs déplaçables (orange).
struct WaveformArea: View {
    let peaks: [Float]
    let duration: Double
    let markers: [Marker]
    @Binding var cursor: Double
    let playhead: Double?
    let zoom: Double
    let moveMarker: (UUID, Double) -> Void

    var body: some View {
        GeometryReader { outer in
            let width = max(outer.size.width, outer.size.width * zoom)
            let h = max(60, outer.size.height - 18)
            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in draw(ctx, size) }
                        .frame(width: width, height: h)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("wave")).onChanged { v in
                            cursor = time(v.location.x, width)
                        })
                    Rectangle().fill(Color.blue).frame(width: 2, height: h).offset(x: x(cursor, width) - 1)
                        .allowsHitTesting(false)
                    if let p = playhead {
                        Rectangle().fill(Color.green).frame(width: 2, height: h).offset(x: x(p, width) - 1)
                            .allowsHitTesting(false)
                    }
                    ForEach(markers) { m in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(m.label.isEmpty ? "n\(m.note)" : m.label)
                                .font(.caption2).foregroundColor(.black)
                                .padding(.horizontal, 3).padding(.vertical, 1)
                                .background(Color.orange)
                                .fixedSize()
                            Rectangle().fill(Color.orange).frame(width: 2, height: h - 16)
                        }
                        .offset(x: x(m.time, width) - 1)
                        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("wave")).onChanged { v in
                            moveMarker(m.id, time(v.location.x, width))
                        })
                        .help("\(m.label) : can.\(m.channel) note \(m.note), \(timeString(m.time))")
                    }
                }
                .frame(width: width, height: h, alignment: .topLeading)
                .coordinateSpace(name: "wave")
            }
        }
    }

    private func x(_ t: Double, _ width: CGFloat) -> CGFloat {
        CGFloat(max(0, min(1, t / duration))) * width
    }

    private func time(_ x: CGFloat, _ width: CGFloat) -> Double {
        max(0, min(duration, Double(x / max(1, width)) * duration))
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6), with: .color(Color.black.opacity(0.8)))
        let mid = size.height / 2
        if peaks.isEmpty {
            ctx.draw(Text("Calcul de la forme d'onde…").foregroundColor(.gray), at: CGPoint(x: 120, y: mid))
        } else {
            let n = peaks.count
            let w = size.width / CGFloat(n)
            var path = Path()
            for i in 0..<n {
                let a = CGFloat(min(1, peaks[i])) * (mid - 4)
                path.addRect(CGRect(x: CGFloat(i) * w, y: mid - a, width: max(w, 0.7), height: max(1, a * 2)))
            }
            ctx.fill(path, with: .color(Color(red: 0.35, green: 0.75, blue: 1.0)))
        }
        // graduations : une toutes les ~80 px
        let pxPerSec = size.width / CGFloat(duration)
        let steps: [Double] = [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        let step = steps.first { CGFloat($0) * pxPerSec >= 80 } ?? 600
        var t = 0.0
        while t <= duration {
            let xx = CGFloat(t) * pxPerSec
            var p = Path()
            p.move(to: CGPoint(x: xx, y: size.height - 10))
            p.addLine(to: CGPoint(x: xx, y: size.height))
            ctx.stroke(p, with: .color(.gray), lineWidth: 1)
            ctx.draw(Text(timeString(t)).font(.system(size: 9)).foregroundColor(.gray),
                     at: CGPoint(x: xx + 3, y: size.height - 18), anchor: .leading)
            t += step
        }
    }
}
