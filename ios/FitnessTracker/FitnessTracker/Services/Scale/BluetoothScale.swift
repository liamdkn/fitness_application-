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
    /// The weight on the scale right now, including while it is still settling -
    /// for a display that follows the pour. `grams` and `onSample`'s steady flag only take
    /// steady readings.
    var live: Double?
    /// The unit the scale itself is displaying (see `ScaleDecoding.unitName`).
    /// The weight is mass whatever this says; it matters for ml and milk modes.
    var unit: Int?
    /// The scale paired with this phone, kept until it's unpaired. Identified by
    /// the iPhone's own id for the device, so it survives restarts.
    var pairedName: String?
    private(set) var pairedId: UUID?
    var isPaired: Bool { pairedId != nil }
    var isScanning = false
    /// Messages received on the scale's weight channel since connecting.
    var weightChannelPackets = 0
    var status = ""

    /// Called with every weight reading (grams) and whether the scale calls it
    /// steady - moving readings included, so a pour's pauses can be told from its end.
    var onSample: ((Double, Bool) -> Void)?
    /// Called when TARE is pressed on the scale, with the weight on it just before
    /// it zeroed - the app uses that press as "that's the amount, log it".
    var onTare: ((Double) -> Void)?
    /// How many TARE presses have been seen since connecting (shown in settings,
    /// to check the scale's button is being noticed).
    var tarePresses = 0
    private var massBeforeTare: Double?
    private var inTare = false

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connected: CBPeripheral?
    private var writables: [String: CBCharacteristic] = [:]
    private var handshakeSent = false
    /// Set when the user disconnects on purpose, so it isn't reconnected behind their back.
    private var manualDisconnect = false
    private static let knownKey = "scale-known-id"
    private static let knownNameKey = "scale-known-name"
    private var handshakeTask: Task<Void, Never>?
    /// Last broadcast bytes seen per device, so only changes are logged.
    private var lastBroadcast: [UUID: Data] = [:]

    private static let weightScaleMeasurement = CBUUID(string: "2A9D")

    override init() {
        super.init()
        pairedId = UserDefaults.standard.string(forKey: Self.knownKey).flatMap(UUID.init(uuidString:))
        pairedName = UserDefaults.standard.string(forKey: Self.knownNameKey)
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard central.state == .poweredOn else { status = "Bluetooth isn't on or isn't allowed."; return }
        found.removeAll()
        peripherals.removeAll()
        isScanning = true
        status = "Looking for scales... A scale only talks to one app at a time: close the Fitdays+ app completely first, or it won't be listed. Look for MY_SCALE."
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    func connect(_ device: Found) {
        guard let peripheral = peripherals[device.id] else { return }
        stopScan()
        status = "Connecting to \(device.name)..."
        manualDisconnect = false
        connected = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    /// Forgets the paired scale and drops the connection - for when something is
    /// wrong, or the scale is being replaced. Pairing again is a scan and a tap.
    func unpair() {
        manualDisconnect = true
        UserDefaults.standard.removeObject(forKey: Self.knownKey)
        UserDefaults.standard.removeObject(forKey: Self.knownNameKey)
        pairedId = nil
        pairedName = nil
        if let connected { central.cancelPeripheralConnection(connected) }
        connected = nil
        connectedName = nil
        grams = nil
        live = nil
        unit = nil
        writables.removeAll()
        services.removeAll()
    }

    /// Reconnects to the scale used last time. The connection request stays
    /// open, so it completes by itself when the scale wakes up - no scanning or
    /// tapping needed. Does nothing if no scale has been set up, or one is connected.
    func reconnectKnown() {
        guard central.state == .poweredOn, connected == nil,
              let id = pairedId,
              let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        manualDisconnect = false
        connected = peripheral
        peripheral.delegate = self
        status = "Waiting for the scale - wake it by pressing a button or putting something on."
        central.connect(peripheral)
    }

    /// Drops whatever connection attempt is open and starts a fresh one - for a
    /// paired scale that seems stuck.
    func reconnectNow() {
        if let connected { central.cancelPeripheralConnection(connected) }
        connected = nil
        connectedName = nil
        reconnectKnown()
    }

    /// The characteristic the scale takes commands on.
    private static let commandChannel = "0000FFB1-0000-1000-8000-00805F9B34FB"

    private func write(_ data: Data) {
        guard let connected, let characteristic = writables[Self.commandChannel] else {
            append("Not sent: no command channel on this device.")
            return
        }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        connected.writeValue(data, for: characteristic, type: type)
        append("Sent: \(ScaleDecoding.hex(data))")
    }

    /// The reply this family of kitchen scale expects after you subscribe to its
    /// weight channel (without it the scale stays silent), then the user-info
    /// command that starts the weight stream.
    func sendIcomonHandshake() {
        handshakeSent = true
        write(ScaleDecoding.icomonHandshake)
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            write(ScaleDecoding.icomonUserInfo)
        }
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
        Task { @MainActor in
            self.state = central.state
            if central.state == .poweredOn { self.reconnectKnown() }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        guard let name, !name.isEmpty else { return }
        let id = peripheral.identifier
        let rssi = RSSI.intValue
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        Task { @MainActor in
            // Some scales put the weight in what they broadcast, with no connection
            // needed. Log changes to that for anything that looks like a scale.
            if let manufacturer, name.localizedCaseInsensitiveContains("scale"), self.lastBroadcast[id] != manufacturer {
                self.lastBroadcast[id] = manufacturer
                self.append("\(name) broadcast: \(ScaleDecoding.hex(manufacturer))")
            }
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
            self.handshakeSent = false
            self.weightChannelPackets = 0
            self.tarePresses = 0
            self.inTare = false
            self.massBeforeTare = nil
            self.handshakeTask?.cancel()
            self.connectedName = peripheral.name ?? "Scale"
            self.status = "Connected. Looking at what it offers..."
            self.append("Connected to \(peripheral.name ?? "scale")")
        }
        peripheral.discoverServices(nil)
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.status = "Couldn't connect: \(error?.localizedDescription ?? "unknown error")"
            if !self.manualDisconnect { self.central.connect(peripheral) }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.connectedName = nil
            self.grams = nil
            self.live = nil
            self.unit = nil
            if self.manualDisconnect {
                self.status = "Disconnected."
            } else {
                // The scale went to sleep or out of range: keep a connection request
                // open so it comes back by itself.
                self.status = "Scale asleep - waiting for it to wake."
                self.handshakeSent = false
                self.central.connect(peripheral)
            }
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
            }
        }
        for characteristic in service.characteristics ?? [] {
            // Leave the firmware-update service completely alone.
            if Self.isFirmwareUpdate(characteristic.uuid) { continue }
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let id = String(characteristic.uuid.uuidString.prefix(8))
        let text = error.map { "Listening to \(id) FAILED: \($0.localizedDescription)" }
            ?? "Listening to \(id): \(characteristic.isNotifying ? "on" : "off")"
        let isWeightChannel = characteristic.uuid == CBUUID(string: "FFB2") && characteristic.isNotifying
        let peripheralId = peripheral.identifier
        let peripheralName = peripheral.name
        Task { @MainActor in
            self.append(text)
            // Only a device with the weight channel is remembered, so a wrong tap
            // in the list doesn't become the scale that auto-connects.
            if isWeightChannel {
                UserDefaults.standard.set(peripheralId.uuidString, forKey: Self.knownKey)
                self.pairedId = peripheralId
                if let name = peripheralName {
                    UserDefaults.standard.set(name, forKey: Self.knownNameKey)
                    self.pairedName = name
                }
            }
            // The scale normally announces itself once we listen; if it doesn't
            // within a few seconds, send the handshake anyway.
            if isWeightChannel, !self.handshakeSent {
                self.handshakeTask?.cancel()
                self.handshakeTask = Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    if !Task.isCancelled, !self.handshakeSent { self.sendIcomonHandshake() }
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let id = String(characteristic.uuid.uuidString.prefix(8))
        let text = error.map { "Write to \(id) FAILED: \($0.localizedDescription)" } ?? "Write to \(id) accepted"
        Task { @MainActor in self.append(text) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            Task { @MainActor in self.append("Read of \(characteristic.uuid.uuidString.prefix(8)) failed: \(error.localizedDescription)") }
            return
        }
        guard let data = characteristic.value else { return }
        let uuid = characteristic.uuid
        let line = "\(uuid.uuidString): \(ScaleDecoding.hex(data))"
        var decoded = uuid == CBUUID(string: "2A9D") ? ScaleDecoding.standardWeightScale(data) : nil
        var note = ""
        var announced = false
        var moving: Double?
        var unitCode: Int?
        var sampleStable = true
        var tareFlag = false
        if uuid == CBUUID(string: "FFB2"), let icomon = ScaleDecoding.icomonFrame(data) {
            note = "  [type \(String(format: "%02X", icomon.type)), checksum \(icomon.checksumOK ? "ok" : "BAD")"
            if icomon.type == 0xA0 { announced = true; note += ", capabilities - replying" }
            if let weight = ScaleDecoding.icomonWeight(icomon) {
                note += ", \(weight.stable ? "steady" : "moving")\(weight.isTare ? ", tare" : "")"
                // The weight is mass in every display unit, so g, ml, milk, oz and lb:oz
                // all read the same here; only the unit label differs.
                note += ", shows \(ScaleDecoding.unitName(Int(weight.unit)))"
                moving = weight.grams
                unitCode = Int(weight.unit)
                sampleStable = weight.stable
                tareFlag = weight.isTare
                if weight.stable { decoded = weight.grams }
            }
            note += "]"
        }
        let finalDecoded = decoded
        let didAnnounce = announced
        let liveValue = moving
        let liveUnit = unitCode
        let steady = sampleStable
        let tareFrame = tareFlag
        let onWeightChannel = uuid == CBUUID(string: "FFB2")
        let noteText = note
        Task { @MainActor in
            if onWeightChannel { self.weightChannelPackets += 1 }
            if didAnnounce, !self.handshakeSent { self.sendIcomonHandshake() }
            self.append(line + noteText + (finalDecoded.map { "  = \($0) g" } ?? ""))
            if let liveValue { self.live = liveValue }
            if let liveUnit { self.unit = liveUnit }
            if let decoded = finalDecoded { self.grams = decoded }
            if let liveValue {
                if tareFrame {
                    // First flagged frame = the press. The weight before it is the amount.
                    if !self.inTare {
                        self.inTare = true
                        self.tarePresses += 1
                        self.onTare?(self.massBeforeTare ?? 0)
                    }
                } else {
                    self.inTare = false
                    self.massBeforeTare = liveValue
                }
                self.onSample?(liveValue, steady)
            } else if let decoded = finalDecoded {
                self.onSample?(decoded, true)
            }
            guard finalDecoded == nil else { return }
        }
    }
}
