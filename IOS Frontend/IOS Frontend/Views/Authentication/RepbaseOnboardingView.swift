import SwiftUI

struct RepbaseOnboardingView: View {
    /// Two questions and a look at the answers.
    ///
    /// There were four. Two of them asked what the other two had already
    /// asked: "your goals" set the same field as "what brings you here", in
    /// different words, and the weekly target and the emphasis each appeared
    /// on two pages. Of what is left, the target drives the weekly goal and
    /// the emphasis decides what home opens on, so both pages do something.
    ///
    /// Experience went with them. It was collected to "tune language and
    /// suggested starting points", which was never built and is a content
    /// project rather than a feature.
    private enum Step: Int { case rhythm, ready }

    private enum TrainingType: String, CaseIterable, Identifiable {
        case strength = "Strength", running = "Running", cycling = "Cycling", swimming = "Swimming"
        var id: String { rawValue }
    }
    private enum Emphasis: String, CaseIterable, Identifiable {
        case training = "Training", movement = "Movement", nutrition = "Nutrition"
        var id: String { rawValue }
    }

    @Environment(SocialProfileStore.self) private var store

    @State private var step: Step = {
#if DEBUG
        // The summary is a screen and a tap in, and simctl has no tap.
        if ProcessInfo.processInfo.environment["REPBASE_PERSONALIZATION"] == "ready" {
            return .ready
        }
#endif
        return .rhythm
    }()
    @State private var trainingTypes: Set<TrainingType> = [.strength, .running]
    @State private var weeklyTarget = 3
    @State private var emphasis: Emphasis = .movement
    let completion: () -> Void

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current
        VStack(spacing: 0) {
            header(timeOfDay)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(title).font(.community(.title, weight: .bold)).tracking(-0.5)
                        Text(subtitle).font(.community(.subheadline)).foregroundStyle(.secondary)
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
        // Outside the TimelineView, which rebuilds every minute and would ask
        // the server again each time it did.
        .task { await loadPreferences() }
    }

