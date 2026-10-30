//
//  ExerciseLibrary.swift
//  IOS Frontend
//
//  The exercise library shipped with the app: every movement, how it is
//  done, what it works and what it needs, searchable without a connection.
//

import Foundation

/// One exercise in the library.
///
/// The same file seeds the server's shared catalogue (`repbase/core/data/
/// exercise_library.json`; `Scripts/sync-exercise-library.sh` copies it
/// here), so a library exercise and the server's row for it share a name.
/// That name is how a choice made here becomes a server exercise when the
/// workout is saved: the save looks the name up and creates it only where the
/// server has never had it, as an older server will not have.
nonisolated struct LibraryExercise: Identifiable, Hashable, Decodable, Sendable {
    let slug: String
    let name: String
    let aliases: [String]
    /// The vocabulary values as written in the file. Kept as strings so a
    /// library from a later build that adds a value still loads; the typed
    /// accessors below read them, and treat an unknown one as absent.
    let category: String
    let equipment: String
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let movementPattern: String
    let mechanic: String?
    let force: String?
    let level: String
    let disciplines: [String]
    let family: String
    let instructions: [String]

    var id: String { slug }

    private enum CodingKeys: String, CodingKey {
        case slug, name, aliases, category, equipment, mechanic, force, level, disciplines, family, instructions
        case primaryMuscles = "primary_muscles"
        case secondaryMuscles = "secondary_muscles"
        case movementPattern = "movement_pattern"
    }

    var type: ExerciseType? { ExerciseType(rawValue: category) }
    var equipmentKind: ExerciseEquipment? { ExerciseEquipment(rawValue: equipment) }
    var pattern: MovementPattern? { MovementPattern(rawValue: movementPattern) }
    var difficulty: ExerciseLevel? { ExerciseLevel(rawValue: level) }
    var primary: [ExerciseMuscle] { primaryMuscles.compactMap(ExerciseMuscle.init(rawValue:)) }
    var secondary: [ExerciseMuscle] { secondaryMuscles.compactMap(ExerciseMuscle.init(rawValue:)) }
    var disciplineKinds: [ExerciseDiscipline] { disciplines.compactMap(ExerciseDiscipline.init(rawValue:)) }

    /// The region its first primary muscle belongs to, which is what the
    /// server writes into `muscle_group` and what the muscle chips filter on.
    var region: MuscleRegion? { primary.first?.region }

    /// "Chest · Barbell", for a row in a list.
    var detailLine: String {
        [region?.title, equipmentKind?.title].compactMap { $0 }.joined(separator: " · ")
    }

    /// The name in the language on screen. `name` stays the exercise's
    /// identity -- what the server's row is called and what a saved workout
    /// finds it by -- so it is only ever this that is shown.
    var localizedName: String { ExerciseLibraryText.localized(name) }

    /// How to do it, step by step, in the language on screen.
    var localizedInstructions: [String] { instructions.map { ExerciseLibraryText.localized($0) } }
}

/// The library's own text in the chosen language.
///
/// Names and instructions live in `ExerciseLibrary.xcstrings`, keyed by their
/// English, rather than in `Localizable`: they come from the library file, not
/// from code, and a thousand exercises would bury the app's own strings. They
/// are looked up in `Bundle.app` like everything else, so a language picked in
/// Settings applies at once. Text the table lacks -- an exercise added to the
/// library since it was translated -- reads in English.
nonisolated enum ExerciseLibraryText {
    static let table = "ExerciseLibrary"

    static func localized(_ english: String, in bundle: Bundle = .app) -> String {
        bundle.localizedString(forKey: english, value: english, table: table)
    }
}

