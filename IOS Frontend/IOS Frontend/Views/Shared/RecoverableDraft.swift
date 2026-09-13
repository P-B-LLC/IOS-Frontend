import SwiftUI

extension View {
    func recoverableDraft<Value: Codable & Equatable>(
        key: String, value: Binding<Value>, saved: Binding<Bool>, error: Binding<String?>
    ) -> some View {
        modifier(RecoverableDraftModifier(key: key, value: value, saved: saved, error: error))
    }
}

private struct RecoverableDraftModifier<Value: Codable & Equatable>: ViewModifier {
    let key: String
    @Binding var value: Value
    @Binding var saved: Bool
    @Binding var error: String?
    @State private var scope: EditorDraftRecovery.Scope?
    @State private var loaded = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !loaded else { return }
                scope = EditorDraftRecovery.shared.scope
                guard let scope else { return }
                do {
                    if let restored = try EditorDraftRecovery.shared.load(Value.self, key: key, scope: scope) {
                        value = restored
                    }
                    loaded = true
                } catch {
                    // Do not overwrite an unreadable draft with empty fields.
                    self.error = "Couldn't restore the local draft. \(error.localizedDescription)"
                }
            }
            .onChange(of: value) { _, newValue in
                guard loaded, !saved, let scope,
                      scope == EditorDraftRecovery.shared.scope else { return }
                do { try EditorDraftRecovery.shared.save(newValue, key: key, scope: scope) }
                catch { self.error = "Couldn't keep a local draft. \(error.localizedDescription)" }
            }
            .onChange(of: saved) { _, confirmed in
                guard confirmed, let scope else { return }
                do { try EditorDraftRecovery.shared.remove(key: key, scope: scope) }
                catch { self.error = "Saved, but the local draft could not be cleared." }
            }
            .onDisappear {
                if saved, let scope { try? EditorDraftRecovery.shared.remove(key: key, scope: scope) }
            }
    }
}
