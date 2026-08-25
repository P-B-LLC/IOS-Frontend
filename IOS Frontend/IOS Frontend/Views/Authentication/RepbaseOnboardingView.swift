import SwiftUI

struct RepbaseOnboardingView: View {
    private enum Step: Int { case intent, rhythm, goals, ready }
    private enum Intent: String, CaseIterable, Identifiable {
        case consistency = "Consistency", strength = "Strength", endurance = "Endurance"
        case nutrition = "Nutrition awareness", community = "Community"
        var id: String { rawValue }
        var detail: String {
            switch self {
            case .consistency: "Create a rhythm you can actually repeat."
            case .strength: "Track progressive workouts and personal bests."
            case .endurance: "Build running, cycling, or swimming capacity."
            case .nutrition: "Understand your food without overcomplicating it."
            case .community: "Share progress and follow people who inspire you."
            }
        }
    }
    private enum TrainingType: String, CaseIterable, Identifiable {
        case strength = "Strength", running = "Running", cycling = "Cycling", swimming = "Swimming"
        var id: String { rawValue }
    }
    private enum Experience: String, CaseIterable, Identifiable {
        case new = "New", some = "Some", experienced = "Experienced"
        var id: String { rawValue }
    }
    private enum Emphasis: String, CaseIterable, Identifiable {
        case training = "Training", movement = "Movement", nutrition = "Nutrition"
        var id: String { rawValue }
    }