/// Every lookup the pickers make, over the whole library at once.
///
/// Built once: the file is read and every name and alias folded for search
/// up front, so a keystroke filters a thousand exercises without allocating a
/// thousand lowercased strings. Translated names are folded the first time a
/// language is searched, and kept for as long as it stays chosen.
nonisolated final class ExerciseLibrary: Sendable {
    let exercises: [LibraryExercise]
    let version: String
    private let searchIndex: [String: Entry]
    /// Folded English name to the exercise's position in `exercises`.
    private let positionByName: [String: Int]
    private let translatedIndex = TranslatedIndex()

    private struct Entry: Sendable {
        let foldedName: String
        let foldedAliases: [String]
        /// Name, aliases and vocabulary words together.
        let haystack: String
    }

    private struct File: Decodable {
        let schemaVersion: Int
        let libraryVersion: String
        let exercises: [LibraryExercise]

        private enum CodingKeys: String, CodingKey {
            case exercises
            case schemaVersion = "schema_version"
            case libraryVersion = "library_version"
        }
    }

    enum LoadError: Error, Equatable {
        case unsupportedSchema(Int)
    }

    static let supportedSchemaVersion = 1

    init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.schemaVersion == Self.supportedSchemaVersion else {
            throw LoadError.unsupportedSchema(file.schemaVersion)
        }
        exercises = file.exercises
        version = file.libraryVersion
        var index: [String: Entry] = [:]
        var positions: [String: Int] = [:]
        for (position, exercise) in file.exercises.enumerated() {
            let name = ExerciseSearch.folded(exercise.name)
            if positions[name] == nil { positions[name] = position }
            let aliases = exercise.aliases.map(ExerciseSearch.folded)
            let vocabulary = [
                exercise.equipmentKind?.searchTerm, exercise.region?.searchTerm,
            ] + exercise.primary.map(\.searchTerm)
            index[exercise.slug] = Entry(
                foldedName: name,
                foldedAliases: aliases,
                haystack: ([name] + aliases + vocabulary.compactMap { $0 }).joined(separator: " ")
            )
        }
        searchIndex = index
        positionByName = positions
    }

    /// The library bundled with the app, read once on first use. Nil only if
    /// the bundle is damaged, in which case the pickers fall back to the
    /// server's catalogue alone.
    static let shared: ExerciseLibrary? = bundled()

    static func bundled(in bundle: Bundle = .main) -> ExerciseLibrary? {
        guard let url = bundle.url(forResource: "exercise_library", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? ExerciseLibrary(data: data)
    }

    /// Exercises matching the query and every filter given, best match first.
    ///
    /// Every word of the query has to appear in the name, an alias, or the
    /// exercise's equipment or muscles, so "db row" and "row dumbbell" both
    /// find Bent Over Row (Dumbbell). The name in the language on screen
    /// counts as much as the English one: "press de banca" and "bench press"
    /// find the same exercise. Ranked so that what somebody most likely meant
    /// comes first: an exact name or alias, then a name that starts with what
    /// was typed, then the rest in the order of the names as shown.
    func search(_ query: String, filter: ExerciseFilter = ExerciseFilter(), in bundle: Bundle = .app) -> [LibraryExercise] {
        let words = ExerciseSearch.words(query)
        let folded = words.joined(separator: " ")
        let translated = translatedIndex.names(for: exercises, in: bundle)
        let candidates = exercises.filter(filter.matches)
        guard !words.isEmpty else {
            return candidates.sorted { translated.areInOrder($0, $1) }
        }
        var ranked: [(rank: Int, exercise: LibraryExercise)] = []
        for exercise in candidates {
            guard let entry = searchIndex[exercise.slug] else { continue }
            let shown = translated.folded[exercise.slug] ?? entry.foldedName
            guard words.allSatisfy({ entry.haystack.contains($0) || shown.contains($0) }) else { continue }
            let rank: Int
            if entry.foldedName == folded || shown == folded || entry.foldedAliases.contains(folded) {
                rank = 0
            } else if entry.foldedName.hasPrefix(folded) || shown.hasPrefix(folded) {
                rank = 1
            } else if entry.foldedAliases.contains(where: { $0.hasPrefix(folded) }) {
                rank = 2
            } else if words.allSatisfy({ entry.foldedName.contains($0) || shown.contains($0) }) {
                rank = 3
            } else {
                rank = 4
            }
            ranked.append((rank, exercise))
        }
        return ranked
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : translated.areInOrder($0.exercise, $1.exercise) }
            .map(\.exercise)
    }

    /// How to show an exercise called `name`: in the language on screen when
    /// it is one of the library's -- as the server's shared exercises are,
    /// since the library names them -- and as written otherwise. Somebody's
    /// own exercise keeps the name they gave it.
    ///
    /// Only the library's own names count, not aliases: an exercise saved as
    /// "Deadlift" was named that by somebody, and showing it as "Deadlift
    /// (Barbell)" translated would say more than they did.
    func displayName(for name: String, in bundle: Bundle = .app) -> String {
        guard let position = positionByName[ExerciseSearch.folded(name)] else { return name }
        return ExerciseLibraryText.localized(exercises[position].name, in: bundle)
    }

    /// `displayName(for:)` on the bundled library, for the many places that
    /// show a name they were given.
    static func displayName(_ name: String) -> String {
        shared?.displayName(for: name) ?? name
    }

    /// The library exercise a name refers to, by its name or one of its
    /// aliases. How an exercise somebody created as "Deadlift" is recognised
    /// as the library's Deadlift (Barbell) rather than listed twice.
    func exercise(named name: String) -> LibraryExercise? {
        let folded = ExerciseSearch.folded(name)
        guard !folded.isEmpty else { return nil }
        if let position = positionByName[folded] {
            return exercises[position]
        }
        return exercises.first { searchIndex[$0.slug]?.foldedAliases.contains(folded) == true }
    }

    func exercise(slug: String) -> LibraryExercise? {
        exercises.first { $0.slug == slug }
    }

    /// Other versions of the same movement: every bench press, say, for the
    /// barbell one.
    func variations(of exercise: LibraryExercise) -> [LibraryExercise] {
        exercises.filter { $0.family == exercise.family && $0.slug != exercise.slug }
    }

    /// The values the library actually uses, in each vocabulary's own order,
    /// so a filter never offers something that matches nothing.
    var equipmentInUse: [ExerciseEquipment] {
        let used = Set(exercises.compactMap(\.equipmentKind))
        return ExerciseEquipment.allCases.filter(used.contains)
    }

    var patternsInUse: [MovementPattern] {
        let used = Set(exercises.compactMap(\.pattern))
        return MovementPattern.allCases.filter(used.contains)
    }

    var typesInUse: [ExerciseType] {
        let used = Set(exercises.compactMap(\.type))
        return ExerciseType.allCases.filter(used.contains)
    }

    var disciplinesInUse: [ExerciseDiscipline] {
        let used = Set(exercises.flatMap(\.disciplineKinds))
        return ExerciseDiscipline.allCases.filter(used.contains)
    }
}

