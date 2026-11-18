import SwiftUI

/// Followers-only invitation flow. Review is a separate explicit step before
/// access can be granted; selecting a color or recipient never sends anything.
struct CalendarShareSheet: View {
    @Environment(CalendarSharingStore.self) private var sharing
    @Environment(\.dismiss) private var dismiss
    let entry: PlannerEntry
    @State private var search = ""
    @State private var people: [CalendarSharePerson] = []
    @State private var selected: [Int: CalendarSharePerson] = [:]
    @State private var nextPage: Int?
    @State private var scope: CalendarShareScope = .occurrence
    @State private var sent: [CalendarShareInvitation] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var review = false
    @State private var sentSuccessfully = false
    @State private var privacyScope: CalendarShareScope?
    @State private var confirmReinvite = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(entry.title).font(.community(.title2, weight: .bold))
                    Text(entry.date).font(.community(.subheadline)).foregroundStyle(.secondary)
                    if sentSuccessfully {
                        Label("Invitations sent", systemImage: "checkmark.circle.fill")
                        Text("Your followers choose whether to show this plan in their calendars.")
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    } else if review {
                        reviewContents
                    } else {
                        Label("Followers", systemImage: "person.2")
                            .font(.community(.headline))
                        Text("Only people who follow you can be invited. Choose up to 20 followers.")
                            .font(.community(.footnote)).foregroundStyle(.secondary)
                        ForEach(people) { person in
                            Button { toggle(person) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(person.name).font(.community(.headline))
                                        Text("@" + person.username).font(.community(.caption)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: selected[person.id] == nil ? "circle" : "checkmark.circle.fill")
                                }
                                .frame(minHeight: 58).padding(.horizontal, 12)
                                .background(RoundedRectangle(cornerRadius: 16)
                                    .fill(selected[person.id] == nil ? RytivoSunriseDesign.surface : RepbaseTactileDesign.cardTint))
                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(RytivoSunriseDesign.border))
                            }
                            .buttonStyle(.plain)
                            .disabled(isSaving || (selected.count >= 20 && selected[person.id] == nil))
                            .accessibilityAddTraits(selected[person.id] == nil ? [] : .isSelected)
                        }
                        if isLoading { ProgressView() }
                        if people.isEmpty && !isLoading {
                            Text("No eligible followers found.").foregroundStyle(.secondary)
                        }
                        if let nextPage {
                            Button("Load more") { Task { await loadPeople(page: nextPage) } }
                                .disabled(isLoading).frame(minHeight: 44)
                        }
                        if entry.isRepeating {
                            Picker("Share which dates?", selection: $scope) {
                                ForEach(CalendarShareScope.allCases) { Text($0.title).tag($0) }
                            }.pickerStyle(.inline)
                        }
                        privacyNotice
                        if !sent.filter(\.isActive).isEmpty { management }
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.community(.footnote)) }
                }.padding(24)
            }
            .navigationTitle(review ? "Review invitation" : "Share item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(isSaving)
                }
            }
            .searchable(text: $search, prompt: "Search name or username")
            .safeAreaInset(edge: .bottom) {
                if !sentSuccessfully {
                    Button(review ? "Send invitations" : "Review invitation") {
                        if review { Task { await send() } } else { review = true }
                    }
                    .buttonStyle(RepbasePrimaryButtonStyle())
                    .disabled(selected.isEmpty || isSaving)
                    .padding().background(Color(.systemBackground))
                }
            }
            .task(id: search) {
                do { try await Task.sleep(for: .milliseconds(300)); await loadPeople(page: nil) }
                catch {}
            }
            .task { await loadSent() }
            .confirmationDialog("Re-invite previously declined or removed followers?", isPresented: $confirmReinvite,
                                titleVisibility: .visible) {
                Button("Send invitations") { Task { await send(reinvite: true) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They will receive a new invitation and must accept again. Ordinary retries never restore their access.")
            }
            .confirmationDialog("Change who can see this plan?", isPresented: Binding(
                get: { privacyScope != nil }, set: { if !$0 { privacyScope = nil } }
            ), titleVisibility: .visible) {
                Button("Make private", role: .destructive) {
                    guard let chosen = privacyScope else { return }
                    Task { await makePrivate(chosen) }
                }
                Button("Cancel", role: .cancel) { privacyScope = nil }
            }
            .tint(RepbaseTactileDesign.accentText)
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var reviewContents: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(scope.title).font(.community(.headline))
            if scope == .series {
                Text("Earlier occurrences stay private.").font(.community(.footnote))
            }
            ForEach(selected.values.sorted { $0.id < $1.id }) { Text($0.name) }
            privacyNotice
            Button("Change recipients or dates") { review = false }.frame(minHeight: 44)
        }
    }

    private var privacyNotice: some View {
        Label("Only this plan’s title, time and completion status are shared. Your other plans, notes, subtasks and workout logs stay private.", systemImage: "lock")
            .font(.community(.footnote)).foregroundStyle(.secondary)
    }

    private var management: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sharing with").font(.community(.headline))
            ForEach(sent.filter(\.isActive)) { share in
                HStack {
                    VStack(alignment: .leading) {
                        Text(share.recipient.name)
                        if share.appliesToSelectedOccurrence == false {
                            Text("This occurrence is private.").font(.community(.caption)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Stop sharing", role: .destructive) {
                        Task {
                            do { try await sharing.revoke(share.id); await loadSent() }
                            catch { self.error = error.userFacingMessage }
                        }
                    }.frame(minHeight: 44)
                }
            }
            Button("Make this occurrence private", role: .destructive) { privacyScope = .occurrence }
                .frame(minHeight: 44)
            if entry.isRepeating {
                Button("Stop sharing this series", role: .destructive) { privacyScope = .series }
                    .frame(minHeight: 44)
            }
        }
    }

    private func toggle(_ person: CalendarSharePerson) {
        if selected[person.id] == nil { selected[person.id] = person }
        else { selected.removeValue(forKey: person.id) }
    }

    private func loadPeople(page: Int?) async {
        let query = search
        isLoading = true
        if page == nil { people = []; nextPage = nil }
        defer { if query == search { isLoading = false } }
        do {
            let result = try await sharing.followers(search: query, page: page)
            guard !Task.isCancelled, query == search else { return }
            if page == nil { people = result.people }
            else {
                let known = Set(people.map(\.id))
                people += result.people.filter { !known.contains($0.id) }
            }
            nextPage = result.nextPage
        } catch {
            guard !Task.isCancelled, query == search else { return }
            self.error = error.userFacingMessage
        }
    }

    private func loadSent() async {
        guard let id = entry.serverID else { return }
        do { sent = try await sharing.sent(for: id) }
        catch { guard !Task.isCancelled else { return }; self.error = error.userFacingMessage }
    }

    private func send(reinvite: Bool = false) async {
        guard let id = entry.serverID, !isSaving, !selected.isEmpty else { return }
        isSaving = true; error = nil
        defer { isSaving = false }
        do {
            try await sharing.invite(entryID: id, recipients: selected.keys.sorted(), scope: scope, reinvite: reinvite)
            guard !Task.isCancelled else { return }
            sentSuccessfully = true
        } catch CalendarShareRequestFailure.requiresExplicitReinvite {
            confirmReinvite = true
        } catch CalendarShareRequestFailure.scopeConflict {
            review = false
            self.error = String(localized: "This series is already shared from a later date. Stop sharing the series before choosing an earlier occurrence.", bundle: .app, locale: .app)
        } catch { self.error = error.userFacingMessage }
    }

    private func makePrivate(_ scope: CalendarShareScope) async {
        guard let id = entry.serverID, !isSaving else { return }
        isSaving = true
        defer { isSaving = false; privacyScope = nil }
        do { try await sharing.makePrivate(entryID: id, scope: scope); await loadSent() }
        catch { self.error = error.userFacingMessage }
    }
}
