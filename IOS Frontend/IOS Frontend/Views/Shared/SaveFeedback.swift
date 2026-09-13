import SwiftUI

extension View {
    /// One save state for inputs, dismissal, progress, and an inline retry error.
    func saveFeedback(isSaving: Bool, error: String?) -> some View {
        self
            .disabled(isSaving)
            .interactiveDismissDisabled(isSaving)
            .navigationBarBackButtonHidden(isSaving)
            .safeAreaInset(edge: .bottom) {
                if isSaving || error != nil {
                    VStack(spacing: 6) {
                        if isSaving { ProgressView("Saving…") }
                        else if let error {
                            Text(error)
                                .font(.community(.footnote))
                                .foregroundStyle(.primary)
                                .accessibilityLabel("Save failed. \(error)")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(.regularMaterial)
                }
            }
    }
}
