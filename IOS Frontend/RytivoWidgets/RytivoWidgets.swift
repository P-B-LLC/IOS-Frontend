import SwiftUI
import WidgetKit
import AppIntents

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var plannerPages: [Int: Int] = [:]
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { TodayEntry(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = load()
        let midnight = Calendar.current.startOfDay(for: entry.date).addingTimeInterval(36 * 3600)
        let nextDay = Calendar.current.startOfDay(for: midnight)
        // An explicit empty entry prevents yesterday's totals from rolling into today.
        completion(Timeline(entries: [entry, TodayEntry(date: nextDay, snapshot: nil)],
                            policy: .after(entry.date.addingTimeInterval(3600))))
    }
    private func load() -> TodayEntry {
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group)?
            .appendingPathComponent(WidgetSnapshot.filename)
        let snapshot = WidgetSnapshot.read(from: url)
        var pages: [Int: Int] = [:]
        if let snapshot {
            for size in [1, 2, 7] {
                pages[size] = PlannerPageStorage.page(size: size, revision: snapshot.updatedAt.timeIntervalSince1970)
            }
        }
        return TodayEntry(date: .now, snapshot: snapshot, plannerPages: pages)
    }
}

enum WidgetFocus: String {
    case day, workout, food, planner
    var title: String {
        switch self {
        case .day: "My day"
        case .workout: "Today's workout"
        case .food: "Daily nutrition"
        case .planner: "My planner"
        }
    }
    var symbol: String {
        switch self {
        case .day: "sun.max"
        case .workout: "dumbbell"
        case .food: "fork.knife"
        case .planner: "checklist"
        }
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    let focus: WidgetFocus
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    private var accent: Color { focus == .food ? .teal : .orange }
    private func font(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "NunitoSans-Bold" : "NunitoSans-Regular", size: size)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(focus.title.uppercased(), systemImage: focus.symbol)
                .font(font(10, bold: true)).foregroundStyle(accent).lineLimit(1)
            if let snapshot = entry.snapshot, snapshot.isCurrent(at: entry.date) {
                if focus == .food {
                    food(snapshot.nutrition)
                } else {
                    tasks(snapshot.tasks)
                    if focus == .day, family == .systemMedium, let food = snapshot.nutrition {
                        Text("\(number(food.calories)) kcal logged · \(number(food.protein))g protein")
                            .font(font(11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if focus != .planner || snapshot.tasks?.isEmpty != false {
                  HStack(spacing: 3) {
                    Text("Updated")
                    Text(snapshot.updatedAt, style: .time)
                }
                .font(font(9)).foregroundStyle(.secondary)
                }
            } else {
                Text("A fresh start.")
                    .font(font(21, bold: true))
                Text("Open Rytivo to see today's progress.")
                    .font(font(12)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.primary)
        .containerBackground(for: .widget) {
            (scheme == .dark ? Color(red: 0.09, green: 0.10, blue: 0.10)
             : Color(red: 0.99, green: 0.97, blue: 0.94))
        }
        .widgetURL(URL(string: "rytivo://widget/\(focus.rawValue)"))
        .privacySensitive()
    }

    @ViewBuilder private func tasks(_ items: [WidgetSnapshot.Item]?) -> some View {
        if let items {
            let filtered = focus == .workout ? items.filter(\.workout) : items
            let counted = filtered.filter(\.completable)
            let done = counted.filter(\.complete).count
            if filtered.isEmpty {
                Text(focus == .workout ? "Room to recover." : "Make room for you.")
                    .font(font(19, bold: true))
                Text(focus == .workout ? "No workout planned today." : "Nothing planned today. Open to add a task.")
                    .font(font(12)).foregroundStyle(.secondary)
            } else {
              VStack(alignment: .leading, spacing: 4) {
                Text("\(done) / \(counted.count) complete")
                    .font(font(20, bold: true)).minimumScaleFactor(0.75).lineLimit(1)
                ProgressView(value: Double(done), total: Double(max(counted.count, 1))).tint(accent)
                let ordered = filtered.filter { !$0.complete } + filtered.filter(\.complete)
                let size = family == .systemLarge ? 7 : (family == .systemSmall || focus == .day ? 1 : 2)
                let page = WidgetTaskPage(total: ordered.count, size: size,
                                          requested: focus == .planner ? (entry.plannerPages[size] ?? 0) : 0)
                ForEach(Array(ordered[page.range].enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Image(systemName: item.complete ? "checkmark.circle.fill" : (item.completable ? "circle" : "calendar"))
                            .foregroundStyle(item.complete ? Color.green : accent)
                        Text(item.title).lineLimit(1)
                        if item.stepsTotal > 0 && family != .systemSmall {
                            Text("\(item.stepsDone)/\(item.stepsTotal)").foregroundStyle(.secondary)
                        }
                    }.font(font(12))
                }
                if focus == .planner, let snapshot = entry.snapshot {
                    HStack(spacing: 2) {
                        pageButton("Previous", symbol: "chevron.left", page: page.index - 1,
                                   size: size, revision: snapshot.updatedAt.timeIntervalSince1970,
                                   disabled: page.index == 0)
                        Spacer(minLength: 0)
                        Text("\(page.range.lowerBound + 1)–\(page.range.upperBound) of \(ordered.count)")
                            .font(font(10)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                            .accessibilityLabel("Items \(page.range.lowerBound + 1) through \(page.range.upperBound) of \(ordered.count)")
                        Spacer(minLength: 0)
                        pageButton("Next", symbol: "chevron.right", page: page.index + 1,
                                   size: size, revision: snapshot.updatedAt.timeIntervalSince1970,
                                   disabled: page.index == page.count - 1)
                    }
                    .accessibilityValue("Updated \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                }
              }
            }
        } else {
            Text("Open to update your plan.").font(font(16, bold: true))
        }
    }

    private func pageButton(_ title: String, symbol: String, page: Int,
                            size: Int, revision: Double, disabled: Bool) -> some View {
        Button(intent: PlannerPageIntent(page: page, size: size, revision: revision)) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(disabled ? Color.secondary.opacity(0.3) : accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel("\(title) tasks")
    }

    @ViewBuilder private func food(_ value: WidgetSnapshot.Nutrition?) -> some View {
        if let value {
          VStack(alignment: .leading, spacing: 4) {
            Text("\(number(value.calories)) kcal")
                .font(font(22, bold: true)).lineLimit(1).minimumScaleFactor(0.7)
            Text("of \(number(value.calorieGoal)) kcal")
                .font(font(11)).foregroundStyle(.secondary)
            ProgressView(value: WidgetSnapshot.progress(value.calories, toward: value.calorieGoal)).tint(.orange)
            HStack(spacing: 8) {
                macro("Protein", value.protein, value.proteinGoal, .orange)
                macro("Carbs", value.carbs, value.carbsGoal, .teal)
                macro("Fat", value.fat, value.fatGoal, .purple)
            }
          }
        } else {
            Text("Open to update your food log.").font(font(16, bold: true))
        }
    }
    private func macro(_ title: String, _ amount: Decimal, _ goal: Decimal, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).foregroundStyle(.secondary)
            Text("\(number(amount))g").lineLimit(1).minimumScaleFactor(0.7)
            ProgressView(value: WidgetSnapshot.progress(amount, toward: goal)).tint(color)
        }.font(font(10)).frame(maxWidth: .infinity)
    }
    private func number(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

struct RytivoWidget: Widget {
    let focus: WidgetFocus

    // Widget requires init(); the bundle also supplies a focus for each entry.
    init() {
        self.focus = .day
    }

    init(focus: WidgetFocus) {
        self.focus = focus
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.pbllc.rytivo.\(focus.rawValue)", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry, focus: focus)
        }
        .configurationDisplayName(focus.title)
        .description("Your latest daily progress. Tap to continue in Rytivo.")
        .supportedFamilies(focus == .planner ? [.systemSmall, .systemMedium, .systemLarge] : [.systemSmall, .systemMedium])
    }
}

@main
struct RytivoWidgets: WidgetBundle {
    var body: some Widget {
        RytivoWidget(focus: .day)
        RytivoWidget(focus: .workout)
        RytivoWidget(focus: .food)
        RytivoWidget(focus: .planner)
    }
}
