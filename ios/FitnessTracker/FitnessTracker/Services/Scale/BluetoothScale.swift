import CoreBluetooth
import Foundation
import Observation

/// Finds Bluetooth scales, connects, and shows what they send - the setup
/// screen's engine. It listens to every characteristic that can notify and
/// keeps a log of the raw bytes, so a scale's data format can be worked out
/// from the app itself; readings that match the standard weight-scale format
/// are also decoded into grams.
@Observable
@MainActor
final class BluetoothScale: NSObject {
    /// One connection for the whole app, so the setup screen and the live
    /// weighing screen share it.
    static let shared = BluetoothScale()

    struct Found: Identifiable, Equatable {
        let id: UUID
        var name: String
        var rssi: Int
    }

    struct LogLine: Identifiable {
        let id = UUID()
        let time: Date
        let text: String
    }

    var state: CBManagerState = .unknown
    var found: [Found] = []
    var connectedName: String?
    var services: [String] = []
    var log: [LogLine] = []
    /// Latest weight in grams, when the scale uses the standard format.
    var grams: Double?
    var isScanning = false
    var status = ""
    /// Characteristics that can be written to, by UUID - offered in the advanced
    /// panel. Firmware-update characteristics are left out on purpose.
    var writableIds: [String] = []

    /// Called with each decoded reading (grams).
    var onReading: ((Double) -> Void)?

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connected: CBPeripheral?
    private var writables: [String: CBCharacteristic] = [:]

    private static let weightScaleMeasurement = CBUUID(string: "2A9D")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard central.state == .poweredOn else { status = "Bluetooth isn't on or isn't allowed."; return }
        found.removeAll()
        peripherals.removeAll()
        isScanning = true
        status = "Looking for scales... step on or put weight on yours so it wakes up."
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    func connect(_ device: Found) {
        guard let peripheral = peripherals[device.id] else { return }
        stopScan()
        status = "Connecting to \(device.name)..."
        connected = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func disconnect() {
        if let connected { central.cancelPeripheralConnection(connected) }
        connected = nil
        connectedName = nil
        grams = nil
        writables.removeAll()
        writableIds.removeAll()
        services.removeAll()
    }

    /// Sends bytes (as hex, "A5 01 FF") to one of the writable characteristics.
    /// Some scales only start sending weight after a command from their own app.
    func send(hex: String, to id: String) {
        let cleaned = hex.filter { $0.isHexDigit }
        guard let characteristic = writables[id], let connected, cleaned.count >= 2, cleaned.count % 2 == 0 else {
            append("Not sent: needs whole bytes, e.g. A5 01")
            return
        }
        var bytes: [UInt8] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            if let byte = UInt8(cleaned[index..<next], radix: 16) { bytes.append(byte) }
            index = next
        }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        connected.writeValue(Data(bytes), for: characteristic, type: type)
        append("Sent to \(id): \(ScaleDecoding.hex(Data(bytes)))")
    }

    /// Characteristics of the firmware-update service must never be written to.
    fileprivate nonisolated static func isFirmwareUpdate(_ uuid: CBUUID) -> Bool {
        uuid.uuidString.uppercased().hasPrefix("0000153")
    }

    private func append(_ text: String) {
        log.append(LogLine(time: Date(), text: text))
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }
}

extension BluetoothScale: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in self.state = central.state }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        guard let name, !name.isEmpty else { return }
        let id = peripheral.identifier
        let rssi = RSSI.intValue
        Task { @MainActor in
            self.peripherals[id] = peripheral
            if let index = self.found.firstIndex(where: { $0.id == id }) {
                self.found[index].rssi = rssi
            } else {
                self.found.append(Found(id: id, name: name, rssi: rssi))
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.connectedName = peripheral.name ?? "Scale"
            self.status = "Connected. Looking at what it offers..."
            self.append("Connected to \(peripheral.name ?? "scale")")
        }
        peripheral.discoverServices(nil)
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in self.status = "Couldn't connect: \(error?.localizedDescription ?? "unknown error")" }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.connectedName = nil
            self.status = "Disconnected."
        }
    }
}

extension BluetoothScale: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let serviceId = service.uuid.uuidString
        let lines = (service.characteristics ?? []).map { characteristic -> String in
            var properties: [String] = []
            if characteristic.properties.contains(.read) { properties.append("read") }
            if characteristic.properties.contains(.notify) { properties.append("notify") }
            if characteristic.properties.contains(.indicate) { properties.append("indicate") }
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) { properties.append("write") }
            return "\(characteristic.uuid.uuidString) (\(properties.joined(separator: ", ")))"
        }
        let writable = (service.characteristics ?? []).filter {
            ($0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)) && !Self.isFirmwareUpdate($0.uuid)
        }
        Task { @MainActor in
            self.services.append("Service \(serviceId): " + (lines.isEmpty ? "no characteristics" : lines.joined(separator: "; ")))
            self.status = "Listening. Put something on the scale."
            for characteristic in writable {
                self.writables[characteristic.uuid.uuidString] = characteristic
                if !self.writableIds.contains(characteristic.uuid.uuidString) { self.writableIds.append(characteristic.uuid.uuidString) }
            }
        }
        for characteristic in service.characteristics ?? [] {
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let uuid = characteristic.uuid
        let line = "\(uuid.uuidString): \(ScaleDecoding.hex(data))"
        let decoded = uuid == CBUUID(string: "2A9D") ? ScaleDecoding.standardWeightScale(data) : nil
        Task { @MainActor in
            self.append(line + (decoded.map { "  = \($0) g" } ?? ""))
            if let decoded {
                self.grams = decoded
                self.onReading?(decoded)
            }
        }
    }
}
