import SwiftUI

struct ContentView: View {
    @Environment(PhoneConnection.self) private var phone
    @State private var treadmill = TreadmillSession()

    var body: some View {
        TabView {
            TreadmillView(session: treadmill)
            WaterView()
        }
        .tabViewStyle(.verticalPage)
    }
}

private struct TreadmillView: View {
    let session: TreadmillSession

    var body: some View {
        VStack(spacing: 10) {
            if session.isRunning, let startedAt = session.startedAt {
                Text(startedAt, style: .timer)
                    .font(.system(.title, design: .rounded).monospacedDigit().weight(.semibold))
                if let heartRate = session.heartRate {
                    Label("\(heartRate)", systemImage: "heart.fill").foregroundStyle(.red)
                }
                Button("Finish") { Task { await session.finish() } }
                    .tint(.green)
                Button("Discard", role: .destructive) { session.discard() }
                    .font(.caption)
            } else {
                Image(systemName: "figure.walk.treadmill")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                Text("Incline Walk")
                    .font(.headline)
                Button("Start") { Task { await session.start() } }
                    .tint(.blue)
                    .disabled({ if case .starting = session.state { return true } else { return false } }())
                if case .failed(let message) = session.state {
                    Text(message).font(.caption2).foregroundStyle(.red)
                }
            }
        }
    }
}

private struct WaterView: View {
    @Environment(PhoneConnection.self) private var phone

    var body: some View {
        VStack(spacing: 8) {
            Label(String(format: "%.2f L", Double(phone.waterTodayMl) / 1000), systemImage: "drop.fill")
                .font(.headline)
                .foregroundStyle(.cyan)
            ProgressView(value: min(Double(phone.waterTodayMl) / Double(max(phone.waterTargetMl, 1)), 1))
                .tint(.cyan)
            ForEach(phone.waterButtonsMl.prefix(3), id: \.self) { ml in
                Button("+\(ml) ml") { phone.sendWater(ml) }
                    .tint(.cyan)
            }
        }
        .padding(.horizontal, 4)
    }
}
