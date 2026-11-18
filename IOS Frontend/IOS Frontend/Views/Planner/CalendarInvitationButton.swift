import SwiftUI

/// Kept outside the horizontally scrolling people filters so requests cannot
/// disappear behind an arbitrarily long list of shared calendars.
struct CalendarInvitationButton: View {
    @Environment(\.self) private var environment
    let presentation: CalendarInvitationPresentation
    let action: () -> Void

    private var hasIncoming: Bool { presentation.pendingCount != nil }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "envelope")
                    .font(.community(.title3, weight: .semibold))
                    .foregroundStyle(RepbaseTactileDesign.accentText)
                    .padding(10)
                    .background(RepbaseTactileDesign.accentText.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Calendar invitations")
                        .font(.community(.subheadline, weight: .bold))
                        .foregroundStyle(CalendarMonthStyle.ink)
                    statusText
                        .font(.community(.caption))
                        .foregroundStyle(CalendarMonthStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let count = presentation.pendingCount {
                    Text(count, format: .number.grouping(.never).locale(.app))
                        .font(.community(.subheadline, weight: .bold))
                        .monospacedDigit()
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundStyle(CalendarMonthStyle.foreground(
                            on: RepbaseTactileDesign.accentText, environment: environment))
                        .background(RepbaseTactileDesign.accentText, in: Capsule())
                        .fixedSize()
                        .accessibilityHidden(true)
                }
                Image(systemName: "chevron.forward")
                    .font(.community(.caption, weight: .bold))
                    .foregroundStyle(CalendarMonthStyle.ink)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(RepbaseTactileCardBackground(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(hasIncoming ? RepbaseTactileDesign.accentText : CalendarMonthStyle.border,
                                  lineWidth: hasIncoming ? 1.5 : 1)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(RepbaseTactilePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calendar invitations")
        .accessibilityValue(accessibilityStatus)
        .accessibilityHint("Review shared plans and respond to invitations")
        .accessibilityIdentifier("calendar.invitations")
    }

    private var statusText: Text {
        switch presentation {
        case .pending: Text("Shared plans are waiting for you")
        case .loading: Text("Checking invitations…")
        case .unavailable: Text("Open calendar invitations")
        case .empty: Text("No calendar invitations.")
        }
    }

    private var accessibilityStatus: Text {
        if let count = presentation.pendingCount { return Text("\(count) incoming invitations") }
        return statusText
    }
}
