//
//  GuidedHomeView.swift
//  IOS Frontend
//
//  Connected-flow presentation. Every value and destination below continues
//  to come from the existing stores and personalization settings.
//

import SwiftUI

/// Scoped to Home: stronger night-mode contrast without changing other screens
/// or the approved light appearance. Progress tracks are not card outlines.
private enum HomeWidgetColors {
    static var secondaryText: Color {
        .repbaseDynamic(light: Color.secondary, dark: Color(hex: 0xC7C2BD))
    }

    static var border: Color {
        .repbaseDynamic(
            light: RepbasePalette.espresso.opacity(0.12),
            dark: Color(hex: 0x605B56)
        )
    }

    static var progressTrack: Color {
        .repbaseDynamic(
            light: RepbasePalette.espresso.opacity(0.12),
            dark: Color(hex: 0x77716B)
        )
    }

    static var fatProgress: Color {
        .repbaseDynamic(light: RepbasePalette.cocoa, dark: Color(hex: 0xE5C5AC))
    }
}

/// What home leads with.
///
/// The personalization flow asks this outright and calls it "home screen
/// emphasis", so the honest reading is that it decides the order of the day.
nonisolated enum HomeEmphasis: String {
    case training = "Training"
    case movement = "Movement"
    case nutrition = "Nutrition"
}

struct GuidedHomeView: View {
    @Environment(SocialProfileStore.self) private var profileStore

    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var emphasis = HomeEmphasis.training
#if DEBUG
    // The emphasis is set four taps into a settings flow, and simctl has no
    // tap, so the three orderings cannot otherwise be looked at.
    private let forcedEmphasis = ProcessInfo.processInfo
        .environment["REPBASE_EMPHASIS"].flatMap(HomeEmphasis.init(rawValue:))
#endif


    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay.current

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    GuidedHomeHeader(date: context.date)

                    GuidedHomeWeekStrip(
                        today: context.date,
                        selection: $selectedDate
                    )
                    GuidedDayFlow(
                        selectedDate: selectedDate,
                        today: context.date,
                        emphasis: emphasis
                    )


                    GuidedHomeErrors()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, RepbaseDesign.bottomBarClearance)
            }
            .scrollIndicators(.hidden)
            .minimizesBottomBarOnScroll()
            .background {
                Color(uiColor: .systemBackground).ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            // Keyed on the connection: home appears before the session is
            // restored, and a bare .task would ask a store with nothing to
            // answer from and never ask again.
            .task(id: profileStore.isConnected) {
#if DEBUG
                if let forcedEmphasis {
                    emphasis = forcedEmphasis
                    return
                }
#endif
                guard let values = try? await profileStore.personalization() else {
                    return
                }
                emphasis = HomeEmphasis(rawValue: values.emphasis) ?? .training
            }

            .homeTimeScreen(timeOfDay)
        }
    }
}

// MARK: - Header

private struct GuidedHomeHeader: View {
    @Environment(AuthenticationStore.self) private var authentication
    @Environment(SocialProfileStore.self) private var profiles
    @Environment(\.homeTimeOfDay) private var timeOfDay
    @Environment(\.repbaseNavigate) private var navigate