    @State private var step: Step = .intent
    @State private var intents: Set<Intent> = [.consistency, .strength, .nutrition]
    @State private var trainingTypes: Set<TrainingType> = [.strength, .running]
    @State private var weeklyTarget = 3
    @State private var experience: Experience = .some
    @State private var emphasis: Emphasis = .movement
    let completion: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)
            VStack(spacing: 0) {
                header(timeOfDay)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(title).font(.title.weight(.bold)).tracking(-0.5)
                            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 30)
                        content(timeOfDay)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                nextButton
            }
            .homeTimeScreen(timeOfDay)
        }
    }

    private func header(_ timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 20) {
            HStack {
                Button {
                    guard step.rawValue > 0 else { return }
                    withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .intent }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 40, height: 40)
                        .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
                .opacity(step == .intent ? 0 : 1)
                Spacer()
                Button("Skip", action: completion)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }
            VStack(alignment: .leading, spacing: 13) {
                Text("STEP \(step.rawValue + 1) OF 4")
                    .font(.caption2.weight(.bold)).tracking(1.1)
                    .foregroundStyle(RepbasePalette.caramel)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(timeOfDay.border)
                        Capsule().fill(RepbasePalette.sage)
                            .frame(width: proxy.size.width * CGFloat(step.rawValue + 1) / 4)
                    }
                }
                .frame(height: 5)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 26)
    }

    @ViewBuilder private func content(_ timeOfDay: HomeTimeOfDay) -> some View {
        switch step {
        case .intent:
            VStack(spacing: 10) {
                ForEach(Intent.allCases) { item in
                    intentRow(item, timeOfDay)
                }
                Text("\(intents.count) selected").font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 4)
            }
        case .rhythm:
            VStack(alignment: .leading, spacing: 28) {
                section("WORKOUT TYPES") { choiceGrid(timeOfDay, usesGoals: false) }
                section("YOUR RHYTHM") { targetRow(timeOfDay) }
                section("EXPERIENCE") {
                    Picker("", selection: $experience) {
                        ForEach(Experience.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                }
                helper("We use this only to tune language and suggested starting points.")
            }
        case .goals:
            VStack(alignment: .leading, spacing: 28) {
                section("YOUR GOALS") { choiceGrid(timeOfDay, usesGoals: true) }
                section("WEEKLY TARGET") { targetRow(timeOfDay) }
                section("WHAT SHOULD WE EMPHASIZE?") { emphasisPicker }
                helper("This shapes your home screen and recommendations—not what you can access.")
            }
        case .ready:
            VStack(alignment: .leading, spacing: 28) {
                section("YOUR REPBASE") { summaryGrid(timeOfDay) }
                section("YOUR RHYTHM") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(weeklyTarget) workouts each week").font(.headline)
                        Text("Realistic, repeatable, and adjustable anytime.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(timeOfDay.border) }
                }
                section("HOME SCREEN EMPHASIS") { emphasisPicker }
                helper("Nothing is locked in. Your plan learns and changes with you.")
            }
        }
    }

    private var nextButton: some View {
        Button {
            if step == .ready {
                persistPreferences()
                completion()
            } else {
                withAnimation { step = Step(rawValue: step.rawValue + 1) ?? .ready }
            }
        } label: {
            HStack {
                Text(step == .ready ? "Start using Repbase" : "Continue")
                Image(systemName: "arrow.right")
            }.frame(maxWidth: .infinity)
        }
        .buttonStyle(RepbasePrimaryButtonStyle())
        .disabled(step == .intent && intents.isEmpty)
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func intentRow(_ item: Intent, _ timeOfDay: HomeTimeOfDay) -> some View {
        let selected = intents.contains(item)
        return Button { toggle(item, in: &intents) } label: {
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark" : "plus")
                    .font(.caption.weight(.bold)).frame(width: 26, height: 26)
                    .background(selected ? Color.white.opacity(0.13) : timeOfDay.selectorSurface,
                                in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.rawValue).font(.headline)
                    Text(item.detail).font(.caption2).opacity(0.76)
                }
                Spacer()
            }
            .foregroundStyle(selected ? Color.white : timeOfDay.canvasPrimaryText)
            .padding(.horizontal, 18).frame(minHeight: 60)
            .background(selected ? RepbasePalette.sage : timeOfDay.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 19))
            .overlay {
                if !selected { RoundedRectangle(cornerRadius: 19).strokeBorder(timeOfDay.border) }
            }
        }.buttonStyle(.plain)
    }

    private func choiceGrid(_ timeOfDay: HomeTimeOfDay, usesGoals: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            if usesGoals {
                ForEach(Array(Intent.allCases.prefix(4))) { item in
                    compactChoice(goalTitle(item), selected: intents.contains(item), timeOfDay) {
                        toggle(item, in: &intents)
                    }
                }
            } else {
                ForEach(TrainingType.allCases) { item in
                    compactChoice(item.rawValue, selected: trainingTypes.contains(item), timeOfDay) {
                        toggle(item, in: &trainingTypes)
                    }
                }
            }
        }
    }

    private func summaryGrid(_ timeOfDay: HomeTimeOfDay) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            compactSummary("Consistency first", intents.contains(.consistency), timeOfDay)
            compactSummary(trainingSummary, true, timeOfDay)
            compactSummary("Feel healthier", intents.contains(.nutrition), timeOfDay)
            compactSummary("Balanced progress", emphasis == .movement, timeOfDay)
        }
    }

    private func compactChoice(_ title: String, selected: Bool, _ timeOfDay: HomeTimeOfDay,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) { compactLabel(title, selected, timeOfDay) }.buttonStyle(.plain)
    }

    private func compactSummary(_ title: String, _ selected: Bool, _ timeOfDay: HomeTimeOfDay) -> some View {
        compactLabel(title, selected, timeOfDay)
    }

    private func compactLabel(_ title: String, _ selected: Bool, _ timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 9) {
            Image(systemName: selected ? "checkmark" : "plus").font(.caption2.weight(.bold))
            Text(title).font(.caption.weight(.semibold)).lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(selected ? Color.white : timeOfDay.canvasPrimaryText)
        .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 54)
        .background(selected ? RepbasePalette.sage : timeOfDay.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 17))
        .overlay { RoundedRectangle(cornerRadius: 17)
            .strokeBorder(selected ? Color.clear : timeOfDay.border) }
    }

    private func targetRow(_ timeOfDay: HomeTimeOfDay) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Workouts each week").font(.headline)
                Text("Start realistic. Change it anytime.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            targetButton("minus", background: timeOfDay.selectorSurface, foreground: timeOfDay.primaryText) {
                weeklyTarget = max(1, weeklyTarget - 1)
            }
            Text("\(weeklyTarget)").font(.title3.weight(.bold)).frame(width: 26)
            targetButton("plus", background: RepbaseDesign.ink, foreground: RepbaseDesign.onInk) {
                weeklyTarget = min(7, weeklyTarget + 1)
            }
        }
        .padding(18)
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(timeOfDay.border) }
    }

    private func targetButton(_ symbol: String, background: Color, foreground: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundStyle(foreground).frame(width: 38, height: 38)
        }.buttonStyle(.plain).background(background, in: RoundedRectangle(cornerRadius: 14))
    }

    private var emphasisPicker: some View {
        Picker("", selection: $emphasis) {
            ForEach(Emphasis.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented).labelsHidden()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(RepbasePalette.sage)
            content()
        }
    }

    private func helper(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private var title: String {
        switch step {
        case .intent: "What are you building?"
        case .rhythm: "How do you like to move?"
        case .goals: "What does progress look like?"
        case .ready: "Your starting plan is ready."
        }
    }
    private var subtitle: String {
        switch step {
        case .intent: "Choose everything that matters. You can change this later."
        case .rhythm: "Choose your usual training. You can always add another type."
        case .goals: "Pick the outcomes that matter now. You can change them anytime."
        case .ready: "A simple rhythm built around what matters to you."
        }
    }
    private var trainingSummary: String {
        let values = TrainingType.allCases.filter(trainingTypes.contains).map { $0.rawValue.lowercased() }
        return values.isEmpty ? "Choose movement" : values.prefix(2).joined(separator: " + ").capitalized
    }
    private func goalTitle(_ item: Intent) -> String {
        switch item {
        case .consistency: "Build consistency"
        case .strength: "Get stronger"
        case .endurance: "Build endurance"
        case .nutrition: "Feel healthier"
        case .community: "Build community"
        }
    }
    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
    private func persistPreferences() {
        let defaults = UserDefaults.standard
        defaults.set(intents.map(\.rawValue), forKey: "repbase.onboarding.intents")
        defaults.set(trainingTypes.map(\.rawValue), forKey: "repbase.onboarding.trainingTypes")
        defaults.set(weeklyTarget, forKey: "repbase.onboarding.weeklyTarget")
        defaults.set(experience.rawValue, forKey: "repbase.onboarding.experience")
        defaults.set(emphasis.rawValue, forKey: "repbase.onboarding.emphasis")
    }
}
