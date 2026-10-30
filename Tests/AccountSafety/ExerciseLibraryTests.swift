import Foundation
import XCTest
@testable import AccountSafety

final class ExerciseLibraryTests: XCTestCase {
    private func exercise(
        _ slug: String,
        _ name: String,
        aliases: [String] = [],
        equipment: String = "barbell",
        primary: [String] = ["chest"],
        pattern: String = "horizontal_push",
        category: String = "strength",
        disciplines: [String] = ["bodybuilding"],
        family: String? = nil
    ) -> [String: Any] {
        [
            "slug": slug, "name": name, "aliases": aliases, "category": category, "equipment": equipment,
            "primary_muscles": primary, "secondary_muscles": [], "movement_pattern": pattern,
            "mechanic": NSNull(), "force": "push", "level": "beginner", "disciplines": disciplines,
            "family": family ?? slug, "instructions": ["Do it."],
        ]
    }

    private func library(_ exercises: [[String: Any]], schema: Int = 1) throws -> ExerciseLibrary {
        let file: [String: Any] = ["schema_version": schema, "library_version": "test", "sources": [], "exercises": exercises]
        return try ExerciseLibrary(data: JSONSerialization.data(withJSONObject: file))
    }

    private func sample() throws -> ExerciseLibrary {
        try library([
            exercise("bench-press-barbell", "Bench Press (Barbell)", aliases: ["Flat Bench", "Bench"], family: "bench-press"),
            exercise("bench-press-dumbbell", "Bench Press (Dumbbell)", aliases: ["DB Bench"], equipment: "dumbbell", family: "bench-press"),
            exercise("romanian-deadlift-barbell", "Romanian Deadlift (Barbell)", aliases: ["RDL"], primary: ["hamstrings"], pattern: "hinge"),
            exercise("bent-over-row-dumbbell", "Bent Over Row (Dumbbell)", aliases: ["DB Row"], equipment: "dumbbell", primary: ["upper_back"], pattern: "horizontal_pull"),
            exercise("glute-bridge", "Glute Bridge", equipment: "bodyweight", primary: ["glutes"], pattern: "hinge", disciplines: ["rehab"]),
            exercise("benchmark-hold", "Benchmark Hold", equipment: "kettlebell", primary: ["shoulders"], pattern: "carry", category: "isometric"),
            exercise("future-thing", "Future Thing", equipment: "hoverboard", primary: ["antigravity"], pattern: "teleport"),
        ])
    }

    func testAnExactNameOrAliasComesFirstThenNamesStartingWithTheQuery() throws {
        let library = try sample()
        XCTAssertEqual(library.search("rdl").first?.slug, "romanian-deadlift-barbell")
        XCTAssertEqual(library.search("bench").first?.slug, "bench-press-barbell", "Bench is an alias of the barbell press")
        XCTAssertEqual(Set(library.search("bench").prefix(3).map(\.slug)), ["bench-press-barbell", "bench-press-dumbbell", "benchmark-hold"])
    }

    func testEveryWordMustMatchSomewhereInAnyOrder() throws {
        let library = try sample()
        XCTAssertEqual(library.search("row dumbbell").map(\.slug), ["bent-over-row-dumbbell"])
        XCTAssertEqual(library.search("db row").map(\.slug), ["bent-over-row-dumbbell"])
        XCTAssertEqual(library.search("ROMÁNIAN  deadlift!").map(\.slug), ["romanian-deadlift-barbell"], "Case, accents and punctuation are ignored")
        XCTAssertTrue(library.search("bench squat").isEmpty)
        XCTAssertEqual(library.search("").count, 7)
    }

    func testFiltersCombineWithSearch() throws {
        let library = try sample()
        XCTAssertEqual(library.search("", filter: ExerciseFilter(region: .chest)).count, 2)
        XCTAssertEqual(library.search("bench", filter: ExerciseFilter(equipment: .dumbbell)).map(\.slug), ["bench-press-dumbbell"])
        XCTAssertEqual(library.search("", filter: ExerciseFilter(pattern: .hinge)).count, 2)
        XCTAssertEqual(library.search("", filter: ExerciseFilter(discipline: .rehab)).map(\.slug), ["glute-bridge"])
        XCTAssertEqual(library.search("", filter: ExerciseFilter(type: .isometric)).map(\.slug), ["benchmark-hold"])
        XCTAssertEqual(ExerciseFilter(region: .chest, equipment: .barbell, discipline: .rehab).refinementCount, 2)
    }