/// The library's names in one language: folded for search, and the order
/// they are listed in there.
private nonisolated struct TranslatedNames: Sendable {
    let folded: [String: String]
    let order: [String: Int]

    func areInOrder(_ first: LibraryExercise, _ second: LibraryExercise) -> Bool {
        (order[first.slug] ?? .max) < (order[second.slug] ?? .max)
    }
}

/// The translated names of the language last searched in. Rebuilt only when
/// the language changes, which takes a few milliseconds for the whole library.
private nonisolated final class TranslatedIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: (path: String, names: TranslatedNames)?

    func names(for exercises: [LibraryExercise], in bundle: Bundle) -> TranslatedNames {
        let path = bundle.bundlePath
        if let cached = lock.withLock({ cached }), cached.path == path {
            return cached.names
        }
        let shown = exercises.map { ($0.slug, ExerciseLibraryText.localized($0.name, in: bundle)) }
        // The chosen language's own alphabetical order: pinyin for Chinese,
        // the kana order for Japanese.
        let url = bundle.bundleURL
        let locale = Locale(identifier: url.pathExtension == "lproj" ? url.deletingPathExtension().lastPathComponent : "en")
        let sorted = shown.sorted {
            $0.1.compare($1.1, options: [.caseInsensitive, .numeric], range: nil, locale: locale) == .orderedAscending
        }
        let names = TranslatedNames(
            folded: Dictionary(shown.map { ($0.0, ExerciseSearch.folded($0.1)) }, uniquingKeysWith: { first, _ in first }),
            order: Dictionary(sorted.enumerated().map { ($1.0, $0) }, uniquingKeysWith: { first, _ in first })
        )
        lock.withLock { cached = (path, names) }
        return names
    }
}