    let date: Date

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(greeting), \(firstName)")
                    .font(.community(.footnote, weight: .semibold))
                    .foregroundStyle(HomeWidgetColors.secondaryText)
                Text("Make today yours.")
                    .font(.community(size: 24, weight: .bold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { navigate(.account) } label: {
                Group {
                    if let data = profiles.profile?.profileImageData,
                       let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if let photo = profiles.profile?.profilePhotoURL,
                              let url = URL(string: photo) {
                        RemoteImage(url: url, maxPixel: 144) {
                            initialsAvatar
                        } failure: {
                            initialsAvatar
                        }
                        .scaledToFill()
                    } else {
                        initialsAvatar
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open your profile")
        }
        .frame(minHeight: 48)
    }

    private var initialsAvatar: some View {
        Text(profiles.profile?.initials ?? String(firstName.prefix(1)))
            .font(.community(.footnote, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 48, height: 48)
            .background(RepbasePalette.ink, in: Circle())
    }

    private var firstName: String {
        guard case .signedIn(let user) = authentication.phase else { return "Your day" }
        let given = user.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return given.isEmpty ? user.username : given
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

}

// MARK: - Week selector

private struct GuidedHomeWeekStrip: View {
    @Environment(PlannerStore.self) private var planner
    @Environment(WorkoutStore.self) private var workouts
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let today: Date
    @Binding var selection: Date

    var body: some View {
        HStack(spacing: 3) {
            ForEach(weekDates, id: \.self) { day in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selection = day
                    }
                    planner.select(day)
                } label: {
                    VStack(spacing: 2) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.community(.caption2, weight: .bold))
                        Text(day.formatted(.dateTime.day()))
                            .font(.community(.subheadline, weight: .bold))

                        Circle()
                            .fill(dayHasContent(day) ? dotColor(for: day) : .clear)
                            .frame(width: 3, height: 3)
                    }
                    .foregroundStyle(isSelected(day) ? Color.white : timeOfDay.canvasPrimaryText)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background {
                        Capsule()
                            .fill(isSelected(day) ? timeOfDay.accent : Color.clear)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                .accessibilityAddTraits(isSelected(day) ? [.isSelected] : [])
            }
        }
        // Seven days across, same as the planner's. Left uncapped, the dates
        // stacked a digit per line -- "1 / 0" for the tenth -- and the
        // selected day became a tall bar. VoiceOver reads the full date from
        // the label on each button, so nothing is lost by holding the glyphs
        // to a size that fits a seventh of the screen.
        .typeSizeCeiling()
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selection)
        else { return [selection] }
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
    }

    private func isSelected(_ day: Date) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: selection)
    }

    private func dayHasContent(_ day: Date) -> Bool {
        // The Home strip may start on the previous Sunday, but the workout
        // store holds the current Monday-based week. Never borrow the next
        // Sunday's workout just because both dates share a weekday.
        let weekday = workouts.weekday(forDateString: PlannerStore.dateString(day))
        return planner.hasEntries(on: day)
            || weekday.map { !workouts.workouts(on: $0).isEmpty } == true
    }

    private func dotColor(for day: Date) -> Color {
        isSelected(day) ? Color.white : timeOfDay.accent
    }
}

// MARK: - Connected daily flow

private struct GuidedDayFlow: View {
    @Environment(WorkoutStore.self) private var workouts
    @Environment(PlannerStore.self) private var planner
    @Environment(FoodTrackingStore.self) private var food
    @Environment(CycleStore.self) private var cycles
    @Environment(ActivityStore.self) private var activity
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var widgetHeight = 184
    @Environment(\.homeTimeOfDay) private var timeOfDay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Sends the app to another tab rather than pushing that tab's page onto
    /// this one.
    ///
    /// Home summarises four other areas and offers to open each. Pushing
    /// them left the bottom bar lit on Home while you read a workout, so the
    /// bar described where you started rather than where you were.
    @Environment(\.repbaseNavigate) private var navigate

    @State private var isConfirmingClear = false
    @State private var displayedFoodTotal: NutritionAmount?
    @State private var displayedMealCount: Int?
    @State private var isHomeVisible = false
    @State private var foodProgressPulse = false
    @State private var foodProgressTask: Task<Void, Never>?

    let selectedDate: Date
    let today: Date
    var emphasis = HomeEmphasis.training

    /// The stages of the day, in the order this person asked for.
    ///
    /// Up Next and the momentum figures stay where they are: one is what is
    /// happening next regardless of what matters most, and the other is a
    /// footer. What moves is which of the three chapters leads.
    private enum Chapter: String {
        case movement = "MOVEMENT"
        case training = "TRAINING"
        case fuel = "FUEL"
        case finish = "FINISH"
    }

