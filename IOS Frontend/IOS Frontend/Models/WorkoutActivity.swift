//
//  WorkoutActivity.swift
//  IOS Frontend
//
//  What somebody is actually doing -- tennis, a hike, a yoga class -- and
//  what is worth asking about it.
//

import Foundation

/// The specific activity a workout is.
///
/// `WorkoutType` used to be the whole answer: lifting, running, biking or
/// swimming. That is still what old builds of the app read, so it stays on the
/// wire as the activity's *family* (`family`), and an activity the old build
/// has never heard of arrives there as the nearest thing it does know. This is
/// the answer the app actually works from.
///
/// The raw values are the API's `activity` strings and must stay in step with
/// the backend's `core/activities.py`. They are a plain string on the wire,
/// not an enum, so the server can add an activity without breaking this
/// build: one it does not know reads as `.other`.
nonisolated enum WorkoutActivity: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    // Strength and conditioning
    case weightlifting
    case calisthenics
    case crossfit
    case circuitTraining = "circuit_training"
    case functionalTraining = "functional_training"
    case hiit
    // Cardio and endurance
    case running
    case jogging
    case sprinting
    case trailRunning = "trail_running"
    case walking
    case cycling
    case indoorCycling = "indoor_cycling"
    case mountainBiking = "mountain_biking"
    case swimming
    case openWaterSwimming = "open_water_swimming"
    case rowing
    case indoorRowing = "indoor_rowing"
    case elliptical
    case stairClimbing = "stair_climbing"
    case jumpRope = "jump_rope"
    // Racket sports
    case tennis
    case padel
    case badminton
    case tableTennis = "table_tennis"
    case squash
    case pickleball
    // Team sports
    case soccer
    case americanFootball = "american_football"
    case basketball
    case volleyball
    case rugby
    case hockey
    case baseball
    case handball
    case cricket
    // Combat sports
    case boxing
    case kickboxing
    case martialArts = "martial_arts"
    // Mind and body
    case yoga
    case pilates
    case stretching
    case dance
    // Outdoors
    case hiking
    case climbing
    case skiing
    case snowboarding
    case surfing
    case paddling
    case golf
    case other

    var id: String { rawValue }

    /// The activity a server value names, or `.other` for one this build was
    /// shipped before. Never fails: one unknown activity must not make a whole
    /// list of workouts unreadable.
    init(serverValue: String?, family: WorkoutType) {
        if let serverValue, let known = WorkoutActivity(rawValue: serverValue) {
            self = known
        } else if serverValue?.isEmpty == false {
            self = .other
        } else {
            self = Self.legacyDefault(for: family)
        }
    }

    // Written out so a checkpoint or draft holding an activity a later build
    // added still opens in this one.
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = WorkoutActivity(rawValue: value) ?? .other
    }

    /// What a workout saved before activities existed is.
    static func legacyDefault(for family: WorkoutType) -> WorkoutActivity {
        switch family {
        case .lifting: .weightlifting
        case .running: .running
        case .biking: .cycling
        case .swimming: .swimming
        }
    }

    /// The `workout_type` old builds read. Anything that is not a run, ride or
    /// swim reads there as lifting, which is the only family with no distance.
    var family: WorkoutType {
        switch self {
        case .running, .jogging, .sprinting, .trailRunning, .walking, .hiking: .running
        case .cycling, .indoorCycling, .mountainBiking: .biking
        case .swimming, .openWaterSwimming: .swimming
        default: .lifting
        }
    }

    var profile: ActivityProfile {
        switch self {
        case .weightlifting, .calisthenics: .strength
        case .running, .jogging, .trailRunning, .walking, .hiking, .cycling, .indoorCycling,
             .mountainBiking, .swimming, .openWaterSwimming, .rowing, .indoorRowing, .paddling: .distance
        default: .session
        }
    }

    /// Planned as exercises and logged as sets.
    var usesSets: Bool { profile == .strength }

    /// Outdoors and moving from place to place, so a GPS track means something.
    /// A pool, a court or a spin bike has no route worth recording.
    var tracksRoute: Bool {
        switch self {
        case .running, .jogging, .trailRunning, .walking, .hiking, .cycling, .mountainBiking,
             .openWaterSwimming, .rowing, .paddling: true
        default: false
        }
    }

    /// Whether distance is worth asking for, and how prominently.
    var distanceField: ActivityDistanceField {
        switch profile {
        case .distance: .primary
        case .strength: .none
        case .session:
            switch self {
            case .sprinting, .soccer, .rugby, .elliptical, .skiing, .other: .optional
            default: .none
            }
        }
    }

    /// What else is worth asking about this activity, in the order asked.
    /// Everything here is optional; the server refuses any key not listed.
    var detailFields: [ActivityDetailField] {
        switch self {
        case .crossfit: [.format, .rounds, .reps, .movements]
        case .circuitTraining, .hiit, .boxing, .kickboxing: [.rounds]
        case .martialArts: [.style, .rounds]
        case .sprinting: [.intervals]
        case .trailRunning, .hiking, .cycling, .mountainBiking: [.elevationGain]
        case .swimming: [.poolLength]
        case .tennis, .padel, .badminton, .tableTennis, .squash, .pickleball,
             .soccer, .americanFootball, .basketball, .volleyball, .rugby, .hockey,
             .baseball, .handball, .cricket: [.sessionType]
        case .yoga, .pilates: [.style]
        case .climbing: [.style, .routes]
        default: []
        }
    }

    /// The choices for `.style`, which depend on the activity.
    var styleOptions: [ActivityChoice] {
        switch self {
        case .yoga: ActivityChoice.yogaStyles
        case .pilates: ActivityChoice.pilatesStyles
        case .martialArts: ActivityChoice.martialArtsStyles
        case .climbing: ActivityChoice.climbingStyles
        default: []
        }
    }

    var category: ActivityCategory {
        switch self {
        case .weightlifting, .calisthenics, .crossfit, .circuitTraining, .functionalTraining, .hiit: .strength
        case .running, .jogging, .sprinting, .trailRunning, .walking, .cycling, .indoorCycling,
             .mountainBiking, .swimming, .openWaterSwimming, .rowing, .indoorRowing, .elliptical,
             .stairClimbing, .jumpRope: .cardio
        case .tennis, .padel, .badminton, .tableTennis, .squash, .pickleball: .racket
        case .soccer, .americanFootball, .basketball, .volleyball, .rugby, .hockey, .baseball,
             .handball, .cricket: .team
        case .boxing, .kickboxing, .martialArts: .combat
        case .yoga, .pilates, .stretching, .dance: .mindBody
        case .hiking, .climbing, .skiing, .snowboarding, .surfing, .paddling, .golf: .outdoors
        case .other: .other
        }
    }

    /// The handful offered first, before anybody searches or browses.
    static let featured: [WorkoutActivity] = [
        .weightlifting, .running, .cycling, .swimming, .tennis, .soccer, .basketball, .yoga,
        .crossfit, .hiking,
    ]

    var symbol: String {
        switch self {
        case .weightlifting: "dumbbell"
        case .calisthenics: "figure.strengthtraining.functional"
        case .crossfit: "figure.cross.training"
        case .circuitTraining: "figure.mixed.cardio"
        case .functionalTraining: "figure.core.training"
        case .hiit: "figure.highintensity.intervaltraining"
        case .running: "figure.run"
        case .jogging: "figure.run.circle"
        case .sprinting: "figure.track.and.field"
        case .trailRunning: "mountain.2"
        case .walking: "figure.walk"
        case .cycling: "figure.outdoor.cycle"
        case .indoorCycling: "figure.indoor.cycle"
        case .mountainBiking: "bicycle"
        case .swimming: "figure.pool.swim"
        case .openWaterSwimming: "figure.open.water.swim"
        case .rowing: "figure.outdoor.rowing"
        case .indoorRowing: "figure.indoor.rowing"
        case .elliptical: "figure.elliptical"
        case .stairClimbing: "figure.stair.stepper"
        case .jumpRope: "figure.jumprope"
        case .tennis: "figure.tennis"
        case .padel: "figure.racquetball"
        case .badminton: "figure.badminton"
        case .tableTennis: "figure.table.tennis"
        case .squash: "figure.squash"
        case .pickleball: "figure.pickleball"
        case .soccer: "figure.soccer"
        case .americanFootball: "figure.american.football"
        case .basketball: "figure.basketball"
        case .volleyball: "figure.volleyball"
        case .rugby: "figure.rugby"
        case .hockey: "figure.hockey"
        case .baseball: "figure.baseball"
        case .handball: "figure.handball"
        case .cricket: "figure.cricket"
        case .boxing: "figure.boxing"
        case .kickboxing: "figure.kickboxing"
        case .martialArts: "figure.martial.arts"
        case .yoga: "figure.yoga"
        case .pilates: "figure.pilates"
        case .stretching: "figure.flexibility"
        case .dance: "figure.socialdance"
        case .hiking: "figure.hiking"
        case .climbing: "figure.climbing"
        case .skiing: "figure.skiing.downhill"
        case .snowboarding: "figure.snowboarding"
        case .surfing: "figure.surfing"
        case .paddling: "figure.water.fitness"
        case .golf: "figure.golf"
        case .other: "figure.mixed.cardio"
        }
    }

    var title: String {
        switch self {
        case .weightlifting: String(localized: "Weightlifting", bundle: .app, locale: .app, comment: "An activity: training with weights")
        case .calisthenics: String(localized: "Calisthenics", bundle: .app, locale: .app, comment: "An activity: bodyweight strength training")
        case .crossfit: String(localized: "CrossFit", bundle: .app, locale: .app, comment: "An activity: CrossFit-style functional fitness")
        case .circuitTraining: String(localized: "Circuit training", bundle: .app, locale: .app, comment: "An activity")
        case .functionalTraining: String(localized: "Functional training", bundle: .app, locale: .app, comment: "An activity")
        case .hiit: String(localized: "HIIT", bundle: .app, locale: .app, comment: "An activity: high-intensity interval training")
        case .running: String(localized: "Running", bundle: .app, locale: .app, comment: "A kind of workout")
        case .jogging: String(localized: "Jogging", bundle: .app, locale: .app, comment: "An activity")
        case .sprinting: String(localized: "Sprinting", bundle: .app, locale: .app, comment: "An activity")
        case .trailRunning: String(localized: "Trail running", bundle: .app, locale: .app, comment: "An activity")
        case .walking: String(localized: "Walking", bundle: .app, locale: .app, comment: "An activity")
        case .cycling: String(localized: "Cycling", bundle: .app, locale: .app)
        case .indoorCycling: String(localized: "Indoor cycling", bundle: .app, locale: .app, comment: "An activity: a stationary bike or spin class")
        case .mountainBiking: String(localized: "Mountain biking", bundle: .app, locale: .app, comment: "An activity")
        case .swimming: String(localized: "Swimming", bundle: .app, locale: .app, comment: "A kind of workout")
        case .openWaterSwimming: String(localized: "Open-water swimming", bundle: .app, locale: .app, comment: "An activity: swimming in a lake or the sea")
        case .rowing: String(localized: "Rowing", bundle: .app, locale: .app, comment: "An activity: rowing a boat on water")
        case .indoorRowing: String(localized: "Indoor rowing", bundle: .app, locale: .app, comment: "An activity: a rowing machine")
        case .elliptical: String(localized: "Elliptical", bundle: .app, locale: .app, comment: "A cardio machine: an elliptical trainer")
        case .stairClimbing: String(localized: "Stair climbing", bundle: .app, locale: .app, comment: "An activity")
        case .jumpRope: String(localized: "Jump rope", bundle: .app, locale: .app, comment: "An activity: skipping with a rope")
        case .tennis: String(localized: "Tennis", bundle: .app, locale: .app, comment: "A sport")
        case .padel: String(localized: "Padel", bundle: .app, locale: .app, comment: "A racket sport")
        case .badminton: String(localized: "Badminton", bundle: .app, locale: .app, comment: "A sport")
        case .tableTennis: String(localized: "Table tennis", bundle: .app, locale: .app, comment: "A sport: ping-pong")
        case .squash: String(localized: "Squash", bundle: .app, locale: .app, comment: "A racket sport")
        case .pickleball: String(localized: "Pickleball", bundle: .app, locale: .app, comment: "A racket sport")
        case .soccer: String(localized: "Soccer", bundle: .app, locale: .app, comment: "A sport: association football")
        case .americanFootball: String(localized: "American football", bundle: .app, locale: .app, comment: "A sport")
        case .basketball: String(localized: "Basketball", bundle: .app, locale: .app, comment: "A sport")
        case .volleyball: String(localized: "Volleyball", bundle: .app, locale: .app, comment: "A sport")
        case .rugby: String(localized: "Rugby", bundle: .app, locale: .app, comment: "A sport")
        case .hockey: String(localized: "Hockey", bundle: .app, locale: .app, comment: "A sport")
        case .baseball: String(localized: "Baseball", bundle: .app, locale: .app, comment: "A sport")
        case .handball: String(localized: "Handball", bundle: .app, locale: .app, comment: "A sport")
        case .cricket: String(localized: "Cricket", bundle: .app, locale: .app, comment: "A sport")
        case .boxing: String(localized: "Boxing", bundle: .app, locale: .app, comment: "A sport")
        case .kickboxing: String(localized: "Kickboxing", bundle: .app, locale: .app, comment: "A sport")
        case .martialArts: String(localized: "Martial arts", bundle: .app, locale: .app, comment: "An activity")
        case .yoga: String(localized: "Yoga", bundle: .app, locale: .app, comment: "An activity")
        case .pilates: String(localized: "Pilates", bundle: .app, locale: .app, comment: "An activity")
        case .stretching: String(localized: "Stretching", bundle: .app, locale: .app, comment: "An activity: stretching and mobility work")
        case .dance: String(localized: "Dance", bundle: .app, locale: .app, comment: "An activity")
        case .hiking: String(localized: "Hiking", bundle: .app, locale: .app, comment: "An activity")
        case .climbing: String(localized: "Climbing", bundle: .app, locale: .app, comment: "An activity: rock or indoor climbing")
        case .skiing: String(localized: "Skiing", bundle: .app, locale: .app, comment: "An activity")
        case .snowboarding: String(localized: "Snowboarding", bundle: .app, locale: .app, comment: "An activity")
        case .surfing: String(localized: "Surfing", bundle: .app, locale: .app, comment: "An activity")
        case .paddling: String(localized: "Paddling", bundle: .app, locale: .app, comment: "An activity: kayaking, canoeing or paddleboarding")
        case .golf: String(localized: "Golf", bundle: .app, locale: .app, comment: "A sport")
        case .other: String(localized: "Other activity", bundle: .app, locale: .app, comment: "An activity not in the list")
        }
    }

    /// Words somebody might search for that the title does not contain, in
    /// English. The translated title is searched as well.
    var searchTerms: [String] {
        switch self {
        case .weightlifting: ["lifting", "weights", "gym", "strength", "bodybuilding", "powerlifting", "resistance"]
        case .calisthenics: ["bodyweight", "street workout", "gymnastics"]
        case .crossfit: ["wod", "functional fitness", "metcon"]
        case .circuitTraining: ["circuit", "bootcamp"]
        case .functionalTraining: ["functional", "conditioning"]
        case .hiit: ["intervals", "tabata", "high intensity"]
        case .running: ["run", "road running", "treadmill"]
        case .jogging: ["jog"]
        case .sprinting: ["sprint", "track", "intervals"]
        case .trailRunning: ["trail", "ultra"]
        case .walking: ["walk", "steps"]
        case .cycling: ["bike", "biking", "road cycling", "ride"]
        case .indoorCycling: ["spin", "spinning", "stationary bike", "peloton"]
        case .mountainBiking: ["mtb", "bike"]
        case .swimming: ["swim", "pool", "laps"]
        case .openWaterSwimming: ["swim", "sea", "lake", "triathlon"]
        case .rowing: ["row", "crew", "boat"]
        case .indoorRowing: ["erg", "rower", "concept2"]
        case .elliptical: ["cross trainer"]
        case .stairClimbing: ["stairmaster", "stair master", "stepper"]
        case .jumpRope: ["skipping", "double unders"]
        case .tennis: ["racket"]
        case .padel: ["racket", "paddle tennis"]
        case .badminton: ["shuttlecock", "racket"]
        case .tableTennis: ["ping pong", "ping-pong"]
        case .squash: ["racket"]
        case .pickleball: ["paddle"]
        case .soccer: ["football", "futbol", "fútbol", "futsal"]
        case .americanFootball: ["football", "nfl", "flag football"]
        case .basketball: ["hoops", "nba"]
        case .volleyball: ["beach volleyball"]
        case .rugby: ["sevens", "league", "union"]
        case .hockey: ["ice hockey", "field hockey"]
        case .baseball: ["softball"]
        case .handball: []
        case .cricket: []
        case .boxing: ["sparring", "bag work"]
        case .kickboxing: ["muay thai"]
        case .martialArts: ["karate", "judo", "bjj", "jiu jitsu", "taekwondo", "mma", "wrestling"]
        case .yoga: ["vinyasa", "hatha"]
        case .pilates: ["reformer"]
        case .stretching: ["mobility", "flexibility", "foam rolling"]
        case .dance: ["zumba", "barre"]
        case .hiking: ["hike", "trekking", "mountain"]
        case .climbing: ["bouldering", "rock climbing"]
        case .skiing: ["ski", "cross-country"]
        case .snowboarding: ["snowboard"]
        case .surfing: ["surf"]
        case .paddling: ["kayak", "canoe", "sup", "paddleboard"]
        case .golf: []
        case .other: []
        }
    }

    /// Activities whose title or search terms contain every word of the
    /// query, ignoring case and accents.
    static func matching(_ query: String) -> [WorkoutActivity] {
        let words = ExerciseSearch.words(query)
        guard !words.isEmpty else { return Array(allCases) }
        return allCases.filter { activity in
            let haystack = ExerciseSearch.folded(([activity.title, activity.rawValue] + activity.searchTerms).joined(separator: " "))
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}

/// How an activity is recorded.
nonisolated enum ActivityProfile: String, Hashable, Sendable {
    /// Exercises, sets, reps and weight.
    case strength
    /// Time and distance; pace or speed follow from the two.
    case distance
    /// Time and how hard it was. A tennis match has no sets and no route.
    case session
}

nonisolated enum ActivityDistanceField: Hashable, Sendable {
    case none
    /// Offered, below everything else, for the few who know it.
    case optional
    /// The main thing measured, asked straight after the time.
    case primary
}

/// How the activity picker groups activities.
nonisolated enum ActivityCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case strength
    case cardio
    case racket
    case team
    case combat
    case mindBody = "mind_body"
    case outdoors
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength: String(localized: "Strength & conditioning", bundle: .app, locale: .app, comment: "A group of activities")
        case .cardio: String(localized: "Cardio & endurance", bundle: .app, locale: .app, comment: "A group of activities")
        case .racket: String(localized: "Racket sports", bundle: .app, locale: .app, comment: "A group of activities")
        case .team: String(localized: "Team sports", bundle: .app, locale: .app, comment: "A group of activities")
        case .combat: String(localized: "Combat sports", bundle: .app, locale: .app, comment: "A group of activities")
        case .mindBody: String(localized: "Mind & body", bundle: .app, locale: .app, comment: "A group of activities: yoga, pilates, stretching")
        case .outdoors: String(localized: "Outdoors", bundle: .app, locale: .app, comment: "A group of activities")
        case .other: String(localized: "Other", bundle: .app, locale: .app, comment: "A cardio machine not in the list")
        }
    }

    var activities: [WorkoutActivity] { WorkoutActivity.allCases.filter { $0.category == self } }
}

