import Foundation

// Modèle du show, sauvegardé en JSON. Le décodage tolère les champs absents
// pour qu'un show enregistré par une version précédente s'ouvre toujours.

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback()
    }
}

/// Une sortie MIDI nommée (grandMA3, QLab, PC QuickShow...).
struct MIDIOutput: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var destination: Int32 = 0       // 0 = port virtuel « Cue Station »
}

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case note, cc, program, playSound, stopSound, stopZone, stopAll
    var id: String { rawValue }
    var label: String {
        switch self {
        case .note: return "Note MIDI"
        case .cc: return "Control Change"
        case .program: return "Program Change"
        case .playSound: return "Lancer un son"
        case .stopSound: return "Arrêter un son"
        case .stopZone: return "Couper une zone"
        case .stopAll: return "Tout couper"
        }
    }
    var isMIDI: Bool { self == .note || self == .cc || self == .program }
}

/// Une action d'un cue.
struct CueAction: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: ActionKind = .note
    var outputID: UUID?
    var channel = 1
    var number = 60          // note ou numéro de CC
    var value = 127          // vélocité, valeur de CC ou n° de programme
    var trackID: UUID?
    var zoneID: UUID?
    var duck = false         // baisser les zones cochées pendant ce son
    var fade: Double = 1     // fondu pour les arrêts (s)
    var delay: Double = 0    // délai avant l'action (s)

    init(kind: ActionKind = .note) { self.kind = kind }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        kind = c.value(.kind, .note)
        outputID = c.value(.outputID, nil)
        channel = c.value(.channel, 1)
        number = c.value(.number, 60)
        value = c.value(.value, 127)
        trackID = c.value(.trackID, nil)
        zoneID = c.value(.zoneID, nil)
        duck = c.value(.duck, false)
        fade = c.value(.fade, 1)
        delay = c.value(.delay, 0)
    }
}

struct Cue: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var color: String = "blue"
    var actions: [CueAction] = []

    init(name: String, color: String = "blue", actions: [CueAction] = []) {
        self.name = name
        self.color = color
        self.actions = actions
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "Cue")
        color = c.value(.color, "blue")
        actions = c.value(.actions, [])
    }

    static let colors = ["blue", "green", "orange", "red", "purple", "pink", "teal", "gray"]
}

struct Zone: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var left: Int = 1            // canal de sortie gauche (1 = premier)
    var right: Int = 2           // 0 = zone mono
    var gainDb: Double = 0
    var muted = false
    var duckOnBuzzer = true      // se baisse pendant un son lancé avec « baisser les zones »
    var duckDb: Double = -15

    init(name: String, left: Int = 1, right: Int = 2) {
        self.name = name
        self.left = left
        self.right = right
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "Zone")
        left = c.value(.left, 1)
        right = c.value(.right, 2)
        gainDb = c.value(.gainDb, 0)
        muted = c.value(.muted, false)
        duckOnBuzzer = c.value(.duckOnBuzzer, true)
        duckDb = c.value(.duckDb, -15)
    }
}

/// Un repère dans un son : quand la lecture passe dessus, il lance un cue.
struct Marker: Codable, Identifiable, Hashable {
    var id = UUID()
    var time: Double
    var label: String = ""
    var cueID: UUID?

    init(time: Double) { self.time = time }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        time = c.value(.time, 0)
        label = c.value(.label, "")
        cueID = c.value(.cueID, nil)
    }
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

    init(name: String, path: String, zoneID: UUID? = nil, loop: Bool = true, duration: Double = 0) {
        self.name = name
        self.path = path
        self.zoneID = zoneID
        self.loop = loop
        self.duration = duration
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "Son")
        path = c.value(.path, "")
        zoneID = c.value(.zoneID, nil)
        loop = c.value(.loop, true)
        gainDb = c.value(.gainDb, 0)
        autoplay = c.value(.autoplay, false)
        duration = c.value(.duration, 0)
        markers = c.value(.markers, [])
    }

    static let empty = Track(name: "", path: "")
}

struct Show: Codable {
    var outputs: [MIDIOutput] = []
    var cues: [Cue] = []
    var zones: [Zone] = []
    var tracks: [Track] = []
    var buzzerCueID: UUID?
    var panicCueID: UUID?
    var deviceUID: String = ""

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        outputs = c.value(.outputs, [])
        cues = c.value(.cues, [])
        zones = c.value(.zones, [])
        tracks = c.value(.tracks, [])
        buzzerCueID = c.value(.buzzerCueID, nil)
        panicCueID = c.value(.panicCueID, nil)
        deviceUID = c.value(.deviceUID, "")
    }

    /// Show de départ : sorties et cues d'exemple, à modifier.
    static var starter: Show {
        var s = Show()
        let ma = MIDIOutput(name: "grandMA3 (ce Mac)")
        let qlab = MIDIOutput(name: "QLab (ce Mac)")
        let laser = MIDIOutput(name: "PC QuickShow (réseau)")
        s.outputs = [ma, qlab, laser]
        s.zones = [Zone(name: "Zone 1", left: 1, right: 2), Zone(name: "Zone 2", left: 3, right: 4), Zone(name: "Zone 3", left: 5, right: 6)]
        var a1 = CueAction(kind: .note); a1.outputID = ma.id; a1.channel = 1; a1.number = 60
        var a2 = CueAction(kind: .note); a2.outputID = laser.id; a2.channel = 1; a2.number = 60
        let show = Cue(name: "Séquence lutins", color: "orange", actions: [a1, a2])
        var p1 = CueAction(kind: .note); p1.outputID = ma.id; p1.channel = 1; p1.number = 127
        var p2 = CueAction(kind: .note); p2.outputID = laser.id; p2.channel = 1; p2.number = 127
        let panic = Cue(name: "Panic (noir)", color: "red", actions: [p1, p2])
        s.cues = [show, panic]
        s.buzzerCueID = show.id
        s.panicCueID = panic.id
        return s
    }
}
