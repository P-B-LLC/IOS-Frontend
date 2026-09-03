import SwiftUI

/// The small receipt shown after somebody takes an item from the social feed.
///
/// `accessibilityMessage` keeps the server's useful detail (including renamed
/// copies) without making the visual confirmation grow into a second card.
nonisolated struct RepbaseToastPresentation: Equatable {
    let title: String
    let accessibilityMessage: String
    let actionTitle: String
    let destination: RepbaseDestination
}

/// A compact status capsule that says something happened, then leaves.
///
/// Saving a meal or a workout used to answer with a notice inserted at the
/// top of the feed. Two problems with that. It pushed the whole feed down,
/// so confirming a tap moved the thing that had just been tapped; and it
/// stayed until it was tapped, so a confirmation of something already
/// finished sat on the screen looking like an alert about something wrong.
///
/// This sits over the page instead of in it, and takes itself away.
struct RepbaseToast: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var presentation: RepbaseToastPresentation?
    let onAction: (RepbaseDestination) -> Void

    /// Long enough to read a sentence, short enough not to be in the way.
    private static let staysFor = Duration.seconds(3.2)

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let presentation {
                    banner(presentation)
                        // Slides from the edge it belongs to, so where it
                        // came from and where it will go are the same place.
                        .transition(
                            .move(edge: .top)
                                .combined(with: .opacity)
                        )
                        // Keyed on the receipt: a second save while the first is
                        // still up restarts the clock rather than inheriting
                        // whatever was left of it.
                        .task(id: presentation) {
                            try? await Task.sleep(for: Self.staysFor)
                            guard !Task.isCancelled else { return }
                            withAnimation(.snappy(duration: 0.25)) {
                                self.presentation = nil
                            }
                        }
                }
            }
            .animation(.snappy(duration: 0.3), value: presentation)
    }

    private func banner(_ receipt: RepbaseToastPresentation) -> some View {
        let capsuleSurface = colorScheme == .dark ? Color.white : Color.black
        let capsuleText = colorScheme == .dark ? Color.black : Color.white

        return HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.community(size: 10, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 22, height: 22)
                .background(RepbasePalette.caramel, in: Circle())

            Text(receipt.title)
                .font(.community(.caption, weight: .semibold))
                .foregroundStyle(capsuleText)
                .lineLimit(1)

            Button(receipt.actionTitle) {
                withAnimation(.snappy(duration: 0.22)) {
                    presentation = nil
                }
                onAction(receipt.destination)
            }
            .font(.community(.caption, weight: .bold))
            .foregroundStyle(RepbasePalette.caramel)
            .buttonStyle(.plain)
        }
        .padding(.leading, 9)
        .padding(.trailing, 12)
        .frame(minHeight: 42)
        .background(capsuleSurface, in: Capsule())
        .overlay { Capsule().strokeBorder(capsuleText.opacity(0.12), lineWidth: 1) }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.18), radius: 10, y: 4)
        .padding(.horizontal, 48)
        .padding(.top, 6)
        // Dismissable early, both ways somebody would try.
        .onTapGesture {
            withAnimation(.snappy(duration: 0.25)) { presentation = nil }
        }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { drag in
                    guard drag.translation.height < 0 else { return }
                    withAnimation(.snappy(duration: 0.25)) { presentation = nil }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(receipt.accessibilityMessage)
    }
}

extension View {
    /// Shows a save receipt over this view until it clears itself.
    ///
    /// The binding is set back to nil when the toast leaves, so the caller
    /// holds one optional and nothing has to remember to tidy up.
    func repbaseToast(
        _ presentation: Binding<RepbaseToastPresentation?>,
        onAction: @escaping (RepbaseDestination) -> Void
    ) -> some View {
        modifier(RepbaseToast(presentation: presentation, onAction: onAction))
    }
}
