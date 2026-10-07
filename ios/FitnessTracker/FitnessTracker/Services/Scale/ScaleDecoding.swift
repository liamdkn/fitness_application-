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

    // MARK: ICOMON / Fitdays+ kitchen scales

    /// Kitchen scales of this family (device type 0x42, e.g. KG2458ULB-D,
    /// advertised as MY_SCALE) frame everything as
    /// `AC 42 [payload...] [command] [checksum]`, the checksum being the sum of
    /// every byte after the 42, command included, modulo 256.
    struct IcomonFrame {
        /// The notification type (0xA0 capabilities, 0xA6 live weight, ...).
        let type: UInt8
        let payload: [UInt8]
        let checksumOK: Bool
    }

    static func icomonFrame(_ data: Data) -> IcomonFrame? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xAC, bytes[1] == 0x42 else { return nil }
        let body = bytes[2..<(bytes.count - 1)]
        let checksum = UInt8(truncatingIfNeeded: body.reduce(0) { $0 + Int($1) })
        return IcomonFrame(type: bytes[bytes.count - 2], payload: Array(bytes[2..<(bytes.count - 2)]),
                           checksumOK: checksum == bytes[bytes.count - 1])
    }

    /// A command frame for the scale.
    static func icomonCommand(payload: [UInt8], command: UInt8) -> Data {
        let body = payload + [command]
        let checksum = UInt8(truncatingIfNeeded: body.reduce(0) { $0 + Int($1) })
        return Data([0xAC, 0x42] + body + [checksum])
    }

    /// The reply to the scale's capabilities message: sent once after connecting.
    /// It is `AC 42 00 02 00 A0 00 D1 73`.
    static let icomonHandshake = icomonCommand(payload: [0x00, 0x02, 0x00, 0xA0, 0x00], command: 0xD1)

    /// Tells the scale who is weighing (user 1). Weight only starts streaming
    /// after this - found by trying it against a real KN2432LB: the scale
    /// acknowledges it and then sends a weight message about every 0.13 s.
    /// It is `AC 42 00 04 00 00 00 00 01 DB E0`.
    static let icomonUserInfo = icomonCommand(payload: [0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x01], command: 0xDB)

    struct IcomonWeight: Equatable {
        /// Grams (the scale reports milligrams).
        let grams: Double
        /// The unit the scale is set to (0 grams, 1 millilitres, 2 pounds, 3 ounces, ...).
        let unit: UInt8
        /// Grams or millilitres (1 ml of water is 1 g): the units the app can use.
        var isMetric: Bool { unit == 0 || unit == 1 }
        /// False while the reading is still moving.
        let stable: Bool
        let isTare: Bool
        let isIdle: Bool
    }

    /// Reads a live-weight (0xA6) notification: after a 3-byte length/sequence
    /// header come a flags byte (0x80 moving, 0x40 tare, 0x01 idle), the unit in
    /// the high nibble of the next, then the weight in milligrams as 24 bits.
    static func icomonWeight(_ frame: IcomonFrame) -> IcomonWeight? {
        guard frame.type == 0xA6 else { return nil }
        let body = frame.payload
        let data = body.count >= 8 ? Array(body.dropFirst(3)) : body
        guard data.count >= 5 else { return nil }
        let flags = data[0]
        let milligrams = Int(data[2]) << 16 | Int(data[3]) << 8 | Int(data[4])
        return IcomonWeight(
            grams: (Double(milligrams) / 1000 * 10).rounded() / 10,
            unit: data[1] >> 4,
            stable: flags & 0x80 == 0, isTare: flags & 0x40 != 0, isIdle: flags & 0x01 != 0
        )
    }

    /// The scale's display units, as the UNIT button cycles them. The weight on
    /// the wire is always mass (milligrams) whatever is displayed; the unit only
    /// says how the scale itself shows it.
    static func unitName(_ code: Int) -> String {
        switch code {
        case 0: "g"
        case 1: "ml"
        case 2: "lb:oz"
        case 3: "oz"
        case 4: "mg"
        case 5: "ml (milk)"
        case 6: "fl oz"
        case 7: "fl oz (milk)"
        default: "unit \(code)"
        }
    }

    /// Grams in one millilitre for the scale's current unit: milk modes use milk's
    /// density, everything else water's.
    static func gramsPerMillilitre(scaleUnit code: Int?) -> Double {
        code == 5 || code == 7 ? 1.03 : 1.0
    }

    /// What to record for `grams` of mass on the scale, in the unit the food is
    /// counted in: grams for a food in g, millilitres for one in ml (using the
    /// scale's milk setting when it is on, so "ml milk" reads the same here as
    /// on the scale). `nil` when the food isn't counted by weight or volume.
    static func amount(forGrams grams: Double, foodUnit: String, scaleUnit: Int?) -> Double? {
        switch foodUnit.lowercased() {
        case "g": grams
        case "ml": grams / gramsPerMillilitre(scaleUnit: scaleUnit)
        default: nil
        }
    }

    /// Hex dump for the setup screen: "0A 1F 00".
    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
