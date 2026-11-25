import SwiftUI

/// Onglet principal : la grille des cues, le PANIC et le journal.
struct CuesView: View {
    @EnvironmentObject var s: ShowController
    @EnvironmentObject var b: BuzzerInput
    @State private var editing = false
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusBar(editing: $editing)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                            ForEach(Array(s.show.cues.enumerated()), id: \.element.id) { i, c in
                                CueTile(cue: c, index: i + 1, editing: editing, selected: selection == c.id) {
                                    if editing { selection = c.id } else { s.go(c.id, from: "bouton") }
                                }
                            }
                            if editing {
                                Button(action: { selection = s.addCue() }) {
                                    VStack {
                                        Image(systemName: "plus").font(.system(size: 28))
                                        Text("Nouveau cue")
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 110)
                                    .background(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                                }.buttonStyle(.plain)
                            }
                        }.padding(2)
                    }
                    LogView().frame(height: 150)
                }
                if editing {
                    Group {
                        if let id = selection, s.cue(id) != nil {
                            CueEditor(cueID: id, selection: $selection).id(id)
                        } else {
                            Text("Clique sur un cue pour le modifier, ou crée-en un.")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(width: 560)
                }
            }
        }
        .padding(8)
    }
}

struct StatusBar: View {
    @EnvironmentObject var s: ShowController
    @EnvironmentObject var b: BuzzerInput
    @Binding var editing: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                s.panic()
                b.panic()
            }) {
                Text("PANIC")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 200, height: 56)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.red))
            }
            .buttonStyle(.plain)
            .help("Annule les cues en attente, coupe les sons lancés par les cues (pas les boucles), All Notes Off, désarme le buzzer, puis lance le cue PANIC")

            Chip(title: "Diffusion", value: s.running ? (s.ducking ? "zones baissées" : "en cours") : "arrêtée",
                 color: s.running ? .green : .gray)
            Chip(title: "Buzzer", value: buzzerText, color: buzzerColor)
            if let last = s.lastCue, let c = s.cue(last.id) {
                Chip(title: "Dernier GO", value: "\(c.name) · \(last.date.formatted(date: .omitted, time: .standard))", color: .cue(c.color))
            }
            Spacer()
            Toggle("Modifier les cues", isOn: $editing).toggleStyle(.button)
        }
    }

    private var buzzerText: String {
        if !b.running { return "pas en écoute" }
        if b.locked { return String(format: "verrou %.0f s", b.lockRemaining) }
        let target = s.cue(s.show.buzzerCueID)?.name ?? "aucun cue"
        return (b.armed ? "armé → " : "désarmé → ") + target
    }

    private var buzzerColor: Color {
        if !b.running { return .gray }
        if b.locked { return .orange }
        return b.armed ? .green : .gray
    }
}

struct Chip: View {
    let title: String, value: String, color: Color
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title).foregroundColor(.secondary)
            Text(value).fontWeight(.semibold).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
    }
}

struct CueTile: View {
    @EnvironmentObject var s: ShowController
    let cue: Cue
    let index: Int
    let editing: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let recent = s.lastCue.map { $0.id == cue.id && Date().timeIntervalSince($0.date) < 1.5 } ?? false
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(index)").font(.system(size: 13, weight: .bold)).foregroundColor(.white.opacity(0.85))
                    Spacer()
                    if s.show.buzzerCueID == cue.id { Tag("BUZZER") }
                    if s.show.panicCueID == cue.id { Tag("PANIC") }
                }
                Text(cue.name).font(.system(size: 18, weight: .bold)).foregroundColor(.white).lineLimit(2)
                Text(summary).font(.caption).foregroundColor(.white.opacity(0.85)).lineLimit(2)
                Spacer(minLength: 0)
                Text(editing ? "MODIFIER" : "GO").font(.system(size: 15, weight: .heavy)).foregroundColor(.white)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.cue(cue.color).opacity(recent ? 1 : 0.8)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.primary : (recent ? Color.white : Color.clear), lineWidth: 3))
        }
        .buttonStyle(.plain)
    }

    private var summary: String {
        if cue.actions.isEmpty { return "aucune action" }
        return cue.actions.map { s.describe($0) }.joined(separator: " · ")
    }
}

private struct Tag: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text).font(.system(size: 10, weight: .bold)).foregroundColor(.black)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.9)))
    }
}