/// One activity-specific question. The raw value is the key in the API's
/// `activity_details`.
nonisolated enum ActivityDetailField: String, CaseIterable, Identifiable, Hashable, Sendable {
    case sessionType = "session_type"
    case format
    case style
    case rounds
    case reps
    case intervals
    case routes
    case elevationGain = "elevation_gain_m"
    case poolLength = "pool_length_m"
    case movements

    var id: String { rawValue }

    enum Kind: Hashable, Sendable {
        case choice
        case integer(ClosedRange<Int>)
        case text(maxLength: Int)
    }

    var kind: Kind {
        switch self {
        case .sessionType, .format, .style: .choice
        case .rounds, .intervals, .routes: .integer(0...999)
        case .reps: .integer(0...9999)
        case .elevationGain: .integer(0...10000)
        case .poolLength: .integer(10...100)
        case .movements: .text(maxLength: 500)
        }
    }

    func options(for activity: WorkoutActivity) -> [ActivityChoice] {
        switch self {
        case .sessionType: ActivityChoice.sessionTypes
        case .format: ActivityChoice.crossfitFormats
        case .style: activity.styleOptions
        default: []
        }
    }

    var title: String {
        switch self {
        case .sessionType: String(localized: "Session", bundle: .app, locale: .app, comment: "Asks whether a sport session was a match, training or casual play")
        case .format: String(localized: "Format", bundle: .app, locale: .app, comment: "A CrossFit workout's format, such as AMRAP or For time")
        case .style: String(localized: "Style", bundle: .app, locale: .app, comment: "The style of a yoga, pilates, martial arts or climbing session")
        case .rounds: String(localized: "Rounds", bundle: .app, locale: .app, comment: "How many rounds were completed")
        case .reps: String(localized: "Extra reps", bundle: .app, locale: .app, comment: "Reps completed beyond the last full round of a CrossFit workout")
        case .intervals: String(localized: "Sprints", bundle: .app, locale: .app, comment: "How many sprints were run")
        case .routes: String(localized: "Routes or problems", bundle: .app, locale: .app, comment: "How many climbing routes or boulder problems were climbed")
        case .elevationGain: String(localized: "Elevation gain", bundle: .app, locale: .app)
        case .poolLength: String(localized: "Pool length", bundle: .app, locale: .app)
        case .movements: String(localized: "Movements", bundle: .app, locale: .app, comment: "The exercises in a CrossFit workout, such as thrusters and pull-ups")
        }
    }

    /// The unit printed beside a number, if it has one.
    var unit: String? {
        switch self {
        case .elevationGain, .poolLength: String(localized: "m", bundle: .app, locale: .app, comment: "Abbreviation for metres")
        default: nil
        }
    }
}

