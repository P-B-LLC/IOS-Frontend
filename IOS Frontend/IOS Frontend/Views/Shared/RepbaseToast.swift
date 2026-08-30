import SwiftUI

/// A line that says something happened, then leaves.
///
/// Saving a meal or a workout used to answer with a notice inserted at the
/// top of the feed. Two problems with that. It pushed the whole feed down,
/// so confirming a tap moved the thing that had just been tapped; and it
/// stayed until it was tapped, so a confirmation of something already
/// finished sat on the screen looking like an alert about something wrong.
///
/// This sits over the page instead of in it, and takes itself away.
struct RepbaseToast: ViewModifier {
    @Binding var message: String?

    /// Long enough to read a sentence, short enough not to be in the way.
    private static let staysFor = Duration.seconds(3.2)

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    banner(message)
                        // Slides from the edge it belongs to, so where it
                        // came from and where it will go are the same place.
                        .transition(
                            .move(edge: .top)
                                .combined(with: .opacity)
                        )
                        // Keyed on the text: a second save while the first is
                        // still up restarts the clock rather than inheriting
                        // whatever was left of it.
                        .task(id: message) {
                            try? await Task.sleep(for: Self.staysFor)
                            guard !Task.isCancelled else { return }
                            withAnimation(.snappy(duration: 0.25)) {
                                self.message = nil
                            }
                        }
                }
            }
            .animation(.snappy(duration: 0.3), value: message)
    }

    private func banner(_ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.community(size: 14, weight: .bold))
                .foregroundStyle(RepbaseDesign.success)

            Text(text)
                .font(.community(.caption, weight: .semibold))
                .foregroundStyle(RepbaseDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(RepbaseDesign.ink.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        // Dismissable early, both ways somebody would try.
        .onTapGesture {
            withAnimation(.snappy(duration: 0.25)) { message = nil }
        }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { drag in
                    guard drag.translation.height < 0 else { return }
                    withAnimation(.snappy(duration: 0.25)) { message = nil }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

extension View {
    /// Shows `message` over this view until it clears itself.
    ///
    /// The binding is set back to nil when the toast leaves, so the caller
    /// holds one optional and nothing has to remember to tidy up.
    func repbaseToast(_ message: Binding<String?>) -> some View {
        modifier(RepbaseToast(message: message))
    }
}
