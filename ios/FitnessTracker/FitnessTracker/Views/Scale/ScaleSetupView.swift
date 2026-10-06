import SwiftUI
import CoreBluetooth

/// Connect a Bluetooth kitchen scale and see what it sends. Weigh something
/// and the readings appear below; if the scale uses the standard format the
/// grams are shown, otherwise the raw bytes are, which is what's needed to
/// teach the app a scale's own format.
struct ScaleSetupView: View {
    @State private var scale = BluetoothScale.shared
    @State private var commandId = ""
    @State private var commandHex = ""

    var body: some View {
        List {
            Section {
                if scale.connectedName == nil {
                    Button {
                        scale.isScanning ? scale.stopScan() : scale.startScan()
                    } label: {
                        Label(scale.isScanning ? "Stop Looking" : "Look for Scales", systemImage: "dot.radiowaves.left.and.right")
                    }
                    ForEach(scale.found.sorted { $0.rssi > $1.rssi }) { device in
                        Button {
                            scale.connect(device)
                        } label: {
                            HStack {
                                Text(device.name)
                                Spacer()
                                Text("\(device.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if let name = scale.connectedName {
                    LabeledContent("Connected to", value: name)
                    if let grams = scale.grams {
                        LabeledContent("Reading", value: "\(AmountLabel.trimmed(grams)) g")
                            .font(.title3.bold())
                    }
                    Button("Disconnect", role: .destructive) { scale.disconnect() }
                }
            } header: {
                Text("Scale")
            } footer: {
                Text(scale.status.isEmpty
                     ? "Turn the scale on first. If it isn't listed, check it isn't already connected to its own app."
                     : scale.status)
            }
            .listRowBackground(AppRowBackground())

            if !scale.log.isEmpty {
                Section {
                    ForEach(scale.log.suffix(60).reversed()) { line in
                        Text(line.text).font(.caption.monospaced())
                    }
                } header: {
                    Text("Live data")
                } footer: {
                    Text("Put something on the scale and watch these change. If the numbers don't turn into grams above, copy a few lines and send them over so the app can be taught this scale's format.")
                }
                .listRowBackground(AppRowBackground())
            }
            if !scale.writableIds.isEmpty {
                Section {
                    Picker("Send to", selection: $commandId) {
                        ForEach(scale.writableIds, id: \.self) { Text(String($0.prefix(8))).tag($0) }
                    }
                    Button("Send the kitchen-scale handshake") { scale.sendIcomonHandshake() }
                    Button("Try the full Fitdays start-up (10 messages)") { scale.sendFitdaysHandshake() }
                    Button("Try just the 3 short commands") { scale.sendFitdaysStart() }
                    TextField("Bytes, e.g. A5 01", text: $commandHex)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Send") { scale.send(hex: commandHex, to: commandId.isEmpty ? (scale.writableIds.first ?? "") : commandId) }
                        .disabled(commandHex.filter(\.isHexDigit).count < 2)
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Some scales only start sending weight after a command from their own app. This sends bytes you type to the scale. The firmware-update channel is never offered.")
                }
                .listRowBackground(AppRowBackground())
            }

            if !scale.services.isEmpty {
                Section("What it offers") {
                    ForEach(scale.services, id: \.self) { line in
                        Text(line).font(.caption.monospaced())
                    }
                }
                .listRowBackground(AppRowBackground())
            }

        }
        .appScreen()
        .navigationTitle("Kitchen Scale")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scale.writableIds) { if commandId.isEmpty { commandId = scale.writableIds.first ?? "" } }
        .onDisappear { scale.stopScan() }
    }
}
