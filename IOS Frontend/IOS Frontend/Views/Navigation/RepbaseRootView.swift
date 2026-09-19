//
//  RepbaseRootView.swift
//  IOS Frontend
//
//  The signed-in shell: one tab per area, with the navigation bar always in
//  reach.
//

import SwiftUI

/// Raised by a screen that needs the bottom of the window to itself.
///
/// The bar is a `safeAreaInset`, so when the keyboard comes up the bar rises
/// with it and sits directly on whatever is being typed into. A text box
/// pinned to the bottom has to be able to say "not while I am being written
/// in"; a system tab bar would take `.toolbar(.hidden, for: .tabBar)`, and
/// this one is ours, so it takes this.
nonisolated struct HidesBottomBarPreference: PreferenceKey {
    static let defaultValue = false

    /// Any one screen asking is enough. Several may be on the stack at once,
    /// and the innermost is not reliably the last to report.
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func hidesBottomBar(_ hidden: Bool) -> some View {
        preference(key: HidesBottomBarPreference.self, value: hidden)
    }
}

/// How much room the bottom bar is taking, shared by the shell and whichever
/// screen is being scrolled.
///
/// An object rather than a preference. A preference reduces across every view
/// that raises one, and TabView keeps all five tabs alive at once: scroll Home
/// down, switch to Social, and Home would still be reporting "minimized" from
/// off screen -- pinning the reduced value so Social's own scrolling could
/// never change it again. A tab that is not being scrolled writes nothing
/// here, which is the same guarantee without the bookkeeping.
@Observable
final class BottomBarChrome {
    /// Smaller, not gone. Set by the screen being read, cleared by the shell
    /// when the tab changes.
    var isMinimized = false
}

extension View {
    /// Shrinks the bottom bar while this scroll view is moving down the page,
    /// and restores it on the way back up.
    func minimizesBottomBarOnScroll() -> some View {
        modifier(MinimizesBottomBarOnScroll())
    }
}

private struct MinimizesBottomBarOnScroll: ViewModifier {
    // Optional on purpose: previews and the launch-flag harnesses build these
    // screens without the shell around them, and a missing object should cost
    // the animation rather than the screen.
    @Environment(BottomBarChrome.self) private var chrome: BottomBarChrome?
    @State private var pivot: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                react(to: offset)
            }
    }

    private func react(to offset: CGFloat) {

        guard let chrome else { return }

        // The top of the page always gets the full bar, whatever the last
        // direction was. Arriving somewhere should not find the furniture
        // already folded away.
        guard offset > 40 else {
            pivot = offset
            chrome.isMinimized = false
            return
        }

        let travel = offset - pivot
        // Distance rather than direction alone: a finger resting on the glass
        // reports a pixel each way forever, and a bar answering that would
        // flicker rather than respond. Not resetting the pivot below the
        // threshold is what makes it cumulative travel rather than one frame's
        // worth, so a slow drag still counts.
        guard abs(travel) > 44 else { return }
        pivot = offset
        chrome.isMinimized = travel > 0
    }
}

/// Everything the signed-in app shows, with the bottom bar outside it.
///
/// A `TabView` rather than pushing each area from the home page: pushing meant
/// the bar was only ever on home, and getting from a workout to the planner
/// took a trip back through it. Each tab keeps its own navigation stack, so
/// coming back to one returns to where it was left.
struct RepbaseRootView: View {
    @Environment(WorkoutStore.self) private var workoutStore
    @AppStorage("widgets.pendingDestination") private var widgetDestination = ""
    @State private var tab: RepbaseTab
    /// Which half of the Training tab is showing, and how deep into it we
    /// are. Both live here because Home sends people there: opening Food or
    /// a particular day has to select the tab as well as the page, or the
    /// bottom bar goes on describing the tab somebody started from.
    @State private var trainingHalf: TrainingTabView.Half = .workouts
    @State private var trainingPath = NavigationPath()
    /// Set while a screen is writing into something pinned to the bottom.
    @State private var isBarHidden = false
    @State private var chrome = BottomBarChrome()
#if DEBUG
    // The minimized bar only appears mid-scroll, and simctl has no gesture
    // to make one with. This is how it gets looked at.
    private let forcesMinimizedBar =
        ProcessInfo.processInfo.environment["REPBASE_BAR_MINIMIZED"] != nil
#endif

    init(initialTab: RepbaseTab = .home) {
#if DEBUG
        // Lands on a named tab, so a screen several taps in can be looked at
        // in the real app rather than only in a preview harness.
        if let raw = ProcessInfo.processInfo.environment["REPBASE_TAB"],
           let named = RepbaseTab(rawValue: raw) {
            _tab = State(initialValue: named)
            return
        }
#endif
        _tab = State(initialValue: initialTab)
    }

    private var showsMinimizedBar: Bool {
#if DEBUG
        if forcesMinimizedBar { return true }
#endif
        return chrome.isMinimized
    }

