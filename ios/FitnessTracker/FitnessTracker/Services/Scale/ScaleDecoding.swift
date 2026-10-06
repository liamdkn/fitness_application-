import Foundation

/// Reads grams out of a scale's Bluetooth data.
nonisolated enum ScaleDecoding {
    /// Standard Bluetooth "Weight Scale" measurement (characteristic 0x2A9D):
    /// a flags byte, then a 16-bit weight. Flag bit 0 says pounds; otherwise
    /// kilograms in 0.005 steps (pounds in 0.01 steps).
    static func standardWeightScale(_ data: Data) -> Double? {
        guard data.count >= 3 else { return nil }
        let flags = data[data.startIndex]
        let raw = Double(UInt16(data[data.startIndex + 1]) | UInt16(data[data.startIndex + 2]) << 8)
        let isImperial = flags & 0x01 != 0
        let kg = isImperial ? raw * 0.01 * 0.45359237 : raw * 0.005
        return (kg * 1000 * 10).rounded() / 10
    }

    /// Fitdays / Lefu / ICOMON frames, as documented for a scale from the same
    /// app family: `[seq][00][len][00][type][payload...][checksum]`, with weight
    /// frames (type 0xA2) carrying the weight as a big-endian 24-bit number at
    /// byte 7. Whether a kitchen scale counts it in grams or tenths is checked
    /// against the number on the scale's own display.
    struct FitdaysFrame {
        let sequence: UInt8
        let type: UInt8
        let payload: [UInt8]
        let checksumOK: Bool

        /// The 24-bit weight field of a live-weight frame.
        var rawWeight: Int? {
            guard type == 0xA2, payload.count >= 5 else { return nil }
            // Frame byte 7 is payload index 2 (bytes 5, 6 are the first payload bytes).
            return Int(payload[2]) << 16 | Int(payload[3]) << 8 | Int(payload[4])
        }
    }

    static func fitdaysFrame(_ data: Data) -> FitdaysFrame? {
        let bytes = [UInt8](data)
        guard bytes.count >= 6 else { return nil }
        let length = Int(bytes[2])
        _ = length
        let type = bytes[4]
        let payload = Array(bytes[5..<(bytes.count - 1)])
        return FitdaysFrame(sequence: bytes[0], type: type, payload: payload,
                            checksumOK: fitdaysChecksum(type: type, payload: payload) == bytes[bytes.count - 1])
    }

    /// `(type + sum(payload)) & 0x1F`, with bit 5 set for every type except 0xA2.
    static func fitdaysChecksum(type: UInt8, payload: [UInt8]) -> UInt8 {
        let low = UInt8(truncatingIfNeeded: Int(type) + payload.reduce(0) { $0 + Int($1) }) & 0x1F
        return type == 0xA2 ? low : (low | 0x20)
    }

    /// A framed message: `[seq][00][len][00][type][payload][checksum]`, where
    /// len counts the type byte and the payload.
    static func fitdaysMessage(sequence: UInt8, type: UInt8, payload: [UInt8]) -> Data {
        var bytes: [UInt8] = [sequence, 0x00, UInt8(payload.count + 1), 0x00, type]
        bytes += payload
        bytes.append(fitdaysChecksum(type: type, payload: payload))
        return Data(bytes)
    }

    /// The ten messages the Fitdays app writes when it connects, as documented
    /// for a scale of the same family: a hello, a profile with the current time
    /// pushed several times, then two status requests. The profile bytes are
    /// the documented example's (body details for a made-up user).
    static func fitdaysHandshake(now: Date = Date(), timeZone: TimeZone = .current, name: [UInt8] = Array("Usr".utf8)) -> [Data] {
        let stamp = UInt32(now.timeIntervalSince1970)
        let zone = UInt16(truncatingIfNeeded: timeZone.secondsFromGMT(for: now) / 60)
        let tail: [UInt8] = [0xB9, 0x1C, 0x16, 0xA6, 0x1C, 0x25, 0x1D, 0x6A, 0x0F,
                             0x12, 0x4D, 0xE8, 0xBF, 0x01, 0x01, 0x03] + name
        let full: [UInt8] = [UInt8(stamp >> 24 & 0xFF), UInt8(stamp >> 16 & 0xFF), UInt8(stamp >> 8 & 0xFF), UInt8(stamp & 0xFF),
                             UInt8(zone >> 8), UInt8(zone & 0xFF), 0x01] + tail
        let compact: [UInt8] = [0x01, 0x01] + tail
        var messages: [Data] = [fitdaysMessage(sequence: 0, type: 0xB0, payload: [0x30, 0x00])]
        for index in 1...7 {
            messages.append(index % 2 == 1
                ? fitdaysMessage(sequence: UInt8(index), type: 0xC0, payload: full)
                : fitdaysMessage(sequence: UInt8(index), type: 0xC1, payload: compact))
        }
        messages.append(fitdaysMessage(sequence: 8, type: 0xB0, payload: [0x31, 0x00]))
        messages.append(fitdaysMessage(sequence: 9, type: 0xB0, payload: [0x39, 0x00]))
        return messages
    }

    /// Hex dump for the setup screen: "0A 1F 00".
    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