/// What a list of exercises is narrowed to. Nil is "any".
nonisolated struct ExerciseFilter: Hashable, Sendable {
    var region: MuscleRegion?
    var equipment: ExerciseEquipment?
    var pattern: MovementPattern?
    var type: ExerciseType?
    var discipline: ExerciseDiscipline?

    /// How many filters beyond the muscle chips are on, for the badge on the
    /// Filters button.
    var refinementCount: Int {
        [equipment != nil, pattern != nil, type != nil, discipline != nil].filter { $0 }.count
    }

    var isEmpty: Bool { region == nil && refinementCount == 0 }

    func matches(_ exercise: LibraryExercise) -> Bool {
        (region == nil || exercise.primary.contains { $0.region == region })
            && (equipment == nil || exercise.equipmentKind == equipment)
            && (pattern == nil || exercise.pattern == pattern)
            && (type == nil || exercise.type == type)
            && (discipline == nil || exercise.disciplineKinds.contains(discipline!))
    }
}

/// How names are compared for search: case, accents and punctuation ignored.
nonisolated enum ExerciseSearch {
    static func folded(_ text: String) -> String {
        let lowered = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var result = ""
        var lastWasSpace = true
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                result.append(" ")
                lastWasSpace = true
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    static func words(_ text: String) -> [String] {
        folded(text).split(separator: " ").map(String.init)
    }
}

// MARK: - Vocabularies

/// What kind of exercise it is.
nonisolated enum ExerciseType: String, CaseIterable, Identifiable, Hashable, Sendable {
    case strength
    case olympic
    case plyometric
    case cardio
    case isometric
    case stretching
    case mobility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength: String(localized: "Strength", bundle: .app, locale: .app, comment: "A type of exercise")
        case .olympic: String(localized: "Olympic lifts", bundle: .app, locale: .app, comment: "A type of exercise: snatch, clean and jerk and their variations")
        case .plyometric: String(localized: "Plyometrics", bundle: .app, locale: .app, comment: "A type of exercise: jumps and explosive moves")
        case .cardio: String(localized: "Cardio", bundle: .app, locale: .app, comment: "A type of exercise")
        case .isometric: String(localized: "Holds", bundle: .app, locale: .app, comment: "A type of exercise: static holds such as a plank")
        case .stretching: String(localized: "Stretching", bundle: .app, locale: .app, comment: "An activity: stretching and mobility work")
        case .mobility: String(localized: "Mobility", bundle: .app, locale: .app, comment: "A type of exercise: joint mobility and activation drills")
        }
    }
}

