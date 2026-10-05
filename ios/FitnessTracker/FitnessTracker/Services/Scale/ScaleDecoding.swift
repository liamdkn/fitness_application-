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

    /// Hex dump for the setup screen: "0A 1F 00".
    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