    private func header(_ timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 20) {
            HStack {
                Button {
                    guard step.rawValue > 0 else { return }
                    withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .rhythm }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 40, height: 40)
                        .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
                .opacity(step == .rhythm ? 0 : 1)
                Spacer()
                Button("Skip", action: completion)
                    .font(.community(.caption, weight: .semibold))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }
            VStack(alignment: .leading, spacing: 13) {
                Text("STEP \(step.rawValue + 1) OF 2")
                    .font(.community(.caption2, weight: .bold)).tracking(1.1)
                    .foregroundStyle(RepbasePalette.caramel)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(timeOfDay.border)
                        Capsule().fill(RepbasePalette.sage)
                            .frame(width: proxy.size.width * CGFloat(step.rawValue + 1) / 2)
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
        case .rhythm:
            VStack(alignment: .leading, spacing: 28) {
                section("WORKOUT TYPES") { choiceGrid(timeOfDay) }
                section("WORKOUTS EACH WEEK") { targetRow(timeOfDay) }
                helper("Start realistic. You can change it any time.")
                section("WHAT SHOULD HOME LEAD WITH?") { emphasisPicker }
                helper("Home opens on whichever of these you choose.")
            }
        case .ready:
            // Read-only on purpose. This page carried live copies of the
            // controls from the page before it, which is how a summary stops
            // being a summary and becomes another chance to answer.
            VStack(alignment: .leading, spacing: 28) {
                section("YOUR RHYTHM") {
                    summaryCard(
                        "\(weeklyTarget) workouts each week",
                        detail: "This is the goal your dashboard counts against.",
                        timeOfDay
                    )
                }
                section("YOUR TRAINING") {
                    summaryCard(
                        trainingSummary,
                        detail: "Change it any time from Settings.",
                        timeOfDay
                    )
                }
                section("HOME OPENS ON") {
                    summaryCard(
                        emphasis.rawValue,
                        detail: "The first thing you see each day.",
                        timeOfDay
                    )
                }
                helper("Nothing is locked in. Your plan learns and changes with you.")
            }
        }
    }

    /// Loaded once, when the flow opens.
    private func loadPreferences() async {
        guard let values = try? await store.personalization() else { return }
        restorePreferences(values)
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
        // Nothing on either page can be left blank in a way worth
        // blocking on: a training type is optional, and the target and the
        // emphasis both start on a real value.
        .disabled(false)
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func choiceGrid(_ timeOfDay: HomeTimeOfDay) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(TrainingType.allCases) { item in
                compactChoice(item.rawValue, selected: trainingTypes.contains(item), timeOfDay) {
                    toggle(item, in: &trainingTypes)
                }
            }
        }
    }

    /// One fact and one line about it.
    ///
    /// The summary page used to carry live copies of the controls from the
    /// page before it, which is how a summary stops being a summary and
    /// becomes another chance to answer the same question.
    private func summaryCard(
        _ title: String,
        detail: String,
        _ timeOfDay: HomeTimeOfDay
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.community(.headline))
            Text(detail).font(.community(.caption)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(timeOfDay.border) }
    }

    private func compactChoice(_ title: String, selected: Bool, _ timeOfDay: HomeTimeOfDay,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: selected ? "checkmark" : "plus").font(.community(.caption2, weight: .bold))
                Text(title).font(.community(.caption, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.white : timeOfDay.canvasPrimaryText)
            .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 54)
            .background(selected ? RepbasePalette.sage : timeOfDay.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 17))
            .overlay { RoundedRectangle(cornerRadius: 17)
                .strokeBorder(selected ? Color.clear : timeOfDay.border) }
        }
        .buttonStyle(.plain)
    }

    private func targetRow(_ timeOfDay: HomeTimeOfDay) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Your weekly goal").font(.community(.headline))
                Text("What your dashboard counts against.").font(.community(.caption)).foregroundStyle(.secondary)
            }
            Spacer()
            targetButton("minus", enabled: weeklyTarget > 1,
                         background: timeOfDay.selectorSurface, foreground: timeOfDay.primaryText) {
                weeklyTarget = max(1, weeklyTarget - 1)
            }
            Text("\(weeklyTarget)").font(.community(.title3, weight: .bold)).frame(width: 26)
            targetButton("plus", enabled: weeklyTarget < 7,
                         background: RepbaseDesign.ink, foreground: RepbaseDesign.onInk) {
                weeklyTarget = min(7, weeklyTarget + 1)
            }
        }
        .padding(18)
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(timeOfDay.border) }
    }

    /// A stepper button, tappable across the whole square it looks like.
    ///
    /// It was neither of those things. The background sat on the Button,
    /// outside the label, so it could not take a tap, and an Image hit-tests
    /// the glyph it draws rather than the frame around it -- leaving roughly
    /// a 15pt target inside a 38pt button. The colours were fixed too, so at
    /// the maximum the dead "plus" stayed black and the working "minus"
    /// stayed pale: the control read as broken in exactly the state where it
    /// was working normally.
    private func targetButton(_ symbol: String, enabled: Bool, background: Color, foreground: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(foreground)
                .frame(width: 38, height: 38)
                .background(background, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }

    private var emphasisPicker: some View {
        Picker("", selection: $emphasis) {
            ForEach(Emphasis.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented).labelsHidden()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.community(.caption2, weight: .bold)).tracking(1).foregroundStyle(RepbasePalette.sage)
            content()
        }
    }

    private func helper(_ text: String) -> some View {
        Text(text).font(.community(.caption)).foregroundStyle(.secondary)
    }

    private var title: String {
        switch step {
        case .rhythm: "How do you like to move?"
        case .ready: "Your starting plan is ready."
        }
    }
    private var subtitle: String {
        switch step {
        case .rhythm: "Choose your usual training, how often, and what home should lead with."
        case .ready: "A simple rhythm built around what matters to you."
        }
    }
    private var trainingSummary: String {
        let values = TrainingType.allCases.filter(trainingTypes.contains).map { $0.rawValue.lowercased() }
        return values.isEmpty ? "Choose movement" : values.prefix(2).joined(separator: " + ").capitalized
    }
    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
    /// Send the answers to the account they belong to.
    ///
    /// These went to UserDefaults before, which meant they belonged to a
    /// phone: gone on reinstall, absent on a second device, and never seen by
    /// the server that was meant to act on them. Asking somebody five
    /// questions and then keeping the answers where nothing can read them is
    /// worse than not asking.
    ///
    /// Not awaited before the flow closes. The answers shape what Repbase
    /// emphasises later, not what happens next, so holding somebody on a
    /// finished screen while a request completes buys nothing -- and if it
    /// fails, the flow is reachable again from Settings.
    private func persistPreferences() {
        let values = Personalization(
            trainingTypes: trainingTypes.map(\.rawValue).sorted(),
            weeklyTarget: weeklyTarget,
            emphasis: emphasis.rawValue
        )
        Task { try? await store.savePersonalization(values) }
    }

    /// Start on whatever this account said last time.
    ///
    /// Anything the app no longer offers is dropped rather than resisted: the
    /// server stores the strings the flow used, and a choice retired since is
    /// a string with no case to map to. Falling back to the defaults for an
    /// account that has never answered is the same as never having asked.
    private func restorePreferences(_ values: Personalization) {
        let restoredTypes = Set(
            values.trainingTypes.compactMap(TrainingType.init(rawValue:))
        )
        if !restoredTypes.isEmpty { trainingTypes = restoredTypes }

        if (0...7).contains(values.weeklyTarget) { weeklyTarget = values.weeklyTarget }
        if let known = Emphasis(rawValue: values.emphasis) { emphasis = known }
    }
}