/// One answer to a choice question: its wire value and what it says.
nonisolated struct ActivityChoice: Identifiable, Hashable, Sendable {
    let value: String
    let title: String

    var id: String { value }

    static var sessionTypes: [ActivityChoice] {
        [
            ActivityChoice(value: "match", title: String(localized: "Match", bundle: .app, locale: .app, comment: "A competitive game, as opposed to training")),
            ActivityChoice(value: "training", title: String(localized: "Training", bundle: .app, locale: .app, comment: "A practice session, as opposed to a match")),
            ActivityChoice(value: "casual", title: String(localized: "Casual play", bundle: .app, locale: .app, comment: "Playing a sport informally")),
        ]
    }

    static var crossfitFormats: [ActivityChoice] {
        [
            ActivityChoice(value: "amrap", title: String(localized: "AMRAP", bundle: .app, locale: .app, comment: "CrossFit format: as many rounds as possible")),
            ActivityChoice(value: "emom", title: String(localized: "EMOM", bundle: .app, locale: .app, comment: "CrossFit format: every minute on the minute")),
            ActivityChoice(value: "for_time", title: String(localized: "For time", bundle: .app, locale: .app, comment: "CrossFit format: finish the work as fast as possible")),
            ActivityChoice(value: "tabata", title: String(localized: "Tabata", bundle: .app, locale: .app, comment: "CrossFit format: 20 seconds on, 10 off")),
            ActivityChoice(value: "rounds", title: String(localized: "Rounds", bundle: .app, locale: .app, comment: "How many rounds were completed")),
            ActivityChoice(value: "chipper", title: String(localized: "Chipper", bundle: .app, locale: .app, comment: "CrossFit format: a long list of movements done once through")),
            ActivityChoice(value: "other", title: String(localized: "Other", bundle: .app, locale: .app, comment: "A cardio machine not in the list")),
        ]
    }

    static var yogaStyles: [ActivityChoice] {
        [
            ActivityChoice(value: "vinyasa", title: String(localized: "Vinyasa", bundle: .app, locale: .app, comment: "A style of yoga")),
            ActivityChoice(value: "hatha", title: String(localized: "Hatha", bundle: .app, locale: .app, comment: "A style of yoga")),
            ActivityChoice(value: "yin", title: String(localized: "Yin", bundle: .app, locale: .app, comment: "A style of yoga")),
            ActivityChoice(value: "power", title: String(localized: "Power", bundle: .app, locale: .app, comment: "A style of yoga")),
            ActivityChoice(value: "restorative", title: String(localized: "Restorative", bundle: .app, locale: .app, comment: "A style of yoga")),
            ActivityChoice(value: "hot", title: String(localized: "Hot", bundle: .app, locale: .app, comment: "A style of yoga practised in a heated room")),
            ActivityChoice(value: "other", title: String(localized: "Other", bundle: .app, locale: .app, comment: "A cardio machine not in the list")),
        ]
    }

    static var pilatesStyles: [ActivityChoice] {
        [
            ActivityChoice(value: "mat", title: String(localized: "Mat", bundle: .app, locale: .app, comment: "Pilates done on a mat")),
            ActivityChoice(value: "reformer", title: String(localized: "Reformer", bundle: .app, locale: .app, comment: "Pilates done on a reformer machine")),
            ActivityChoice(value: "other", title: String(localized: "Other", bundle: .app, locale: .app, comment: "A cardio machine not in the list")),
        ]
    }

    static var martialArtsStyles: [ActivityChoice] {
        [
            ActivityChoice(value: "karate", title: String(localized: "Karate", bundle: .app, locale: .app, comment: "A martial art")),
            ActivityChoice(value: "taekwondo", title: String(localized: "Taekwondo", bundle: .app, locale: .app, comment: "A martial art")),
            ActivityChoice(value: "judo", title: String(localized: "Judo", bundle: .app, locale: .app, comment: "A martial art")),
            ActivityChoice(value: "jiu_jitsu", title: String(localized: "Jiu-jitsu", bundle: .app, locale: .app, comment: "A martial art")),
            ActivityChoice(value: "muay_thai", title: String(localized: "Muay Thai", bundle: .app, locale: .app, comment: "A martial art")),
            ActivityChoice(value: "kung_fu", title: String(localized: "Kung fu", bundle: .app, locale: .app, comment: "A martial art")),
            ActivityChoice(value: "wrestling", title: String(localized: "Wrestling", bundle: .app, locale: .app, comment: "A combat sport")),
            ActivityChoice(value: "mma", title: String(localized: "MMA", bundle: .app, locale: .app, comment: "Mixed martial arts")),
            ActivityChoice(value: "other", title: String(localized: "Other", bundle: .app, locale: .app, comment: "A cardio machine not in the list")),
        ]
    }

    static var climbingStyles: [ActivityChoice] {
        [
            ActivityChoice(value: "bouldering", title: String(localized: "Bouldering", bundle: .app, locale: .app, comment: "A style of climbing")),
            ActivityChoice(value: "top_rope", title: String(localized: "Top rope", bundle: .app, locale: .app, comment: "A style of climbing")),
            ActivityChoice(value: "lead", title: String(localized: "Lead", bundle: .app, locale: .app, comment: "A style of climbing")),
            ActivityChoice(value: "other", title: String(localized: "Other", bundle: .app, locale: .app, comment: "A cardio machine not in the list")),
        ]
    }
}

