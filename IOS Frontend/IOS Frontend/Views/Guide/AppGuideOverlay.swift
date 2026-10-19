//
//  AppGuideOverlay.swift
//  IOS Frontend
//
//  The welcome guide on screen: the app dimmed, the tab being described lit
//  in the bottom bar, and a card above it saying what that tab is for.
//
//  It points at the real bar rather than at a picture of one. Each bar
//  button reports where it is through GuideTabAnchorKey, and the step's tab
//  is selected behind the dimming, so what is lit is what is described.
//

import SwiftUI

/// Where each bottom-bar button is, for the guide to light up.
nonisolated struct GuideTabAnchorKey: PreferenceKey {
    static let defaultValue: [RepbaseTab: Anchor<CGRect>] = [:]

    static func reduce(value: inout [RepbaseTab: Anchor<CGRect>], nextValue: () -> [RepbaseTab: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks this as the bar button the guide lights for `tab`.
    func guideAnchor(_ tab: RepbaseTab) -> some View {
        anchorPreference(key: GuideTabAnchorKey.self, value: .bounds) { [tab: $0] }
    }
}

struct AppGuideOverlay: View {
    // Optional, as BottomBarChrome is: previews and the launch-flag
    // harnesses build the shell without the store, and a missing one should
    // cost the tour rather than the screen.
    @Environment(AppGuideStore.self) private var guide: AppGuideStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleFocused: Bool

    let anchors: [RepbaseTab: Anchor<CGRect>]
    @Binding var tab: RepbaseTab
    /// The tab somebody was on when they asked for the tour from Settings,
    /// and goes back to after. Nil for the tour that opened by itself.
    @State private var startedOn: RepbaseTab?

    var body: some View {
        ZStack {
            if let guide, let progress = guide.progress {
                GeometryReader { proxy in
                    tour(progress, guide: guide, proxy: proxy)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: guide?.isTouring)
        // Initial too: the tour that opens by itself for a new account is
        // already waiting when the shell first appears, after the sign-up
        // questions.
        .onChange(of: guide?.progress?.step.id, initial: true) { previous, current in
            guard current != nil, let step = guide?.progress?.step else { return }
            if previous == nil { startedOn = tab }
            tab = step.tab
            // VoiceOver reads each step as it arrives rather than staying
            // on the button that was pressed with nothing new to say.
            titleFocused = true
        }
    }

    private func tour(_ progress: AppGuideProgress, guide: AppGuideStore, proxy: GeometryProxy) -> some View {
        let lit: CGRect? = progress.step.highlightsTab
            ? anchors[progress.step.tab].map { proxy[$0].insetBy(dx: -6, dy: -6) }
            : nil
        // With nothing lit the hole closes to a point in the middle, so the
        // next lit step opens it from there rather than from a corner.
        let hole = lit ?? CGRect(x: proxy.size.width / 2, y: proxy.size.height / 2, width: 0, height: 0)
        let motion: Animation? = reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86)

        return ZStack {
            GuideScrim(hole: hole, cornerRadius: 18)
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                // The app behind waits. A stray tap on it should not leave
                // the tour half on screen over a different page.
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)

            if let lit {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(RepbasePalette.caramel, lineWidth: 2.5)
                    .frame(width: lit.width, height: lit.height)
                    .position(x: lit.midX, y: lit.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 0) {
                Spacer(minLength: proxy.safeAreaInsets.top + 12)
                card(progress, guide: guide)
                if let lit {
                    // Above the lit button, which is always in the bar at the
                    // bottom; never over it.
                    Color.clear.frame(height: max(proxy.size.height - lit.minY + 14, 0))
                } else {
                    Spacer(minLength: proxy.safeAreaInsets.bottom + 12)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .animation(motion, value: progress.index)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close(guide) }
    }

    private func card(_ progress: AppGuideProgress, guide: AppGuideStore) -> some View {
        let timeOfDay = HomeTimeOfDay.current
        let text = VStack(alignment: .leading, spacing: 7) {
            Text(progress.step.title)
                .font(.community(.title3, weight: .bold))
                .foregroundStyle(timeOfDay.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Text(progress.step.body)
                .font(.community(.subheadline))
                .foregroundStyle(timeOfDay.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text(progress.position.uppercased())
                    .font(.community(.caption2, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(RepbasePalette.caramel)
                Spacer()
                Button {
                    close(guide)
                } label: {
                    Image(systemName: "xmark")
                        .font(.community(.caption, weight: .bold))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .frame(width: 32, height: 32)
                        .background(timeOfDay.selectorSurface, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The full 44 points stay tappable without pushing the
                // progress bar down by the difference.
                .padding(.vertical, -6)
                .padding(.trailing, -6)
                .accessibilityLabel("Close the tour")
                .keyboardShortcut(.cancelAction)
            }

            // As the sign-up questions draw theirs: sage on the border colour.
            GeometryReader { bar in
                ZStack(alignment: .leading) {
                    Capsule().fill(timeOfDay.border)
                    Capsule().fill(RepbasePalette.sage)
                        .frame(width: bar.size.width * progress.fraction)
                }
            }
            .frame(height: 5)
            .accessibilityHidden(true)

            // Scrolls only when it has to: at the largest text sizes a step
            // can be taller than the room above the bar, and the buttons
            // under it must stay in reach.
            ViewThatFits(in: .vertical) {
                text
                ScrollView { text }
                    .scrollBounceBehavior(.basedOnSize)
            }

            HStack(spacing: 10) {
                if !progress.isLast {
                    Button(progress.isFirst ? "Not now" : "Skip tour") { close(guide) }
                        .font(.community(.footnote, weight: .semibold))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .frame(minHeight: 44)
                }
                Spacer(minLength: 0)
                if !progress.isFirst {
                    Button("Back") { guide.back() }
                        .buttonStyle(RepbaseQuietButtonStyle())
                }
                Button {
                    if progress.isLast { close(guide) } else { guide.next() }
                } label: {
                    Text(progress.isFirst ? "Show me round" : progress.isLast ? "Finish" : "Next")
                }
                .buttonStyle(RepbasePrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(timeOfDay.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12)
        .frame(maxWidth: 440)
        .padding(.horizontal, 16)
        .environment(\.homeTimeOfDay, timeOfDay)
    }

    private func close(_ guide: AppGuideStore) {
        if let startedOn { tab = startedOn }
        startedOn = nil
        guide.finish()
    }
}

/// Everything but a rounded hole, filled even-odd. Animatable, so the hole
/// slides from one tab to the next rather than jumping.
private struct GuideScrim: Shape {
    var hole: CGRect
    let cornerRadius: CGFloat

    var animatableData: CGRect.AnimatableData {
        get { hole.animatableData }
        set { hole.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let radius = min(cornerRadius, hole.width / 2, hole.height / 2)
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        return path
    }
}