/// The one piece of equipment that defines an exercise.
nonisolated enum ExerciseEquipment: String, CaseIterable, Identifiable, Hashable, Sendable {
    case barbell
    case dumbbell
    case kettlebell
    case cable
    case machine
    case smithMachine = "smith_machine"
    case ezBar = "ez_bar"
    case trapBar = "trap_bar"
    case resistanceBand = "resistance_band"
    case bodyweight
    case medicineBall = "medicine_ball"
    case stabilityBall = "stability_ball"
    case foamRoller = "foam_roller"
    case pullUpBar = "pull_up_bar"
    case rings
    case suspensionTrainer = "suspension_trainer"
    case sled
    case plate
    case landmine
    case box
    case rope
    case sandbag
    case cardioMachine = "cardio_machine"
    case other

    var id: String { rawValue }

    /// The English word a search for it would use.
    var searchTerm: String {
        switch self {
        case .smithMachine: "smith machine"
        case .ezBar: "ez bar curl bar"
        case .trapBar: "trap bar hex bar"
        case .resistanceBand: "band resistance band"
        case .bodyweight: "bodyweight body weight no equipment"
        case .medicineBall: "medicine ball med ball"
        case .stabilityBall: "stability ball swiss ball"
        case .foamRoller: "foam roller"
        case .pullUpBar: "pull up bar"
        case .suspensionTrainer: "suspension trx"
        case .cardioMachine: "machine cardio"
        case .dumbbell: "dumbbell db"
        case .barbell: "barbell bb"
        case .kettlebell: "kettlebell kb"
        default: rawValue
        }
    }

    var title: String {
        switch self {
        case .barbell: String(localized: "Barbell", bundle: .app, locale: .app, comment: "Exercise equipment")
        case .dumbbell: String(localized: "Dumbbell", bundle: .app, locale: .app, comment: "Exercise equipment")
        case .kettlebell: String(localized: "Kettlebell", bundle: .app, locale: .app, comment: "Exercise equipment")
        case .cable: String(localized: "Cable", bundle: .app, locale: .app, comment: "Exercise equipment: a cable machine")
        case .machine: String(localized: "Machine", bundle: .app, locale: .app, comment: "Exercise equipment: a weight machine")
        case .smithMachine: String(localized: "Smith machine", bundle: .app, locale: .app, comment: "Exercise equipment")
        case .ezBar: String(localized: "EZ bar", bundle: .app, locale: .app, comment: "Exercise equipment: a curl bar")
        case .trapBar: String(localized: "Trap bar", bundle: .app, locale: .app, comment: "Exercise equipment: a hexagonal deadlift bar")
        case .resistanceBand: String(localized: "Resistance band", bundle: .app, locale: .app, comment: "Exercise equipment")
        case .bodyweight: String(localized: "Bodyweight", bundle: .app, locale: .app, comment: "Exercise equipment: none, just your body")
        case .medicineBall: String(localized: "Medicine ball", bundle: .app, locale: .app, comment: "Exercise equipment")
        case .stabilityBall: String(localized: "Stability ball", bundle: .app, locale: .app, comment: "Exercise equipment")
        case .foamRoller: String(localized: "Foam roller", bundle: .app, locale: .app, comment: "Exercise equipment")
        case .pullUpBar: String(localized: "Pull-up bar", bundle: .app, locale: .app, comment: "Exercise equipment")
        case .rings: String(localized: "Rings", bundle: .app, locale: .app, comment: "Exercise equipment: gymnastic rings")
        case .suspensionTrainer: String(localized: "Suspension trainer", bundle: .app, locale: .app, comment: "Exercise equipment, such as TRX straps")
        case .sled: String(localized: "Sled", bundle: .app, locale: .app, comment: "Exercise equipment: a weighted sled")
        case .plate: String(localized: "Weight plate", bundle: .app, locale: .app, comment: "Exercise equipment")
        case .landmine: String(localized: "Landmine", bundle: .app, locale: .app, comment: "Exercise equipment: a barbell anchored at one end")
        case .box: String(localized: "Box", bundle: .app, locale: .app, comment: "Exercise equipment: a plyo box or step")
        case .rope: String(localized: "Rope", bundle: .app, locale: .app, comment: "Exercise equipment: a battle rope or climbing rope")
        case .sandbag: String(localized: "Sandbag", bundle: .app, locale: .app, comment: "Exercise equipment")
        case .cardioMachine: String(localized: "Cardio machine", bundle: .app, locale: .app, comment: "Exercise equipment: a rower, bike or ski erg")
        case .other: String(localized: "Other", bundle: .app, locale: .app, comment: "A cardio machine not in the list")
        }
    }
}

/// The groups somebody filters by. Each muscle belongs to one.
nonisolated enum MuscleRegion: String, CaseIterable, Identifiable, Hashable, Sendable {
    case chest
    case back
    case shoulders
    case arms
    case core
    case legs
    case glutes
    case fullBody = "full_body"
    case neck

    var id: String { rawValue }

    var searchTerm: String { self == .fullBody ? "full body" : rawValue }

    /// The English word the server stores in `muscle_group`, which the
    /// backend's library sync writes too.
    var serverName: String {
        switch self {
        case .fullBody: "Full Body"
        default: rawValue.capitalized
        }
    }

    var title: String {
        switch self {
        case .chest: String(localized: "Chest", bundle: .app, locale: .app, comment: "A muscle group")
        // Its own key: "Back" alone is the navigation button, which other
        // languages translate as "go back", not as the muscles.
        case .back: String(localized: "Back (muscle group)", defaultValue: "Back", bundle: .app, locale: .app, comment: "A muscle group: the back")
        case .shoulders: String(localized: "Shoulders", bundle: .app, locale: .app, comment: "A muscle group")
        case .arms: String(localized: "Arms", bundle: .app, locale: .app, comment: "A muscle group")
        case .core: String(localized: "Core", bundle: .app, locale: .app, comment: "A muscle group: abs and obliques")
        case .legs: String(localized: "Legs", bundle: .app, locale: .app, comment: "A muscle group")
        case .glutes: String(localized: "Glutes", bundle: .app, locale: .app, comment: "A muscle group")
        case .fullBody: String(localized: "Full body", bundle: .app, locale: .app, comment: "A muscle group: the whole body")
        case .neck: String(localized: "Neck", bundle: .app, locale: .app, comment: "A muscle group")
        }
    }

    /// The English region the server writes into `muscle_group`, which is
    /// how an exercise from the server is placed in a region.
    init?(serverMuscleGroup: String) {
        let folded = ExerciseSearch.folded(serverMuscleGroup)
        guard let match = MuscleRegion.allCases.first(where: { $0.searchTerm == folded }) else { return nil }
        self = match
    }
}