/// The activity-specific answers of one session, as the API's
/// `activity_details` object: a whole number or a short text per key.
nonisolated struct ActivityDetails: Hashable, Codable, Sendable {
    enum Value: Hashable, Codable, Sendable {
        case integer(Int)
        case text(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let integer = try? container.decode(Int.self) {
                self = .integer(integer)
            } else {
                self = .text(try container.decode(String.self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .integer(let value): try container.encode(value)
            case .text(let value): try container.encode(value)
            }
        }
    }

    private(set) var values: [String: Value] = [:]

    init(values: [String: Value] = [:]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: Value].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    var isEmpty: Bool { values.isEmpty }

    subscript(field: ActivityDetailField) -> Value? {
        get { values[field.rawValue] }
        set { values[field.rawValue] = newValue }
    }

    func integer(_ field: ActivityDetailField) -> Int? {
        if case .integer(let value) = values[field.rawValue] { return value }
        return nil
    }

    func text(_ field: ActivityDetailField) -> String? {
        if case .text(let value) = values[field.rawValue] { return value }
        return nil
    }

    /// Only what this activity asks about, each within its limits, and with
    /// empty answers dropped. Switching from yoga to tennis must not carry a
    /// yoga style along with it, and a field cleared must not be sent as "".
    func sanitized(for activity: WorkoutActivity) -> ActivityDetails {
        var result = ActivityDetails()
        for field in activity.detailFields {
            guard let value = values[field.rawValue] else { continue }
            switch (field.kind, value) {
            case (.integer(let range), .integer(let number)) where range.contains(number):
                result[field] = value
            case (.choice, .text(let choice))
                where field.options(for: activity).contains(where: { $0.value == choice }):
                result[field] = value
            case (.text(let maxLength), .text(let text)):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result[field] = .text(String(trimmed.prefix(maxLength))) }
            default:
                continue
            }
        }
        return result
    }

    /// "Match · 3 rounds", for a history row.
    func summary(for activity: WorkoutActivity) -> [String] {
        activity.detailFields.compactMap { field in
            switch values[field.rawValue] {
            case .text(let value)?:
                if field == .movements { return value }
                return field.options(for: activity).first { $0.value == value }?.title
            case .integer(let value)?:
                switch field {
                case .rounds: return String(localized: "^[\(value) round](inflect: true)", bundle: .app, locale: .app)
                case .reps: return String(localized: "+\(value) reps", bundle: .app, locale: .app, comment: "Extra reps beyond the last full round")
                case .intervals: return String(localized: "^[\(value) sprint](inflect: true)", bundle: .app, locale: .app)
                case .routes: return String(localized: "^[\(value) route](inflect: true)", bundle: .app, locale: .app, comment: "Climbing routes or boulder problems")
                case .elevationGain: return String(localized: "\(value) m climbed", bundle: .app, locale: .app, comment: "Elevation gained; m is the abbreviation for metres")
                case .poolLength: return String(localized: "\(value) m pool", bundle: .app, locale: .app, comment: "The length of a swimming pool; m is the abbreviation for metres")
                default: return nil
                }
            case nil:
                return nil
            }
        }
    }
}

/// How hard a session felt, on the 0-100 scale the effort chart draws.
///
/// The person's own judgement, never a measurement. The five bands are the
/// chart's five columns; the words are Rytivo's own, written for the "talk
/// test" people already know rather than borrowed from a published scale.
nonisolated enum EffortLevel: Int, CaseIterable, Identifiable, Hashable, Sendable {
    case veryLight
    case light
    case moderate
    case hard
    case allOut

    var id: Int { rawValue }

    /// The band a score falls in. 20 is the top of Very light rather than the
    /// bottom of Light, so each column holds the values drawn inside it.
    init(score: Int) {
        let clamped = min(max(score, 0), 100)
        self = EffortLevel(rawValue: clamped == 0 ? 0 : min((clamped - 1) / 20, 4)) ?? .veryLight
    }

    var range: ClosedRange<Int> { (rawValue * 20)...(rawValue * 20 + 20) }

    var title: String {
        switch self {
        case .veryLight: String(localized: "Very easy", bundle: .app, locale: .app, comment: "Effort level, 0 to 20 of 100")
        case .light: String(localized: "Easy", bundle: .app, locale: .app, comment: "Effort level, 20 to 40 of 100")
        case .moderate: String(localized: "Moderate", bundle: .app, locale: .app, comment: "Effort level, 40 to 60 of 100")
        case .hard: String(localized: "Hard", bundle: .app, locale: .app, comment: "Effort level, 60 to 80 of 100")
        case .allOut: String(localized: "All out", bundle: .app, locale: .app, comment: "Effort level, 80 to 100 of 100: as hard as possible")
        }
    }

    var detail: String {
        switch self {
        case .veryLight: String(localized: "Easy movement. You could chat the whole time.", bundle: .app, locale: .app)
        case .light: String(localized: "Comfortable. Breathing a little harder.", bundle: .app, locale: .app)
        case .moderate: String(localized: "Working. Talking takes some effort.", bundle: .app, locale: .app)
        case .hard: String(localized: "Challenging. Only a few words at a time.", bundle: .app, locale: .app)
        case .allOut: String(localized: "At or near your limit. Hard to keep going.", bundle: .app, locale: .app)
        }
    }
}