struct LogView: View {
    @EnvironmentObject var s: ShowController
    var body: some View {
        GroupBox("Journal") {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(s.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: éditeur de cue

struct CueEditor: View {
    @EnvironmentObject var s: ShowController
    let cueID: UUID
    @Binding var selection: UUID?

    var body: some View {
        let cb = s.cueBinding(cueID)
        let c = cb.wrappedValue
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Nom du cue", text: cb.name).font(.title3)
                    Button("GO") { s.go(cueID, from: "test") }.keyboardShortcut(.return, modifiers: [.command])
                }
                HStack(spacing: 6) {
                    ForEach(Cue.colors, id: \.self) { col in
                        Circle().fill(Color.cue(col)).frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.primary, lineWidth: c.color == col ? 2 : 0))
                            .onTapGesture { s.updateCue(cueID) { $0.color = col } }
                    }
                    Spacer()
                    Toggle("Buzzer", isOn: Binding(
                        get: { s.show.buzzerCueID == cueID },
                        set: { s.show.buzzerCueID = $0 ? cueID : nil }))
                        .help("Ce cue part à chaque appui sur le buzzer")
                    Toggle("PANIC", isOn: Binding(
                        get: { s.show.panicCueID == cueID },
                        set: { s.show.panicCueID = $0 ? cueID : nil }))
                        .help("Ce cue part quand on appuie sur PANIC (noir, stop...)")
                }

                Text("Actions (parties dans l'ordre, chacune après son délai)").font(.headline)
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(c.actions) { a in
                            ActionRow(cueID: cueID, actionID: a.id)
                        }
                    }
                }
                HStack {
                    Menu("+ Ajouter une action") {
                        ForEach(ActionKind.allCases) { k in
                            Button(k.label) {
                                var a = CueAction(kind: k)
                                a.outputID = s.show.outputs.first?.id
                                a.trackID = s.show.tracks.first?.id
                                a.zoneID = s.show.zones.first?.id
                                s.updateCue(cueID) { $0.actions.append(a) }
                            }
                        }
                    }.frame(width: 200)
                    Spacer()
                    Button(action: { s.moveCue(cueID, by: -1) }) { Image(systemName: "arrow.left") }.help("Déplacer avant")
                    Button(action: { s.moveCue(cueID, by: 1) }) { Image(systemName: "arrow.right") }.help("Déplacer après")
                    Button("Dupliquer") { selection = s.duplicateCue(cueID) }
                    Button("Supprimer") { s.deleteCue(cueID); selection = nil }
                }
            }
            .padding(8)
        }
    }
}

struct ActionRow: View {
    @EnvironmentObject var s: ShowController
    let cueID: UUID
    let actionID: UUID

    private var binding: Binding<CueAction> {
        Binding(
            get: { s.cue(cueID)?.actions.first { $0.id == actionID } ?? CueAction() },
            set: { nv in
                guard let ci = s.show.cues.firstIndex(where: { $0.id == cueID }),
                      let ai = s.show.cues[ci].actions.firstIndex(where: { $0.id == actionID }) else { return }
                s.show.cues[ci].actions[ai] = nv
            })
    }

    var body: some View {
        let ab = binding
        let a = ab.wrappedValue
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: ab.kind) {
                    ForEach(ActionKind.allCases) { k in Text(k.label).tag(k) }
                }.frame(width: 170)
                Text("délai")
                TextField("s", value: ab.delay, format: .number.precision(.fractionLength(1))).frame(width: 50)
                Text("s")
                Spacer()
                Button("Tester") { s.perform(a) }
                Button(action: {
                    if let ci = s.show.cues.firstIndex(where: { $0.id == cueID }) {
                        s.show.cues[ci].actions.removeAll { $0.id == actionID }
                    }
                }) { Image(systemName: "trash") }
            }
            HStack {
                switch a.kind {
                case .note, .cc, .program:
                    Picker("", selection: ab.outputID) {
                        Text("Sortie…").tag(UUID?.none)
                        ForEach(s.show.outputs) { o in Text(o.name).tag(UUID?.some(o.id)) }
                    }.frame(width: 190)
                    Stepper(value: ab.channel, in: 1...16) { Text("can. \(a.channel)").monospacedDigit() }
                    if a.kind != .program {
                        Stepper(value: ab.number, in: 0...127) { Text("\(a.kind == .note ? "note" : "CC") \(a.number)").monospacedDigit() }
                    }
                    Stepper(value: ab.value, in: 0...127) {
                        Text("\(a.kind == .note ? "vél." : (a.kind == .cc ? "val." : "prog.")) \(a.value)").monospacedDigit()
                    }
                case .playSound:
                    TrackPicker(selection: ab.trackID)
                    Toggle("Baisser les autres zones", isOn: ab.duck)
                        .help("Les zones cochées « Baisser » descendent pendant ce son puis remontent")
                case .stopSound:
                    TrackPicker(selection: ab.trackID)
                    FadeField(value: ab.fade)
                case .stopZone:
                    Picker("", selection: ab.zoneID) {
                        Text("Zone…").tag(UUID?.none)
                        ForEach(s.show.zones) { z in Text(z.name).tag(UUID?.some(z.id)) }
                    }.frame(width: 190)
                    FadeField(value: ab.fade)
                case .stopAll:
                    FadeField(value: ab.fade)
                }
                Spacer()
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
    }
}

struct TrackPicker: View {
    @EnvironmentObject var s: ShowController
    @Binding var selection: UUID?
    var body: some View {
        Picker("", selection: $selection) {
            Text("Son…").tag(UUID?.none)
            ForEach(s.show.tracks) { t in Text(t.name).tag(UUID?.some(t.id)) }
        }.frame(width: 220)
    }
}

struct FadeField: View {
    @Binding var value: Double
    var body: some View {
        HStack(spacing: 4) {
            Text("fondu")
            TextField("s", value: $value, format: .number.precision(.fractionLength(1))).frame(width: 50)
            Text("s")
        }
    }
}
