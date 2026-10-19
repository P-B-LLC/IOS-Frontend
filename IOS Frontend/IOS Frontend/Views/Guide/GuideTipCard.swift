//
//  GuideTipCard.swift
//  IOS Frontend
//
//  A short note where the feature it explains is, until it is put away.
//

import SwiftUI

/// Once per account on this phone; Settings → Help brings them all back.
/// Quiet while the tour is running, which is already saying enough.
///
/// Drawn as the feed's own notices are -- the accent at a tint behind
/// caption text -- so it reads as part of the page rather than as something
/// laid on top of it.
struct GuideTipCard: View {
    // Optional: previews and the launch-flag harnesses have no store, and a
    // tip is the first thing that can go.
    @Environment(AppGuideStore.self) private var guide: AppGuideStore?
    let tip: AppGuideTip

    init(_ tip: AppGuideTip) {
        self.tip = tip
    }

    var body: some View {
        if let guide, !guide.isTouring, !guide.isDismissed(tip) {
            let timeOfDay = HomeTimeOfDay.current
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb")
                    .font(.community(.subheadline, weight: .semibold))
                    .foregroundStyle(timeOfDay.accent)
                    .accessibilityHidden(true)
                Text(tip.text)
                    .font(.community(.caption))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Got it") {
                    withAnimation(.easeOut(duration: 0.2)) { guide.dismiss(tip) }
                }
                .font(.community(.caption, weight: .bold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.vertical, -12)
                .accessibilityHint("Hides this tip")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(timeOfDay.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Tip")
            .transition(.opacity)
        }
    }
}
