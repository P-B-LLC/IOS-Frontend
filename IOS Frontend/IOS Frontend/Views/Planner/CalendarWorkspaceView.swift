import SwiftUI

/// Composes read-only grants at the presentation edge, never in own-entry state.
struct CalendarWorkspaceView: View {
    @Environment(PlannerStore.self) private var planner
    @Environment(CalendarSharingStore.self) private var sharing
    @Environment(\.scenePhase) private var phase
    @State private var showingInvitations = false
    @State private var selectedSharedPlan: SharedCalendarPlan?

    var body: some View {
        PlannerView(
            showsOwnPlans: sharing.showsOwn,
            sharedMonthItems: sharing.monthDays.flatMap(\.items).map(display),
            sharedMonthCounts: Dictionary(uniqueKeysWithValues: sharing.monthDays.map { ($0.date, $0.total) }),
            sharedDayItems: sharing.dayItems.map(display),
            sharedIsLoading: sharing.isConnected &&
                (sharing.isLoading || sharing.lastLoadedDay != PlannerStore.dateString(planner.selectedDate)),
            calendarControls: AnyView(visibilityControls),
            onSelectShared: { item in
                selectedSharedPlan = sharing.dayItems.first { $0.id == item.sharedID }
            }
        )
        .environment(\.calendarSharing, sharing)
        .task(id: readKey) { await sharing.refresh(month: planner.visibleMonth, day: planner.selectedDate) }
        .onChange(of: phase) { _, phase in
            if phase == .active { Task { await sharing.refresh(month: planner.visibleMonth, day: planner.selectedDate) } }
        }
        .refreshable { await sharing.refresh(month: planner.visibleMonth, day: planner.selectedDate) }
        .onChange(of: sharing.connectionRevision) { selectedSharedPlan = nil }
        .onChange(of: sharing.dayItems) { _, items in
            if let selectedSharedPlan { self.selectedSharedPlan = items.first { $0.id == selectedSharedPlan.id } }
        }
        .sheet(isPresented: $showingInvitations) { CalendarInvitationsView().environment(sharing) }
        .sheet(item: $selectedSharedPlan) { SharedCalendarPlanView(plan: $0) }
    }

    private var readKey: String {
        "\(sharing.connectionRevision)-\(planner.visibleMonth)-\(planner.selectedDate)-\(sharing.hiddenOwnerIDs.sorted())"
    }

    private var visibilityControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { sharing.showsOwn.toggle() } label: {
                        Label("You", systemImage: sharing.showsOwn ? "checkmark.circle.fill" : "circle")
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(RepbaseTactileDesign.cardTint, in: Capsule())
                    }.buttonStyle(.plain)
                    ForEach(sharing.people) { person in
                        Button { sharing.toggle(person.id) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: sharing.isVisible(person.id) ? "checkmark.circle.fill" : "circle")
                                Text(person.name)
                            }
                            .foregroundStyle(Self.ownerColor(person.id))
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(Self.ownerColor(person.id).opacity(0.12), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                    Button { showingInvitations = true } label: {
                        Label("Invitations", systemImage: "person.crop.circle.badge.plus")
                            .frame(minHeight: 44)
                        if !sharing.pendingInvitations.isEmpty { Text("\(sharing.pendingInvitations.count)") }
                    }.buttonStyle(.bordered)
                }.font(.community(.footnote, weight: .semibold))
            }
            if sharing.isLoading { ProgressView().controlSize(.mini) }
            if let error = sharing.errorMessage {
                Text(error).font(.community(.caption)).foregroundStyle(.secondary)
                Button("Retry") { Task { await sharing.refresh(month: planner.visibleMonth, day: planner.selectedDate) } }
                    .frame(minHeight: 44)
            }
        }
    }

    private func display(_ plan: SharedCalendarPlan) -> CalendarMonthItem {
        CalendarMonthItem(id: plan.id, sharedID: plan.id, title: plan.title, date: plan.date,
                          time: plan.time, isComplete: plan.isComplete, color: Self.ownerColor(plan.owner.id),
                          ownerLabel: plan.owner.name, durationMinutes: plan.durationMinutes,
                          schedulingTimezone: plan.schedulingTimezone)
    }

    static func ownerColor(_ ownerID: Int) -> Color {
        let palette: [PlannerItemColor] = [.lavender, .teal, .sky, .rose, .slate]
        return palette[Int(ownerID.magnitude % UInt(palette.count))].tint
    }
}

struct CalendarInvitationsView: View {
    @Environment(CalendarSharingStore.self) private var sharing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if sharing.pendingInvitations.isEmpty { Text("No calendar invitations.") }
                ForEach(sharing.pendingInvitations) { invitation in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(invitation.owner.name).font(.community(.headline))
                        if let plan = invitation.item {
                            Text(plan.title).font(.community(.title3, weight: .bold))
                            Text(plan.date).font(.community(.subheadline))
                            if let time = plan.time { Text(time).font(.community(.subheadline)) }
                            Text(plan.schedulingTimezone).font(.community(.caption))
                        }
                        Text(invitation.scope == "series" ? "This and future occurrences" : "Only this occurrence")
                        Text("Shared plans are view only and never count toward your tasks.")
                            .font(.community(.footnote)).foregroundStyle(.secondary)
                        Button("Show in my calendar") { Task { await sharing.respond(invitation, accept: true) } }
                            .buttonStyle(.borderedProminent).disabled(sharing.isSaving)
                        Button("Decline", role: .destructive) { Task { await sharing.respond(invitation, accept: false) } }
                            .buttonStyle(.bordered).disabled(sharing.isSaving)
                    }.padding(.vertical, 12)
                }
                if let error = sharing.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Calendar invitations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
            .task { await sharing.refreshCurrent() }
            .refreshable { await sharing.refreshCurrent() }
            .tint(RepbaseTactileDesign.accentText)
        }
    }
}

struct SharedCalendarPlanView: View {
    @Environment(\.dismiss) private var dismiss
    let plan: SharedCalendarPlan

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(plan.owner.name).foregroundStyle(CalendarWorkspaceView.ownerColor(plan.owner.id))
                    Text(plan.title).font(.community(.title, weight: .bold))
                    Text(plan.date)
                    if let time = plan.time { Text(time) }
                    Text(plan.schedulingTimezone).font(.community(.footnote)).foregroundStyle(.secondary)
                    Label("View only", systemImage: "lock")
                    if plan.isComplete { Label("Complete", systemImage: "checkmark.circle.fill") }
                    Text("Shared plans are view only and never count toward your tasks.")
                    Text("Notes, subtasks and workout logs are not shared.")
                }.padding(24)
            }
            .navigationTitle("Shared item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
    }
}