    func testANameOrAliasFindsTheSameExerciseSoNothingIsListedTwice() throws {
        let library = try sample()
        XCTAssertEqual(library.exercise(named: "  flat bench ")?.slug, "bench-press-barbell")
        XCTAssertEqual(library.exercise(named: "bench press (barbell)")?.slug, "bench-press-barbell")
        XCTAssertNil(library.exercise(named: "Zercher Squat"))
        XCTAssertEqual(library.variations(of: try XCTUnwrap(library.exercise(slug: "bench-press-barbell"))).map(\.slug), ["bench-press-dumbbell"])
    }

    func testValuesFromALaterLibraryAreToleratedNotFatal() throws {
        let future = try XCTUnwrap(sample().exercise(slug: "future-thing"))
        XCTAssertNil(future.equipmentKind)
        XCTAssertNil(future.pattern)
        XCTAssertTrue(future.primary.isEmpty)
        XCTAssertEqual(future.detailLine, "")
        XCTAssertThrowsError(try library([], schema: 2)) { error in
            XCTAssertEqual(error as? ExerciseLibrary.LoadError, .unsupportedSchema(2))
        }
    }

    func testEveryMuscleBelongsToARegionTheServerNames() {
        for muscle in ExerciseMuscle.allCases {
            XCTAssertEqual(MuscleRegion(serverMuscleGroup: muscle.region.serverName), muscle.region)
        }
        XCTAssertEqual(MuscleRegion(serverMuscleGroup: "Full Body"), .fullBody)
        XCTAssertNil(MuscleRegion(serverMuscleGroup: "Wings"))
    }

    // MARK: - The library the app ships

    /// The bundled file, checked as the app will read it: complete, unique by
    /// name and alias so nothing is listed twice, and every value one the
    /// filters know.
    func testTheShippedLibraryIsCompleteAndUnambiguous() throws {
        let repository = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        let url = URL(fileURLWithPath: repository)
            .appendingPathComponent("IOS Frontend/IOS Frontend/Resources/ExerciseLibrary/exercise_library.json")
        let library = try ExerciseLibrary(data: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(library.exercises.count, 800, "The library is meant to be comprehensive")

        var names: [String: String] = [:]
        for exercise in library.exercises {
            XCTAssertNotNil(exercise.type, "\(exercise.slug): category \(exercise.category)")
            XCTAssertNotNil(exercise.equipmentKind, "\(exercise.slug): equipment \(exercise.equipment)")
            XCTAssertNotNil(exercise.pattern, "\(exercise.slug): pattern \(exercise.movementPattern)")
            XCTAssertNotNil(exercise.difficulty, "\(exercise.slug): level \(exercise.level)")
            XCTAssertFalse(exercise.primary.isEmpty, "\(exercise.slug) works no muscle")
            XCTAssertEqual(exercise.primary.count, exercise.primaryMuscles.count, "\(exercise.slug): unknown muscle")
            XCTAssertEqual(exercise.secondary.count, exercise.secondaryMuscles.count, "\(exercise.slug): unknown muscle")
            XCTAssertEqual(exercise.disciplineKinds.count, exercise.disciplines.count, "\(exercise.slug): unknown discipline")
            XCTAssertFalse(exercise.disciplines.isEmpty, exercise.slug)
            XCTAssertFalse(exercise.instructions.isEmpty, "\(exercise.slug) has no instructions")
            XCTAssertLessThanOrEqual(exercise.name.count, 150, exercise.slug)
            for name in [exercise.name] + exercise.aliases {
                let folded = ExerciseSearch.folded(name)
                if let other = names[folded], other != exercise.slug {
                    XCTFail("“\(name)” names both \(other) and \(exercise.slug)")
                }
                names[folded] = exercise.slug
            }
        }
        XCTAssertEqual(Set(library.exercises.map(\.slug)).count, library.exercises.count, "Slugs are unique")
        // Each discipline the app was asked to cover has exercises in it.
        for discipline in ExerciseDiscipline.allCases {
            XCTAssertFalse(library.search("", filter: ExerciseFilter(discipline: discipline)).isEmpty, "\(discipline)")
        }
        for equipment: ExerciseEquipment in [.barbell, .dumbbell, .kettlebell, .cable, .machine, .resistanceBand, .bodyweight] {
            XCTAssertFalse(library.search("", filter: ExerciseFilter(equipment: equipment)).isEmpty, "\(equipment)")
        }
        // The names this account's own exercises already use resolve to the
        // library instead of appearing twice.
        XCTAssertNotNil(library.exercise(named: "Deadlift"))
        XCTAssertNotNil(library.exercise(named: "Incline Bench"))
    }
}
