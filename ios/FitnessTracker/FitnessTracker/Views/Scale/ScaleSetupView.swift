import SwiftUI
import CoreBluetooth

/// Pair the Bluetooth kitchen scale once; the app remembers it and reconnects
/// whenever the scale wakes. Unpair if something goes wrong or the scale is
/// replaced.
struct ScaleSetupView: View {
    @State private var scale = BluetoothScale.shared
    @State private var confirmingUnpair = false

    var body: some View {
        List {
            if scale.isPaired {
                Section {
                    LabeledContent("Paired scale", value: scale.pairedName ?? "Kitchen scale")
                    LabeledContent("Status") {
                        Text(scale.connectedName != nil ? "Connected" : "Waiting for it to wake")
                            .foregroundStyle(scale.connectedName != nil ? AppColor.success : .secondary)
                    }
                    if scale.connectedName != nil {
                        if let grams = scale.live ?? scale.grams {
                            LabeledContent("Reading", value: "\(AmountLabel.trimmed(grams)) g")
                                .font(.title3.bold())
                        }
                        if let unit = scale.unit {
                            LabeledContent("Scale shows", value: ScaleDecoding.unitName(unit))
                        }
                        LabeledContent("TARE presses seen", value: "\(scale.tarePresses)")
                    } else {
                        Button("Reconnect now") { scale.reconnectNow() }
                    }
                    Button("Unpair Scale", role: .destructive) { confirmingUnpair = true }
                } header: {
                    Text("Scale")
                } footer: {
                    Text(scale.connectedName != nil
                         ? "It reconnects by itself next time - press a button on the scale or put something on it."
                         : (scale.status.isEmpty ? "Press a button on the scale or put something on it to wake it." : scale.status))
                }
                .listRowBackground(AppRowBackground())
            } else {
                Section {
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
                } header: {
                    Text("Pair a Scale")
                } footer: {
                    Text(scale.status.isEmpty
                         ? "Turn the scale on first, and close its own app. Tap your scale in the list once to pair it - it's MY_SCALE for the Phoenix."
                         : scale.status)
                }
                .listRowBackground(AppRowBackground())
            }
        }
        .appScreen()
        .navigationTitle("Kitchen Scale")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Unpair this scale?", isPresented: $confirmingUnpair, titleVisibility: .visible) {
            Button("Unpair", role: .destructive) { scale.unpair() }
        } message: {
            Text("The app forgets it and stops connecting. You can pair it again from this screen.")
        }
        .onAppear { scale.reconnectKnown() }
        .onDisappear { scale.stopScan() }
    }
}
