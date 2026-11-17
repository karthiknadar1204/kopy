import AppKit

@MainActor
enum ShelfSound: CaseIterable {
    case capture, click, on, off, delete, expand, collapse, tick
    case edgeRetract, edgeBeacon, edgeExpand

    private static var players: [Self: NSSound] = [:]
    private static var lastPlayed: [Self: ContinuousClock.Instant] = [:]

    static func play(_ cue: Self, enabled: Bool) {
        guard enabled else { return }
        let now = ContinuousClock.now
        if let last = lastPlayed[cue], last.duration(to: now) < .milliseconds(35) { return }
        guard let player = players[cue] ?? NSSound(data: cue.wave) else { return }
        players[cue] = player
        lastPlayed[cue] = now
        player.stop()
        player.play()
    }

    private struct Note {
        let pitch: Double
        let length: Double
        let start: Double
        let volume: Double
        let bend: Double

        init(_ pitch: Double, _ length: Double, start: Double = 0, volume: Double = 0.09, bend: Double = 0) {
            self.pitch = pitch
            self.length = length
            self.start = start
            self.volume = volume
            self.bend = bend
        }
    }

    private var notes: [Note] {
        switch self {
        case .capture: [Note(1_175, 0.07), Note(1_760, 0.09, start: 0.026, volume: 0.045)]
        case .click: [Note(880, 0.038)]
        case .on: [Note(988, 0.06), Note(2_727, 0.027, volume: 0.023)]
        case .off: [Note(740, 0.06), Note(2_042, 0.027, volume: 0.023)]
        case .delete: [Note(587, 0.11, bend: -110)]
        case .expand: [Note(659, 0.075), Note(988, 0.12, start: 0.05)]
        case .collapse: [Note(988, 0.075), Note(659, 0.09, start: 0.05, volume: 0.065)]
        case .tick: [Note(1_760, 0.019, volume: 0.045)]
        case .edgeRetract: [Note(440, 0.15, volume: 0.04, bend: -220), Note(294, 0.09, start: 0.15)]
        case .edgeBeacon: [Note(1_175, 0.18, volume: 0.052)]
        case .edgeExpand: [Note(440, 0.13, bend: 220)]
        }
    }

    var wave: Data {
        let notes = notes
        let rate: UInt32 = 24_000
        let sampleCount = Int(ceil((notes.map { $0.start + $0.length }.max() ?? 0) * Double(rate)))
        let dataLength = UInt32(sampleCount * 2)
        var data = Data("RIFF".utf8)
        data.appendLittleEndian(dataLength + 36)
        data.append(Data("WAVEfmt ".utf8))
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(rate)
        data.appendLittleEndian(rate * 2)
        data.appendLittleEndian(UInt16(2))
        data.appendLittleEndian(UInt16(16))
        data.append(Data("data".utf8))
        data.appendLittleEndian(dataLength)
        for position in 0..<sampleCount {
            let t = Double(position) / Double(rate)
            let amplitude = notes.reduce(0.0) { value, note in
                let age = t - note.start
                guard age >= 0, age < note.length else { return value }
                let progress = age / note.length
                let attack = min(age / 0.003, 1)
                let envelope = attack * pow(1 - progress, 3)
                let phase = (note.pitch * age + note.bend * age * progress / 2) * 2 * Double.pi
                return value + sin(phase) * envelope * note.volume
            }
            data.appendLittleEndian(Int16(amplitude * Double(Int16.max)))
        }
        return data
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var bytes = value.littleEndian
        Swift.withUnsafeBytes(of: &bytes) { append(contentsOf: $0) }
    }
}
