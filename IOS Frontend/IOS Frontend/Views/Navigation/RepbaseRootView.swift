//
//  RepbaseRootView.swift
//  IOS Frontend
//
//  The signed-in shell: one tab per area, with the navigation bar always in
//  reach.
//

import SwiftUI

nonisolated enum RepbaseTab: String, CaseIterable, Identifiable {
    case home
    /// Workouts and food together. They were a slot each, which is two of five
    /// spent on the two halves of the same day, and left none for the feed.
    case training
    case planner
    case social
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .training: "Training"
        case .planner: "Calendar"
        case .social: "Social"
        case .account: "Account"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .training: "dumbbell.fill"
        case .planner: "calendar"
        case .social: "person.2.fill"
        case .account: "person"
        }
    }
}

/// Everything the signed-in app shows, with the bottom bar outside it.
///
/// A `TabView` rather than pushing each area from the home page: pushing meant
/// the bar was only ever on home, and getting from a workout to the planner
/// took a trip back through it. Each tab keeps its own navigation stack, so
/// coming back to one returns to where it was left.
struct RepbaseRootView: View {
    @State private var tab: RepbaseTab

    init(initialTab: RepbaseTab = .home) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $tab) {
            // Each tab hides the system bar for itself. Asking the TabView to
            // hide it does nothing, which left iOS 26's own floating bar
            // sitting under this one and reading as a duplicate.
            NavigationStack { ContentView() }
                .toolbar(.hidden, for: .tabBar)
                .tag(RepbaseTab.home)
            NavigationStack { TrainingTabView() }
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
        .safeAreaInset(edge: .bottom, spacing: 8) {
            // The clock wraps only the bar. Wrapping the whole TabView in a
            // TimelineView collapsed it to an empty screen, and would have
            // rebuilt every tab once a minute besides.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let timeOfDay = HomeTimeOfDay(date: context.date)
                RepbaseBottomNavigation(tab: $tab)
                    .environment(\.homeTimeOfDay, timeOfDay)
                    .tint(timeOfDay.accent)
                    .padding(.horizontal, RepbaseDesign.pageInset)
            }
        }
    }
}

/// The bar itself. Applied outside the tabs, so it stays put wherever the user
/// has navigated to inside one.
struct RepbaseBottomNavigation: View {
    @Environment(\.homeTimeOfDay) private var timeOfDay
    @Binding var tab: RepbaseTab

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
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .repbaseDepthSurface(cornerRadius: 18)
        .animation(.easeOut(duration: 0.18), value: tab)
    }

    private func itemLabel(_ item: RepbaseTab, isSelected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: item.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? activeColor : timeOfDay.secondaryText)
                .frame(width: 34, height: 26)
            Text(item.title)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isSelected ? activeColor : timeOfDay.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 50)
        .contentShape(Rectangle())
    }

    private var activeColor: Color {
        timeOfDay.usesDarkAppearance ? .white : RepbaseDesign.ink
    }
}