nonisolated enum ExerciseMuscle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case chest, shoulders, triceps, biceps, forearms, traps, lats
    case upperBack = "upper_back"
    case lowerBack = "lower_back"
    case abdominals, obliques
    case hipFlexors = "hip_flexors"
    case glutes, quadriceps, hamstrings, adductors, abductors, calves, tibialis, neck
    case fullBody = "full_body"

    var id: String { rawValue }

    var region: MuscleRegion {
        switch self {
        case .chest: .chest
        case .lats, .traps, .upperBack, .lowerBack: .back
        case .shoulders: .shoulders
        case .biceps, .triceps, .forearms: .arms
        case .abdominals, .obliques, .hipFlexors: .core
        case .quadriceps, .hamstrings, .adductors, .abductors, .calves, .tibialis: .legs
        case .glutes: .glutes
        case .neck: .neck
        case .fullBody: .fullBody
        }
    }

    var searchTerm: String { rawValue.replacingOccurrences(of: "_", with: " ") }

    var title: String {
        switch self {
        case .chest: String(localized: "Chest", bundle: .app, locale: .app, comment: "A muscle group")
        case .shoulders: String(localized: "Shoulders", bundle: .app, locale: .app, comment: "A muscle group")
        case .triceps: String(localized: "Triceps", bundle: .app, locale: .app, comment: "A muscle")
        case .biceps: String(localized: "Biceps", bundle: .app, locale: .app, comment: "A muscle")
        case .forearms: String(localized: "Forearms", bundle: .app, locale: .app, comment: "A muscle")
        case .traps: String(localized: "Traps", bundle: .app, locale: .app, comment: "A muscle: the trapezius")
        case .lats: String(localized: "Lats", bundle: .app, locale: .app, comment: "A muscle: the latissimus dorsi")
        case .upperBack: String(localized: "Upper back", bundle: .app, locale: .app, comment: "Muscles: rhomboids and mid traps")
        case .lowerBack: String(localized: "Lower back", bundle: .app, locale: .app, comment: "Muscles: the spinal erectors")
        case .abdominals: String(localized: "Abs", bundle: .app, locale: .app, comment: "A muscle: the abdominals")
        case .obliques: String(localized: "Obliques", bundle: .app, locale: .app, comment: "A muscle")
        case .hipFlexors: String(localized: "Hip flexors", bundle: .app, locale: .app, comment: "Muscles")
        case .glutes: String(localized: "Glutes", bundle: .app, locale: .app, comment: "A muscle group")
        case .quadriceps: String(localized: "Quads", bundle: .app, locale: .app, comment: "A muscle: the quadriceps")
        case .hamstrings: String(localized: "Hamstrings", bundle: .app, locale: .app, comment: "A muscle")
        case .adductors: String(localized: "Adductors", bundle: .app, locale: .app, comment: "Muscles: the inner thigh")
        case .abductors: String(localized: "Abductors", bundle: .app, locale: .app, comment: "Muscles: the outer hip")
        case .calves: String(localized: "Calves", bundle: .app, locale: .app, comment: "A muscle")
        case .tibialis: String(localized: "Shins", bundle: .app, locale: .app, comment: "A muscle: the tibialis anterior")
        case .neck: String(localized: "Neck", bundle: .app, locale: .app, comment: "A muscle group")
        case .fullBody: String(localized: "Full body", bundle: .app, locale: .app, comment: "A muscle group: the whole body")
        }
    }
}

