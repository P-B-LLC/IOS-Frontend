//
//  ExerciseCatalog.swift
//  IOS Frontend
//
//  The exercises people choose from, shared by every screen that offers them.
//

import Foundation
import Observation

/// Exercises to choose from, read once and shared.
///
/// This used to be state inside the workout builder, so it was read again on
/// every visit and thrown away on leaving, and an exercise somebody created
/// while saving a workout did not appear anywhere until the builder happened
/// to be opened again and paged far enough down to reach it. Shared, it is
/// one list: the builder, the add-exercise sheet in a session and Explore all
/// see a newly created exercise as soon as the save that created it returns.
///
/// Two lists, kept apart so neither hides the other. `mine` is what the
/// account created itself, which is what somebody is most likely looking for
/// and what used to be buried pages deep in alphabetical order. `items` is the
/// paged catalogue. An exercise is one record however many workouts use it,
/// so both are de-duplicated by id: reusing an exercise in a second workout
/// never lists it twice.
@Observable
final class ExerciseCatalog {
    typealias Source = (_ page: Int, _ search: String?, _ mine: Bool) async throws -> WorkoutExercisePage

    @ObservationIgnored var source: Source?

    private(set) var items: [WorkoutExerciseChoice] = []
    private(set) var mine: [WorkoutExerciseChoice] = []
    private(set) var nextPage: Int? = 1
    private(set) var isLoading = false
    private(set) var loadError: String?
    /// Results of the server's search for the current query, when it has one.
    private(set) var searchResults: [WorkoutExerciseChoice] = []
    private(set) var searchedQuery = ""
    private(set) var isSearching = false
    private var generation = UUID()

    var hasLoaded: Bool { nextPage != 1 || !items.isEmpty }

    func reset() {
        generation = UUID()
        items = []
        mine = []
        nextPage = 1
        isLoading = false
        loadError = nil
        searchResults = []
        searchedQuery = ""
        isSearching = false
    }

    /// The first page and the account's own exercises, unless already read.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        async let page: Void = loadMore()
        async let own: Void = refreshMine()
        _ = await (page, own)
    }

    func loadMore() async {
        guard let source, !isLoading, let page = nextPage else { return }
        let generation = generation
        isLoading = true
        loadError = nil
        defer { if generation == self.generation { isLoading = false } }
        do {
            let result = try await source(page, nil, false)
            guard generation == self.generation else { return }
            items = Self.merged(items, result.items)
            nextPage = result.nextPage
        } catch is CancellationError {
        } catch {
            guard generation == self.generation else { return }
            loadError = error.userFacingMessage ?? error.localizedDescription
        }
    }

    /// Reads the account's own exercises again, after a save may have created
    /// one. Quietly: this is a list that got a little more complete, and a
    /// failure leaves the one already shown.
    func refreshMine() async {
        guard let source else { return }
        let generation = generation
        guard let result = try? await source(1, nil, true), generation == self.generation else { return }
        // A server that does not know `mine` answers with the whole catalogue;
        // only rows somebody created belong in this list either way.
        let own = result.items.filter(\.isCustom)
        mine = Self.merged([], own).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        items = Self.merged(items, own)
    }

    /// Asks the server for names containing the query, on top of filtering
    /// what is already loaded. The two together mean a search finds an
    /// exercise that has not been paged in yet, and still works against a
    /// server that ignores the parameter.
    func search(_ query: String) async {
        let trimmed = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard let source else { return }
        guard trimmed.count >= 2 else {
            searchResults = []
            searchedQuery = ""
            return
        }
        let generation = generation
        isSearching = true
        defer { if generation == self.generation { isSearching = false } }
        guard let result = try? await source(1, trimmed, false), generation == self.generation else { return }
        searchResults = Self.merged([], result.items.filter { $0.name.localizedCaseInsensitiveContains(trimmed) })
        searchedQuery = trimmed
    }

    /// Everything matching a query and a muscle group: the account's own
    /// first, then the catalogue, then anything only the server's search
    /// found -- each exercise once.
    func filtered(query: String, muscle: String?) -> [WorkoutExerciseChoice] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched = trimmed.isEmpty || searchedQuery != trimmed ? [] : searchResults
        return Self.merged(Self.merged(mine, items), searched).filter {
            (muscle == nil || $0.muscleGroup == muscle)
                && (trimmed.isEmpty || $0.name.localizedCaseInsensitiveContains(trimmed))
        }
    }

    var muscleGroups: [String] {
        Set((mine + items).map(\.muscleGroup).filter { !$0.isEmpty }).sorted()
    }

    /// An exercise already in the catalogue under this name, so creating one
    /// with a name in use picks the existing record instead of a duplicate.
    func existing(named name: String) -> WorkoutExerciseChoice? {
        (mine + items + searchResults).first { WorkoutSummary.matches($0.name, name) }
    }

    private static func merged(_ first: [WorkoutExerciseChoice], _ second: [WorkoutExerciseChoice]) -> [WorkoutExerciseChoice] {
        var seen = Set(first.map(\.id))
        return first + second.filter { seen.insert($0.id).inserted }
    }
}
