import AppIntents
import WidgetKit
import Foundation

enum PlannerPageStorage {
    static func page(size: Int, revision: Double) -> Int {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshot.group),
              defaults.double(forKey: "widget.planner.revision.\(size)") == revision else { return 0 }
        return defaults.integer(forKey: "widget.planner.page.\(size)")
    }
}

struct PlannerPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Browse planner tasks"
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Page") var page: Int
    @Parameter(title: "Page size") var size: Int
    @Parameter(title: "Snapshot revision") var revision: Double
    init() {}
    init(page: Int, size: Int, revision: Double) {
        self.page = page
        self.size = size
        self.revision = revision
    }
    func perform() async throws -> some IntentResult {
        let file = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group)?
            .appendingPathComponent(WidgetSnapshot.filename)
        // Ignore stale taps after logout, midnight, or a new snapshot.
        guard [1, 2, 7].contains(size), let snapshot = WidgetSnapshot.read(from: file),
              snapshot.updatedAt.timeIntervalSince1970 == revision,
              let tasks = snapshot.tasks,
              let defaults = UserDefaults(suiteName: WidgetSnapshot.group) else { return .result() }
        let position = WidgetTaskPage(total: tasks.count, size: size, requested: page)
        defaults.set(position.index, forKey: "widget.planner.page.\(size)")
        defaults.set(revision, forKey: "widget.planner.revision.\(size)")
        WidgetCenter.shared.reloadTimelines(ofKind: "com.pbllc.rytivo.planner")
        return .result()
    }
}