/// The movement an exercise trains, which is how a balanced program is
/// usually put together: a squat, a hinge, a push and a pull.
nonisolated enum MovementPattern: String, CaseIterable, Identifiable, Hashable, Sendable {
    case squat, hinge, lunge
    case horizontalPush = "horizontal_push"
    case verticalPush = "vertical_push"
    case horizontalPull = "horizontal_pull"
    case verticalPull = "vertical_pull"
    case carry, rotation, core, isolation, explosive, locomotion, mobility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .squat: String(localized: "Squat", bundle: .app, locale: .app, comment: "A movement pattern")
        case .hinge: String(localized: "Hinge", bundle: .app, locale: .app, comment: "A movement pattern: bending at the hips, as in a deadlift")
        case .lunge: String(localized: "Lunge & single leg", bundle: .app, locale: .app, comment: "A movement pattern")
        case .horizontalPush: String(localized: "Horizontal push", bundle: .app, locale: .app, comment: "A movement pattern, as in a bench press")
        case .verticalPush: String(localized: "Vertical push", bundle: .app, locale: .app, comment: "A movement pattern, as in an overhead press")
        case .horizontalPull: String(localized: "Horizontal pull", bundle: .app, locale: .app, comment: "A movement pattern, as in a row")
        case .verticalPull: String(localized: "Vertical pull", bundle: .app, locale: .app, comment: "A movement pattern, as in a pull-up")
        case .carry: String(localized: "Carry", bundle: .app, locale: .app, comment: "A movement pattern, as in a farmer's carry")
        case .rotation: String(localized: "Rotation (movement pattern)", defaultValue: "Rotation", bundle: .app, locale: .app, comment: "A movement pattern: twisting or resisting a twist. Not the weekly workout rotation")
        case .core: String(localized: "Core", bundle: .app, locale: .app, comment: "A muscle group: abs and obliques")
        case .isolation: String(localized: "Isolation", bundle: .app, locale: .app, comment: "A movement pattern: one joint, one muscle, as in a curl")
        case .explosive: String(localized: "Explosive", bundle: .app, locale: .app, comment: "A movement pattern: fast, powerful lifts and jumps")
        case .locomotion: String(localized: "Locomotion", bundle: .app, locale: .app, comment: "A movement pattern: running, rowing, crawling")
        case .mobility: String(localized: "Mobility", bundle: .app, locale: .app, comment: "A type of exercise: joint mobility and activation drills")
        }
    }
}

nonisolated enum ExerciseDiscipline: String, CaseIterable, Identifiable, Hashable, Sendable {
    case bodybuilding, powerlifting
    case olympicWeightlifting = "olympic_weightlifting"
    case crossfit, calisthenics, strongman, functional, mobility, rehab, cardio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bodybuilding: String(localized: "Bodybuilding", bundle: .app, locale: .app, comment: "A training discipline")
        case .powerlifting: String(localized: "Powerlifting", bundle: .app, locale: .app, comment: "A training discipline")
        case .olympicWeightlifting: String(localized: "Olympic weightlifting", bundle: .app, locale: .app, comment: "A training discipline")
        case .crossfit: String(localized: "CrossFit", bundle: .app, locale: .app, comment: "An activity: CrossFit-style functional fitness")
        case .calisthenics: String(localized: "Calisthenics", bundle: .app, locale: .app, comment: "An activity: bodyweight strength training")
        case .strongman: String(localized: "Strongman", bundle: .app, locale: .app, comment: "A training discipline")
        case .functional: String(localized: "Functional fitness", bundle: .app, locale: .app, comment: "A training discipline")
        case .mobility: String(localized: "Mobility", bundle: .app, locale: .app, comment: "A type of exercise: joint mobility and activation drills")
        case .rehab: String(localized: "Low impact & rehab", bundle: .app, locale: .app, comment: "A training discipline: gentle exercises often used in rehabilitation")
        case .cardio: String(localized: "Cardio", bundle: .app, locale: .app, comment: "A type of exercise")
        }
    }
}

nonisolated enum ExerciseLevel: String, CaseIterable, Identifiable, Hashable, Sendable {
    case beginner, intermediate, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner: String(localized: "Beginner", bundle: .app, locale: .app, comment: "An exercise's difficulty")
        case .intermediate: String(localized: "Intermediate", bundle: .app, locale: .app, comment: "An exercise's difficulty")
        case .advanced: String(localized: "Advanced", bundle: .app, locale: .app, comment: "An exercise's difficulty")
        }
    }
}
