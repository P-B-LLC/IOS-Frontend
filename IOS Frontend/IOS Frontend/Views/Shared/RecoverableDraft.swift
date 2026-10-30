import Foundation
import SwiftUI

extension View {
    func recoverableDraft<Value: Codable & Equatable>(
        key: String, value: Binding<Value>, saved: Binding<Bool>, error: Binding<String?>,
        confirmRestoration: Bool = false
    ) -> some View {
        modifier(RecoverableDraftModifier(key: key, value: value, saved: saved, error: error,
                                         confirmRestoration: confirmRestoration))
    }
}

private struct RecoverableDraftModifier<Value: Codable & Equatable>: ViewModifier {
    let key: String
    @Binding var value: Value
    @Binding var saved: Bool
    @Binding var error: String?
    let confirmRestoration: Bool
    @State private var scope: EditorDraftRecovery.Scope?
    @State private var loaded = false
    @State private var pendingRestoration: Value?
    @State private var showingRestoreChoice = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !loaded else { return }
                scope = EditorDraftRecovery.shared.scope
                guard let scope else { return }
                do {
                    if let restored = try EditorDraftRecovery.shared.load(Value.self, key: key, scope: scope) {
                        if confirmRestoration, restored != value {
                            pendingRestoration = restored
                            showingRestoreChoice = true
                            return
                        }
                        value = restored
                    }
                    loaded = true
                } catch {
                    // Do not overwrite an unreadable draft with empty fields.
                    self.error = String(localized: "Couldn't restore the local draft. \(error.localizedDescription)", bundle: .app, locale: .app)
                }
            }
            .disabled(showingRestoreChoice)
            .alert("Continue your unfinished draft?", isPresented: $showingRestoreChoice) {
                Button("Continue draft") {
                    guard let pendingRestoration, scope == EditorDraftRecovery.shared.scope else { return }
                    value = pendingRestoration
                    self.pendingRestoration = nil
                    loaded = true
                }
                Button("Discard draft", role: .destructive) {
                    guard let scope, scope == EditorDraftRecovery.shared.scope else { return }
                    do {
                        try EditorDraftRecovery.shared.remove(key: key, scope: scope)
                        pendingRestoration = nil
                        loaded = true
                    } catch {
                        self.error = String(localized: "Couldn't clear the local draft. Your previous changes are kept.", bundle: .app, locale: .app)
                        showingRestoreChoice = true
                    }
                }
            } message: {
                Text("There are unsaved changes from your last visit. Continue that draft, or discard it and use the current screen. Saved workouts are not deleted.")
            }
            .onChange(of: value) { _, newValue in
                guard loaded, !saved, let scope,
                      scope == EditorDraftRecovery.shared.scope else { return }
                do { try EditorDraftRecovery.shared.save(newValue, key: key, scope: scope) }
                catch { self.error = String(localized: "Couldn't keep a local draft. \(error.localizedDescription)", bundle: .app, locale: .app) }
            }
            .onChange(of: saved) { _, confirmed in
                guard confirmed, let scope else { return }
                do { try EditorDraftRecovery.shared.remove(key: key, scope: scope) }
                catch { self.error = String(localized: "Saved, but the local draft could not be cleared.", bundle: .app, locale: .app) }
            }
            .onDisappear {
                if saved, let scope { try? EditorDraftRecovery.shared.remove(key: key, scope: scope) }
            }
    }
}
