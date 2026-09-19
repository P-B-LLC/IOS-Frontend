import Foundation
import WidgetKit

@MainActor
enum WidgetPublisher {
    private static var last: WidgetSnapshot?
    private static var file: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group)?
            .appendingPathComponent(WidgetSnapshot.filename)
    }

    static func publish(_ snapshot: WidgetSnapshot) {
        guard let file else { return }
        // View observation includes save-state changes. Do not spend a reload
        // budget on renders whose displayed content did not change.
        if let last, last.day == snapshot.day,
           last.tasks == snapshot.tasks, last.nutrition == snapshot.nutrition { return }
        do {
            var dated = snapshot
            dated.updatedAt = Date()
            let data = try JSONEncoder().encode(dated)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            last = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Keep the last confirmed snapshot; its timestamp remains honest.
            // A subsequent store update or foreground entry retries the write.
        }
    }

    static func clear() {
        last = nil
        if let file {
            // Overwrite first so a failed unlink cannot leave readable account data.
            try? Data().write(to: file, options: [.atomic, .completeFileProtection])
            try? FileManager.default.removeItem(at: file)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
