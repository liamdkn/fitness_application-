import SwiftUI
import CoreBluetooth

/// Connect the Bluetooth kitchen scale: find it, connect, see the reading,
/// disconnect. After the first connection the app reconnects by itself.
struct ScaleSetupView: View {
    @State private var scale = BluetoothScale.shared

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
        }
        .appScreen()
        .navigationTitle("Kitchen Scale")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { scale.stopScan() }
    }
}