    private var chapters: [Chapter] {
        switch emphasis {
        case .training:
            [.training, .fuel, .finish]
        case .nutrition:
            [.fuel, .training, .finish]
        case .movement:
            // Movement is the one emphasis with no chapter of its own, so it
            // gets one rather than quietly behaving like Training. Steps move
            // out of the header and lead the day.
            [.movement, .training, .fuel, .finish]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                upNextSection
            }
            .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(HomeWidgetColors.border, lineWidth: 1)
            }
            if emphasis == .nutrition { fuelSection(number: 1) }
            movementAndTraining
            if emphasis != .nutrition { fuelSection(number: 2) }
            dayAgenda
            DisclosureGroup("More from your day") {
                finishSection(number: 3)
                if emphasis == .movement { movementSection(number: 1) }
                momentumSection
                if cycles.activeCycle == nil, workouts.hasAnythingScheduled {
                    Button("Clear my schedule", role: .destructive) { isConfirmingClear = true }
                        .disabled(workouts.isSaving)
                        .frame(minHeight: 44)
                }
            }
            .font(.community(.footnote, weight: .semibold))
            .tint(HomeWidgetColors.secondaryText)
        }
        .onAppear {
            isHomeVisible = true
            if displayedFoodTotal == nil {
                synchronizeFoodProgress()
            }
            presentLatestMealLogIfNeeded()
        }
        .onDisappear {
            isHomeVisible = false
            foodProgressTask?.cancel()
        }
        .onChange(of: selectedDate) { _, _ in
            foodProgressTask?.cancel()
            foodProgressPulse = false
            synchronizeFoodProgress()
            presentLatestMealLogIfNeeded()
        }
        .onChange(of: food.total(on: selectedDate)) { _, newTotal in
            guard isHomeVisible, food.latestMealLogEvent == nil else { return }
            displayedFoodTotal = newTotal
            displayedMealCount = food.loggedMealCount(on: selectedDate)
        }
        .onChange(of: food.latestMealLogEvent?.id) { _, _ in
            guard isHomeVisible else { return }
            presentLatestMealLogIfNeeded()
        }
    }

    @ViewBuilder
    private func chapterView(_ chapter: Chapter, number: Int) -> some View {
        switch chapter {
        case .movement: movementSection(number: number)
        case .training: trainingSection(number: number)
        case .fuel: fuelSection(number: number)
        case .finish: finishSection(number: number)
        }
    }

    /// Personalization chooses the order; the labels remain conversational.
    private func stageNumber(_ number: Int, _ chapter: Chapter) -> String {
        // Personalization still chooses the order; avoid making it read like
        // numbered report sections.
        switch chapter {
        case .movement: "Your movement"
        case .training: "A little stronger today"
        case .fuel: "Fuel your day"
        case .finish: "Still to do"
        }
    }

    private func movementSection(number: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            stageLabel(stageNumber(number, .movement), color: timeOfDay.accent)
            // Explains itself when empty, which home does not normally do. The
            // reason it stays quiet elsewhere is that a card about Health is
            // noise on a page nobody opened to think about Health -- and that
            // stops being true the moment somebody asks for movement to lead.
            // A chapter with a heading and nothing under it is worse.
            StepsWidget(explainsWhenEmpty: true)
        }
        .padding(.vertical, 14)
    }

    private var flowHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("YOUR DAY")
                    .font(.community(.caption2, weight: .bold))
                    .tracking(0.55)
                    .foregroundStyle(timeOfDay.accent)
                Text("Follow what matters.")
                    .font(.community(.title3, weight: .bold))
                    .foregroundStyle(timeOfDay.primaryText)
            }
            Spacer()
            Text(selectedDate.formatted(.dateTime.weekday(.abbreviated).day()))
                .font(.community(.caption, weight: .bold))
                .foregroundStyle(HomeWidgetColors.secondaryText)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var upNextSection: some View {
        Button { navigate(.planner) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Next up")
                    Spacer()
                    Text(remainingTasks.isEmpty ? "Calendar →" : "\(remainingTasks.count) tasks →")
                }
                .font(.community(.footnote, weight: .semibold))
                .foregroundStyle(HomeWidgetColors.secondaryText)
                if let entry = nextEntry {
                    Text(entry.title)
                        .font(.community(.headline, weight: .bold))
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(entry.displayTime ?? "No time set") · \(entry.priority.title) priority")
                        .font(.community(.footnote))
                        .foregroundStyle(HomeWidgetColors.secondaryText)
                } else {
                    Text("Your schedule is clear")
                        .font(.community(.headline, weight: .bold))
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                }
                if let following = planner.entries(on: selectedDate)
                    .filter({ !$0.isComplete || !$0.isCompletable })
                    .sorted(by: { ($0.time ?? "99:99:99") < ($1.time ?? "99:99:99") })
                    .dropFirst().first {
                    Text("Then: \(following.title) · \(following.displayTime ?? "No time set")")
                        .font(.community(.caption2, weight: .semibold))
                        .foregroundStyle(HomeWidgetColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your calendar")
    }

    @ViewBuilder
    private var movementAndTraining: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                stepsCard
                trainingSection(number: 1)
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                stepsCard.frame(width: 146)
                trainingSection(number: 1)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your steps")
                .font(.community(.footnote, weight: .semibold))
                .foregroundStyle(HomeWidgetColors.secondaryText)
            ZStack {
                Circle().stroke(HomeWidgetColors.progressTrack, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: activity.stepGoal > 0
                          ? min(max(Double(activity.stepsToday ?? 0) / Double(activity.stepGoal), 0), 1) : 0)
                    .stroke(RepbasePalette.sage, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 52, height: 52)
            .padding(7)
            .accessibilityHidden(true)
            Text(activity.stepsToday?.formatted() ?? "—")
                .font(.community(size: 24, weight: .bold))
            Text(activity.stepsToday == nil ? "Not reported today" : "of \(activity.stepGoal.formatted()) steps")
                .font(.community(.caption2, weight: .semibold))
                .foregroundStyle(HomeWidgetColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(minHeight: widgetHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(HomeWidgetColors.border, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }

    private func trainingSection(number: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A little stronger today")
                .font(.community(.caption2, weight: .semibold))
                .foregroundStyle(Color.white)
            Text(workout?.name ?? "Plan your workout")
                .font(.community(size: 24, weight: .bold))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(workoutMetadata)
                .font(.community(.footnote))
                .foregroundStyle(Color.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Button { navigate(workoutRoute) } label: {
                Text("\(workoutActionTitle) workout →")
                    .font(.community(.footnote, weight: .semibold))
                    .foregroundStyle(RepbasePalette.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityHint(workoutDetail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(minHeight: widgetHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(trainingSurface, in: RoundedRectangle(cornerRadius: 28))
        .contextMenu {
            if cycles.activeCycle == nil, workouts.hasAnythingScheduled {
                Button("Clear my schedule", role: .destructive) { isConfirmingClear = true }
                    .disabled(workouts.isSaving)
            }
        }
        // Asked about, unlike the destructive controls here that act on a tap:
        // this empties weeks of planning at once and cannot be undone.
        .confirmationDialog(
            "Clear everything you have planned?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear my schedule", role: .destructive) {
                Task { await workouts.clearSchedule() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Every workout you have planned is removed, past days included, so you can plan again from scratch. Workouts you have already done stay in your history.")
        }
    }

    private func fuelSection(number: Int) -> some View {
        let total = displayedFoodTotal ?? food.total(on: selectedDate)
        let goals = food.goals
        let mealCount = displayedMealCount ?? food.loggedMealCount(on: selectedDate)

        let calorieProgress = goals.calories > 0
            ? min(max(total.calories.nutritionDouble / goals.calories.nutritionDouble, 0), 1) : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fuel your day")
                    .font(.community(.footnote, weight: .semibold))
                    .foregroundStyle(HomeWidgetColors.secondaryText)
                Spacer()
                Button { navigate(.food) } label: {
                    Text("Log food +")
                        .font(.community(.footnote, weight: .semibold))
                        .foregroundStyle(HomeWidgetColors.secondaryText)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            Text("\(total.calories.nutritionText) / \(goals.calories.nutritionText) kcal")
                .font(.community(size: 24, weight: .bold))
                .foregroundStyle(timeOfDay.primaryText)
                .contentTransition(.numericText(value: total.calories.nutritionDouble))
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(HomeWidgetColors.progressTrack)
                    Capsule().fill(RepbasePalette.sage)
                        .frame(width: proxy.size.width * calorieProgress)
                }
            }
            .frame(height: 5)
            .accessibilityHidden(true)

            HStack(spacing: 10) {
                GuidedMacroMetric(
                    label: "Protein",
                    value: total.proteinGrams,
                    goal: goals.proteinGrams,
                    color: RepbasePalette.caramel,
                    animationDelay: 0.04
                )
                GuidedMacroMetric(
                    label: "Carbs",
                    value: total.carbohydrateGrams,
                    goal: goals.carbohydrateGrams,
                    color: RepbasePalette.sage,
                    animationDelay: 0.12
                )
                GuidedMacroMetric(
                    label: "Fat",
                    value: total.fatGrams,
                    goal: goals.fatGrams,
                    color: HomeWidgetColors.fatProgress,
                    animationDelay: 0.20
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            GuidedFoodLivingSurface(
                mealCount: mealCount,
                isPulsing: foodProgressPulse
            )
        }
        .scaleEffect(foodProgressPulse && !reduceMotion ? 1.008 : 1)
        .offset(y: foodProgressPulse && !reduceMotion ? -2 : 0)
    }

    private func finishSection(number: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                // "Finish" is what is left of today. When everything left is
                // late that word is wrong twice over: there is nothing of
                // today's to finish, and it hides that the work is overdue.
                // Tinted to match the planner's own Past due section, so the
                // same thing reads the same way in both places.
                stageLabel(
                    everythingLeftIsPastDue
                        ? String(format: "%02d · PAST DUE", number)
                        : stageNumber(number, .finish),
                    color: everythingLeftIsPastDue
                        ? Color(hex: 0xD8557A)
                        : HomeWidgetColors.secondaryText
                )
                Text(taskSummary)
                    .font(.community(.headline))
                    .foregroundStyle(timeOfDay.primaryText)
                Text(taskDetail)
                    .font(.community(.caption))
                    .foregroundStyle(HomeWidgetColors.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                navigate(.planner)
            } label: {
                RepbaseTonalActionLabel(
                    title: "Open",
                    systemImage: "list.bullet.rectangle"
                )
            }
            .buttonStyle(RepbaseTonalButtonStyle(tone: .outline))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// A read-only view of the same selected-day entries used by the planner.
    /// No truncation: all-day and overlapping entries remain visible.
    private var dayAgenda: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your day")
                    .font(.community(.headline, weight: .bold))
                Spacer()
                Button { navigate(.planner) } label: {
                    Label("Calendar", systemImage: "arrow.right")
                        .font(.community(.footnote, weight: .semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            Text("\(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) · \(planner.entries(on: selectedDate).count) entries")
                .font(.community(.footnote))
                .foregroundStyle(HomeWidgetColors.secondaryText)
            ForEach(planner.entries(on: selectedDate)) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entry.displayTime ?? "No time set") · \(entry.title)")
                        .font(.community(.footnote, weight: .semibold))
                    Text(entry.category.title)
                        .font(.community(.caption))
                        .foregroundStyle(HomeWidgetColors.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
            if planner.entries(on: selectedDate).isEmpty {
                Text("Nothing scheduled for this day.")
                    .font(.community(.subheadline))
                    .foregroundStyle(HomeWidgetColors.secondaryText)
            }
        }
        .foregroundStyle(timeOfDay.canvasPrimaryText)
        .padding(16)
        .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(HomeWidgetColors.border, lineWidth: 1)
        }
    }

    private var momentumSection: some View {
        HStack(spacing: 0) {
            momentumMetric(
                value: workouts.trainingStats.completedThisWeek.formatted(),
                label: "WORKOUTS"
            )
            momentumDivider
            momentumMetric(
                value: workouts.trainingStats.currentStreakWeeks.formatted(),
                label: "WEEK STREAK"
            )
            momentumDivider
            momentumMetric(
                value: weeklyProgress.formatted(.percent.precision(.fractionLength(0))),
                label: "WEEKLY GOAL"
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            momentumSurface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func momentumMetric(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.community(.title3, weight: .bold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Text(label)
                .font(.community(.caption2, weight: .bold))
                .tracking(0.25)
                .foregroundStyle(HomeWidgetColors.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private var momentumDivider: some View {
        Rectangle()
            .fill(HomeWidgetColors.border)
            .frame(width: 1, height: 40)
    }

    private func stageLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.community(.caption2, weight: .bold))
            .tracking(0.45)
            .foregroundStyle(color)
    }

    /// Where the training card sends you.
    ///
    /// A day when the card is about one, the week when it is not. Both land
    /// on the Training tab; the day is pushed onto it, so the bar reads
    /// Training either way and back goes to the week rather than to Home.
    private var workoutRoute: RepbaseDestination {
        if let weekday { .workoutDay(weekday) } else { .workouts }
    }

    private var isToday: Bool {
        Calendar.current.isDate(selectedDate, inSameDayAs: today)
    }

    private var weekday: Weekday? {
        // The card and its destination must refer to the same concrete day.
        // An out-of-week date can open Training, not a different day's plan.
        workouts.weekday(forDateString: PlannerStore.dateString(selectedDate))
    }

    private var workout: Workout? {
        guard let weekday else { return nil }
        return workouts.workout(on: weekday)
    }

    private var activeSession: ActiveWorkoutSession? {
        isToday ? workouts.activeSession : nil
    }

    /// Whether the day's workout has already been trained.
    ///
    /// The card knew only about a session *in progress*, so the moment one
    /// finished it fell back to offering "Start" — inviting somebody to do
    /// again the workout the very next screen was showing as done, with its
    /// sets and its volume. The same session the planner reads; asked the
    /// same way, so Home and the calendar cannot come to different views of
    /// one day.
    private var isTrained: Bool {
        guard let workout else { return false }
        return workouts.isCompleted(workout: workout, on: selectedDate)
    }

    /// A session already finished wins over one in progress: starting a second
    /// one is possible, but "Start" is the wrong thing for the card to lead
    /// with on a day that has been trained.
    private var workoutActionTitle: String {
        if workout == nil { return "Plan" }
        if isTrained { return "View" }
        return activeSession == nil ? "Start" : "Continue"
    }

    private var workoutActionSymbol: String {
        if workout == nil { return "calendar.badge.plus" }
        return isTrained ? "checkmark" : "play.fill"
    }

    private var workoutMetadata: String {
        guard let workout else { return "Choose a plan or build something new" }
        let exercises = workout.exercises.count
        return "\(exercises) \(exercises == 1 ? "exercise" : "exercises") · \(workout.totalSets) target sets"
    }

    private var workoutDetail: String {
        if let activeSession {
            return "Session in progress · \(activeSession.workoutName)"
        }
        // Said before the exercise list, because "Incline Chest and 2 more"
        // beside a Start button is what made a finished day read as an
        // unstarted one.
        if isTrained { return "Trained · view the session" }
        guard let workout else { return "Your training plan for this day is open" }
        if let first = workout.exercises.first {
            let remaining = max(workout.exercises.count - 1, 0)
            return remaining == 0 ? first.name : "\(first.name) and \(remaining) more"
        }
        return workout.type.title
    }

    /// The next thing on the day being looked at, and only that day.
    ///
    /// Overdue work is deliberately not folded in. A task left unfinished on
    /// Monday is late, not "up next" on Tuesday, and announcing it as the
    /// day's next thing made a day with nothing on it read as a day with
    /// something on it. It is still shown, under "still to do" below and in
    /// the planner's own past due section, both of which name it for what it
    /// is. This also makes today behave like every other day: only today ever
    /// mixed in work from other dates.
    ///
    /// Sorting on time alone is sound only because every entry here shares a
    /// date. Mixing days in let a 07:00 from last week outrank this morning,
    /// since nothing in the comparison looked at the date at all.
    private var nextEntry: PlannerEntry? {
        planner.entries(on: selectedDate)
            .filter { !$0.isComplete || !$0.isCompletable }
            .sorted { ($0.time ?? "99:99:99") < ($1.time ?? "99:99:99") }
            .first
    }

    private func nextEntryEyebrow(_ entry: PlannerEntry) -> String {
        guard let time = entry.displayTime else { return "UP NEXT" }
        return "UP NEXT · \(time)"
    }

    private var remainingTasks: [PlannerEntry] {
        let overdue = isToday
            ? planner.pastDue.filter { $0.isCompletable && !$0.isComplete }
            : []
        let onDay = planner.entries(on: selectedDate)
            .filter { $0.isCompletable && !$0.isComplete }
        var seen: Set<PlannerEntry.ID> = []
        return (overdue + onDay).filter { seen.insert($0.id).inserted }
    }

    /// Whether a task is late rather than merely unfinished.
    private func isPastDue(_ task: PlannerEntry) -> Bool {
        planner.pastDue.contains { $0.isSameEntry(as: task) }
    }

    /// Whether everything still to do is late.
    ///
    /// All of it, not any of it. A day holding one overdue task and one of its
    /// own still has work of its own in it, and calling the whole section past
    /// due would misdescribe the second.
    private var everythingLeftIsPastDue: Bool {
        !remainingTasks.isEmpty && remainingTasks.allSatisfy(isPastDue)
    }

    private var taskSummary: String {
        let count = remainingTasks.count
        guard count > 0 else { return "Everything is done" }
        let noun = "task\(count == 1 ? "" : "s")"
        return everythingLeftIsPastDue
            ? "\(count) \(noun) past due"
            : "\(count) \(noun) still to do"
    }

    private var taskDetail: String {
        guard let task = remainingTasks.first else { return "Nothing else needs your attention" }
        // Named with the day it was due. A bare title reads as something
        // planned for today, which is the confusion worth removing.
        if isPastDue(task), let day = task.dayValue {
            return "\(task.title) · due \(Self.overdueDay(day))"
        }
        if let time = task.displayTime { return "\(task.title) · due by \(time)" }
        return task.title
    }

    /// "yesterday" when it was, and the day by name when it was longer ago.
    private static func overdueDay(_ day: Date) -> String {
        Calendar.current.isDateInYesterday(day)
            ? "yesterday"
            : day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var weeklyProgress: Double {
        let stats = workouts.trainingStats
        guard stats.weeklyGoal > 0 else { return 0 }
        return min(max(Double(stats.completedThisWeek) / Double(stats.weeklyGoal), 0), 1)
    }

    private var flowRailProgress: Double {
        let mealCount = displayedMealCount ?? food.loggedMealCount(on: selectedDate)
        if mealCount > 0,
           let fuelIndex = chapters.firstIndex(of: .fuel),
           chapters.count > 1 {
            return Double(fuelIndex) / Double(chapters.count - 1)
        }
        if activeSession != nil,
           let trainingIndex = chapters.firstIndex(of: .training),
           chapters.count > 1 {
            return Double(trainingIndex) / Double(chapters.count - 1)
        }
        return 0
    }

    private var fuelAccent: Color {
        .repbaseDynamic(light: Color(hex: 0x5DAA86), dark: Color(hex: 0x84CFA9))
    }

    private var foodWarmAccent: Color {
        .repbaseDynamic(light: Color(hex: 0xC77756), dark: Color(hex: 0xEF946D))
    }

    private var trainingSurface: Color {
        RepbasePalette.ink
    }

    private var momentumSurface: Color {
        .repbaseDynamic(
            light: Color.white.opacity(0.72),
            dark: Color(hex: 0x1C1A17)
        )
    }

    private func synchronizeFoodProgress() {
        displayedFoodTotal = food.total(on: selectedDate)
        displayedMealCount = food.loggedMealCount(on: selectedDate)
    }

    private func presentLatestMealLogIfNeeded() {
        guard let event = food.consumeLatestMealLog(on: selectedDate) else {
            return
        }

        foodProgressTask?.cancel()
        displayedFoodTotal = event.before
        displayedMealCount = event.beforeMealCount
        foodProgressPulse = false

        foodProgressTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 30 : 150))
            guard !Task.isCancelled else { return }

            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.18)
                    : .spring(response: 0.72, dampingFraction: 0.86)
            ) {
                displayedFoodTotal = event.after
                displayedMealCount = event.afterMealCount
                foodProgressPulse = true
            }
            if event.shouldCelebrate {
                RepbaseCelebrations.show(.mealLogged)
            }

            try? await Task.sleep(for: .milliseconds(reduceMotion ? 180 : 760))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.24)) {
                foodProgressPulse = false
            }
        }
    }
}

private struct GuidedHomeFlowRail: View {
    @Environment(\.homeTimeOfDay) private var timeOfDay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let segmentHeight = max(58, proxy.size.height * 0.28)
            let availableTravel = max(proxy.size.height - segmentHeight, 0)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(HomeWidgetColors.border.opacity(0.72))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                timeOfDay.accent,
                                .repbaseDynamic(
                                    light: Color(hex: 0x5DAA86),
                                    dark: Color(hex: 0x84CFA9)
                                )
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: segmentHeight)
                    .offset(y: availableTravel * min(max(progress, 0), 1))
                    .shadow(
                        color: timeOfDay.accent.opacity(0.18),
                        radius: 5,
                        x: 0,
                        y: 0
                    )
            }
        }
        .frame(width: 3)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.18)
                : .spring(response: 0.72, dampingFraction: 0.86),
            value: progress
        )
        .accessibilityHidden(true)
    }
}

private struct GuidedMacroMetric: View {
    @Environment(\.homeTimeOfDay) private var timeOfDay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let label: String
    let value: Decimal
    let goal: Decimal
    let color: Color
    let animationDelay: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.community(.caption2, weight: .bold))
                .foregroundStyle(HomeWidgetColors.secondaryText)
            Text("\(value.nutritionText) / \(goal.nutritionText) g")
                .font(.community(.caption, weight: .semibold))
                .foregroundStyle(timeOfDay.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(HomeWidgetColors.progressTrack)
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * progress)
                        .animation(
                            reduceMotion
                                ? .easeOut(duration: 0.18)
                                : .spring(response: 0.72, dampingFraction: 0.86)
                                    .delay(animationDelay),
                            value: progress
                        )
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(max(value.nutritionDouble / goal.nutritionDouble, 0), 1)
    }
}

private struct GuidedFoodLivingSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let mealCount: Int
    let isPulsing: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [surfaceStart, surfaceEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [warmHalo.opacity(haloOpacity), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 68
                        )
                    )
                    .frame(width: 136, height: 136)
                    .offset(x: 54, y: -58)
                    .scaleEffect(isPulsing && !reduceMotion ? 1.14 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .animation(.easeInOut(duration: 0.68), value: stage)
            .animation(.easeOut(duration: 0.72), value: isPulsing)
    }

    private var stage: Int { min(max(mealCount, 0), 3) }

    private var surfaceStart: Color {
        if colorScheme == .dark {
            return [
                Color(hex: 0x171B18), Color(hex: 0x18201C),
                Color(hex: 0x19231F), Color(hex: 0x1A2722)
            ][stage]
        }
        return .white
    }

    private var surfaceEnd: Color {
        if colorScheme == .dark {
            return [
                Color(hex: 0x1C1D1A), Color(hex: 0x23211C),
                Color(hex: 0x29231D), Color(hex: 0x30261E)
            ][stage]
        }
        return .white
    }

    private var warmHalo: Color {
        colorScheme == .dark ? Color(hex: 0xEF946D) : Color(hex: 0xD58562)
    }

    private var haloOpacity: Double {
        [0.0, 0.08, 0.12, 0.16][stage]
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color(hex: 0x605B56) : RepbasePalette.ink.opacity(0.08)
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.16)
            : Color(hex: 0x594435).opacity(0.07)
    }
}

// MARK: - Store errors

private struct GuidedHomeErrors: View {
    @Environment(WorkoutStore.self) private var workouts
    @Environment(PlannerStore.self) private var planner
    @Environment(FoodTrackingStore.self) private var food
    @Environment(ActivityStore.self) private var activity

    var body: some View {
        VStack(spacing: 8) {
            if let error = workouts.persistenceError {
                errorLine(error) { workouts.retryPersistence() }
            }
            if let error = planner.persistenceError {
                errorLine(error) { planner.retry() }
            }
            if let error = food.errorMessage {
                errorLine(error, retry: nil)
            }
            if let error = activity.persistenceError {
                errorLine(error, retry: nil)
            }
        }
    }

    private func errorLine(_ message: String, retry: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
                .font(.community(.footnote))
                .lineLimit(2)
            Spacer(minLength: 4)
            if let retry {
                Button("Retry", action: retry)
                    .font(.community(.footnote, weight: .bold))
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
