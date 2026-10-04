import AppIntents
import WidgetKit

/// A tap on the water widget. It runs in the widget, writes the amount to the
/// shared queue and redraws; the app logs it properly next time it runs.
struct AddWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description = IntentDescription("Adds water to today's log.")

    @Parameter(title: "Amount (ml)")
    var amountMl: Int

    @Parameter(title: "Container")
    var containerId: String?

    init() {}

    init(amountMl: Int, containerId: UUID?) {
        self.amountMl = amountMl
        self.containerId = containerId?.uuidString
    }

    func perform() async throws -> some IntentResult {
        PendingWater.append(amountMl: amountMl, containerId: containerId.flatMap(UUID.init(uuidString:)))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
