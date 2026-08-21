//
//  GearStore.swift
//  IOS Frontend
//
//  Main-actor gear state, read from the server.
//
//  Mileage is never accumulated here. Every total comes from the server, which
//  sums it across every session the gear was used for; the device that ran one
//  of those sessions has no way to know about the other ninety.
//

import Foundation
import Observation

@Observable
@MainActor
final class GearStore {
    private var repository: GearAPIRepository?
    private var connectionGeneration = UUID()

    private(set) var gear: [Gear] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var persistenceError: String?

    init() {}

    var isConnected: Bool { repository != nil }

    /// Gear still in use, of one kind, default first then alphabetical.
    func active(_ kind: GearKind) -> [Gear] {
        gear
            .filter { $0.kind == kind && !$0.isRetired }
            .sorted {
                if $0.isDefault != $1.isDefault { return $0.isDefault }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                    == .orderedAscending
            }
    }

    /// Everything of one kind, retired last, for the gear list.
    func all(_ kind: GearKind) -> [Gear] {
        gear
            .filter { $0.kind == kind }
            .sorted {
                if $0.isRetired != $1.isRetired { return !$0.isRetired }
                if $0.isDefault != $1.isDefault { return $0.isDefault }
                return $0.totalDistanceKilometers > $1.totalDistanceKilometers
            }
    }

    /// What a new session of this type should start with, if anything.
    ///
    /// Whatever was worn last, first. That is the answer almost every time,
    /// and it is a fact about what the user did rather than a flag they set
    /// once and forgot — so it stays right when they switch to a new pair
    /// without remembering to mark it.
    ///
    /// Then the explicit default, then the only one there is. With several
    /// never-used pairs and no default, nothing is filled in: picking a
    /// favourite among them would be a guess, and a wrong guess quietly puts
    /// miles on the wrong shoe.
    func defaultGear(for workoutType: WorkoutType) -> Gear? {
        guard let kind = GearKind.forWorkoutType(workoutType) else { return nil }
        let candidates = active(kind)

        let mostRecent = candidates
            .compactMap { gear in gear.lastUsedAt.map { (gear, $0) } }
            .max { $0.1 < $1.1 }?
            .0
        if let mostRecent { return mostRecent }

        return candidates.first { $0.isDefault }
            ?? (candidates.count == 1 ? candidates.first : nil)
    }

    func gear(withID id: Int) -> Gear? {
        gear.first { $0.id == id }
    }

    // MARK: - Connection

    func connect(configuration: APIConfiguration, token: String) async {
        let generation = UUID()
        connectionGeneration = generation

        do {
            repository = try GearAPIRepository(
                configuration: configuration,
                token: token
            )
        } catch {
            repository = nil
            gear = []
            persistenceError = error.userFacingMessage
            return
        }

        await reload(generation: generation, showsLoadingState: true)
    }

    func disconnect() {
        connectionGeneration = UUID()
        repository = nil
        // One user's shoes must never be shown to the next.
        gear = []
        persistenceError = nil
        isLoading = false
        isSaving = false
    }

    // MARK: - Reading

    func refresh() async {
        await reload(generation: connectionGeneration, showsLoadingState: false)
    }

    private func reload(generation: UUID, showsLoadingState: Bool) async {
        guard let repository else { return }
        if showsLoadingState { isLoading = true }
        defer {
            if connectionGeneration == generation, showsLoadingState {
                isLoading = false
            }
        }

        do {
            // Retired gear included: the list shows it, and a session recorded
            // before something was retired still names it.
            let loaded = try await repository.gear(includingRetired: true)
            guard connectionGeneration == generation else { return }
            gear = loaded
            persistenceError = nil
        } catch {
            guard connectionGeneration == generation else { return }
            persistenceError = error.userFacingMessage
        }
    }

    // MARK: - Writing

    func create(_ draft: GearDraft) async {
        await save { try await $0.create(draft) }
    }

    func update(_ updated: Gear) async {
        await save { try await $0.update(updated) }
    }

    func setRetired(_ item: Gear, retired: Bool) async {
        await save { try await $0.setRetired(item, retired: retired) }
    }

    func delete(_ item: Gear) async {
        await save { try await $0.delete(item) }
    }

    /// Attaches gear to a session and reads the totals back.
    ///
    /// The reload is the point: the mileage on screen has just changed by this
    /// session's distance, and the server is the only thing that knows the new
    /// figure.
    func assign(_ item: Gear?, toSession sessionID: Int) async {
        await save { try await $0.assign(gearID: item?.id, toSession: sessionID) }
    }

    private func save(
        _ work: @escaping (GearAPIRepository) async throws -> Void
    ) async {
        guard let repository, !isSaving else { return }
        let generation = connectionGeneration
        isSaving = true
        defer { if connectionGeneration == generation { isSaving = false } }

        do {
            try await work(repository)
            guard connectionGeneration == generation else { return }
            // Totals are the server's to state, so everything is read back
            // rather than adjusted in place.
            await reload(generation: generation, showsLoadingState: false)
        } catch {
            guard connectionGeneration == generation else { return }
            persistenceError = error.userFacingMessage
        }
    }
}

#if DEBUG
extension GearStore {
    /// A few shoes and a bike, for looking at the screens without an account.
    static var preview: GearStore {
        let store = GearStore()
        store.gear = [
            Gear(
                id: 1,
                kind: .shoe,
                name: "Pegasus 40",
                brand: "Nike",
                notes: "",
                totalDistanceKilometers: 512.4,
                initialDistanceKilometers: 40,
                retireAtKilometers: 800,
                isDefault: true,
                retiredAt: nil,
                sessionCount: 63,
                // The marked default, but not the most recent: auto-fill
                // should pass over it in favour of the Vaporfly below.
                lastUsedAt: Date().addingTimeInterval(-60 * 60 * 24 * 9)
            ),
            Gear(
                id: 2,
                kind: .shoe,
                name: "Vaporfly 3",
                brand: "Nike",
                notes: "Race day only.",
                totalDistanceKilometers: 96.2,
                initialDistanceKilometers: 0,
                retireAtKilometers: 240,
                isDefault: false,
                retiredAt: nil,
                sessionCount: 9,
                lastUsedAt: Date().addingTimeInterval(-60 * 60 * 24 * 2)
            ),
            // No stated life, so its bar is drawn against the most worn.
            Gear(
                id: 3,
                kind: .shoe,
                name: "Ghost 15",
                brand: "Brooks",
                notes: "",
                totalDistanceKilometers: 861.0,
                initialDistanceKilometers: 0,
                retireAtKilometers: nil,
                isDefault: false,
                retiredAt: nil,
                sessionCount: 104,
                lastUsedAt: nil
            ),
            // No stated life at all, which is the default.
            Gear(
                id: 4,
                kind: .bike,
                name: "Domane AL 3",
                brand: "Trek",
                notes: "",
                totalDistanceKilometers: 1_284.7,
                initialDistanceKilometers: 0,
                retireAtKilometers: nil,
                isDefault: true,
                retiredAt: nil,
                sessionCount: 41,
                lastUsedAt: Date().addingTimeInterval(-60 * 60 * 24 * 4)
            ),
            Gear(
                id: 5,
                kind: .shoe,
                name: "Clifton 9",
                brand: "Hoka",
                notes: "",
                totalDistanceKilometers: 774.3,
                initialDistanceKilometers: 0,
                retireAtKilometers: 700,
                isDefault: false,
                retiredAt: Date().addingTimeInterval(-60 * 60 * 24 * 30),
                sessionCount: 88,
                lastUsedAt: nil
            ),
        ]
        return store
    }
}
#endif