    var body: some View {
        TabView(selection: $tab) {
            // Each tab hides the system bar for itself. Asking the TabView to
            // hide it does nothing, which left iOS 26's own floating bar
            // sitting under this one and reading as a duplicate.
            NavigationStack { ContentView() }
                .toolbar(.hidden, for: .tabBar)
                .tag(RepbaseTab.home)
            NavigationStack(path: $trainingPath) {
                TrainingTabView(half: $trainingHalf)
                    // A day opened from Home is pushed onto this tab rather
                    // than Home's, so the bar reads Training and the chevron
                    // goes back to the week rather than out to the summary.
                    .navigationDestination(for: Weekday.self) { day in
                        DayWorkoutView(day: day)
                    }
            }
            .toolbar(.hidden, for: .tabBar)
            .tag(RepbaseTab.training)
            NavigationStack { PlannerView() }
                .toolbar(.hidden, for: .tabBar)
                .tag(RepbaseTab.planner)
            NavigationStack { SocialFeedView() }
                .toolbar(.hidden, for: .tabBar)
                .tag(RepbaseTab.social)
            NavigationStack { ProfileDestinationView() }
                .toolbar(.hidden, for: .tabBar)
                .tag(RepbaseTab.account)
        }
        .environment(chrome)
        .onChange(of: widgetDestination, initial: true) { _, destination in
            guard !destination.isEmpty else { return }
            switch destination {
            case "activeWorkout":
                trainingPath = NavigationPath()
                trainingHalf = .workouts
                tab = .training
                if let session = workoutStore.activeSession { trainingPath.append(session.day) }
            case "food", "workout":
                trainingPath = NavigationPath()
                trainingHalf = destination == "food" ? .food : .workouts
                tab = .training
            case "planner": tab = .planner
            case "day": tab = .home
            default: break
            }
            widgetDestination = ""
        }
        // Which tab a destination selects, which half it shows and whether it
        // clears the stack first is worked out by RepbaseRoute, and tested
        // there. This applies the answer and owns the state; it decides
        // nothing. Clearing before appending is the rule worth keeping in
        // sight: arriving from Home is a fresh trip, not a step deeper into
        // wherever the tab was left three days ago.
        .environment(\.repbaseNavigate, RepbaseNavigateAction { destination in
            let route = RepbaseRoute(for: destination)
            if let half = route.trainingHalf { trainingHalf = half }
            if route.clearsTrainingPath { trainingPath = NavigationPath() }
            if let day = route.pushesDay { trainingPath.append(day) }
            tab = route.tab
        })
        .onPreferenceChange(HidesBottomBarPreference.self) { isBarHidden = $0 }
        // A new tab is a new page, and a new page starts at the top.
        .onChange(of: tab) { chrome.isMinimized = false }
        .safeAreaInset(edge: .bottom, spacing: isBarHidden ? 0 : 8) {
            // The clock wraps only the bar. Wrapping the whole TabView in a
            // TimelineView collapsed it to an empty screen, and would have
            // rebuilt every tab once a minute besides.
            if !isBarHidden {
                let timeOfDay = HomeTimeOfDay.current
                RepbaseBottomNavigation(tab: $tab, isMinimized: showsMinimizedBar)
                    .environment(\.homeTimeOfDay, timeOfDay)
                    .tint(timeOfDay.accent)
                    // Narrower as well as shorter. Height alone was the
                    // honest change and almost invisible in motion -- and
                    // buying more of it means taking it off the tap
                    // targets, which are already only four points over the
                    // minimum. Pulling the ends in reads as standing back
                    // without costing anything a finger needs.
                    .padding(.horizontal, showsMinimizedBar ? 58 : RepbaseDesign.pageInset)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isBarHidden)
        .animation(.easeOut(duration: 0.22), value: showsMinimizedBar)
    }
}

/// The bar itself. Applied outside the tabs, so it stays put wherever the user
/// has navigated to inside one.
struct RepbaseBottomNavigation: View {
    @Environment(\.homeTimeOfDay) private var timeOfDay
    @Binding var tab: RepbaseTab
    /// Smaller, not gone. Every tab stays where it was and stays pressable;
    /// what changes is how much of the page the bar is standing on.
    var isMinimized = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RepbaseTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    itemLabel(item, isSelected: item == tab)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(item == tab ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isMinimized ? 4 : 5)
        .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(timeOfDay.border, lineWidth: 1)
        }
        .shadow(color: timeOfDay.shadow, radius: 9, x: 0, y: 5)
        .animation(.easeOut(duration: 0.18), value: tab)
    }

    /// Icons only. The names are still on the button as an accessibility
    /// label, so VoiceOver reads "Calendar" even though nothing on screen
    /// says it — dropping the text from the design should not drop it from
    /// the app.
    private func itemLabel(_ item: RepbaseTab, isSelected: Bool) -> some View {
        VStack(spacing: isMinimized ? 3 : 4) {
            Group {
                if item == .training {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: isMinimized ? 18 : 20, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                } else {
                    Image(item.iconAsset)
                        .resizable()
                        .scaledToFit()
                }
            }
                .foregroundStyle(isSelected ? timeOfDay.accent : timeOfDay.secondaryText)
                .frame(width: isMinimized ? 21 : 24, height: isMinimized ? 21 : 24)

            // Kept, and now doing more work: with the labels gone this and the
            // colour are the only things saying which tab you are on.
            Capsule()
                .fill(timeOfDay.accent)
                .frame(width: 14, height: 2)
                .opacity(isSelected ? 1 : 0)
        }
        .foregroundStyle(isSelected ? timeOfDay.accent : timeOfDay.secondaryText)
        // 38 plus the bar's own padding puts the tap target back above Apple's
        // 44pt minimum, which the 34 that briefly replaced it was under.
        // Between the original height and the too-slim one.
        //
        // Minimized trades a little of that back: 32 and 4 is 40, under the
        // guideline by four points. Each item is still about seventy wide, the
        // state only lasts while a finger is actively dragging the page away
        // from the bar, and any scroll the other way returns it. A bar that
        // stood down by becoming untappable would be the worse trade.
        .frame(maxWidth: .infinity, minHeight: isMinimized ? 32 : 38)
        .contentShape(Rectangle())
    }

}
