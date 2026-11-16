import CoreMIDI
import Foundation

struct MIDIDestination: Identifiable, Hashable {
    let id: Int32      // MIDIUniqueID ; 0 = port virtuel de l'appli
    let name: String
}

/// Sortie MIDI : soit un port virtuel "Buzzer Trigger" que QLab et grandMA3 voient
/// directement comme une entrée, soit une destination existante (bus IAC...).
final class MIDIOut {
    static let virtualName = "Buzzer Trigger"
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var source = MIDIEndpointRef()
    private(set) var ready = false

    init() {
        var status = MIDIClientCreateWithBlock(MIDIOut.virtualName as CFString, &client) { _ in }
        if status == noErr { status = MIDIOutputPortCreate(client, "Sortie" as CFString, &port) }
        if status == noErr { status = MIDISourceCreate(client, MIDIOut.virtualName as CFString, &source) }
        ready = (status == noErr)
    }

    static func destinations() -> [MIDIDestination] {
        var result: [MIDIDestination] = []
        for i in 0..<MIDIGetNumberOfDestinations() {
            let ep = MIDIGetDestination(i)
            var uid: Int32 = 0
            MIDIObjectGetIntegerProperty(ep, kMIDIPropertyUniqueID, &uid)
            var cfName: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(ep, kMIDIPropertyDisplayName, &cfName)
            let name = (cfName?.takeRetainedValue() as String?) ?? "Destination \(i + 1)"
            if uid != 0 { result.append(MIDIDestination(id: uid, name: name)) }
        }
        return result
    }

    private static func endpoint(for uid: Int32) -> MIDIEndpointRef? {
        for i in 0..<MIDIGetNumberOfDestinations() {
            let ep = MIDIGetDestination(i)
            var u: Int32 = 0
            MIDIObjectGetIntegerProperty(ep, kMIDIPropertyUniqueID, &u)
            if u == uid { return ep }
        }
        return nil
    }

    /// Envoie des octets MIDI bruts. destination 0 = port virtuel.
    @discardableResult
    func send(_ bytes: [UInt8], destination: Int32) -> Bool {
        guard ready else { return false }
        var target: MIDIEndpointRef? = nil
        if destination != 0 {
            guard let ep = MIDIOut.endpoint(for: destination) else { return false }
            target = ep
        }
        let bufferSize = 256
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var status: OSStatus = noErr
        buffer.withUnsafeMutableBytes { raw in
            let list = raw.baseAddress!.assumingMemoryBound(to: MIDIPacketList.self)
            let packet = MIDIPacketListInit(list)
            _ = MIDIPacketListAdd(list, bufferSize, packet, 0, bytes.count, bytes)
            if let ep = target {
                status = MIDISend(port, ep, list)
            } else {
                status = MIDIReceived(source, list)
            }
        }
        return status == noErr
    }

    func note(channel: Int, note: Int, on: Bool, destination: Int32) -> Bool {
        let ch = UInt8(max(1, min(16, channel)) - 1)
        let n = UInt8(max(0, min(127, note)))
        return send([(on ? 0x90 : 0x80) | ch, n, on ? 127 : 0], destination: destination)
    }
}
