//
//  ProfileExpression.swift
//  IOS Frontend
//
//  The two things a profile says beyond its measurements: questions the person
//  chose to answer, and lifts they chose to show.
//

import Foundation

/// One answered question, as the server sends it.
///
/// `questionLabel` is the server's wording, not the app's. A question added
/// after this build shipped still reads correctly, because the text to draw
/// arrives with the answer rather than being looked up in a table here.
nonisolated struct ProfilePromptAnswer: Identifiable, Equatable, Hashable, Codable, Sendable {
    var question: String
    var questionLabel: String
    var answer: String

    var id: String { question }
}

/// The questions this build knows how to offer.
///
/// Only the picker uses this. Answers already given are drawn from the label
/// the server sent, so if the server learns a new question before the app
/// does, the answer still displays properly — it just cannot be chosen here
/// until the app catches up.
nonisolated enum PromptQuestion: String, CaseIterable, Identifiable, Sendable {
    case whyITrain = "why_i_train"
    case currentGoal = "current_goal"
    case favouriteLift = "favourite_lift"
    case hardestPart = "hardest_part"
    case bestAdvice = "best_advice"
    case proudest = "proudest"
    case restDay = "rest_day"
    case preWorkout = "pre_workout"
    case postWorkout = "post_workout"
    case trainingTo = "training_to"
    case oneMoreRep = "one_more_rep"
    case trainingPartner = "training_partner"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .whyITrain: "Why I train"
        case .currentGoal: "What I am working towards"
        case .favouriteLift: "Favourite lift"
        case .hardestPart: "The hardest part for me"
        case .bestAdvice: "Best advice I have been given"
        case .proudest: "Proudest moment in the gym"
        case .restDay: "A rest day looks like"
        case .preWorkout: "What I eat before training"
        case .postWorkout: "What I eat after"
        case .trainingTo: "What I train to"
        case .oneMoreRep: "What gets me one more rep"
        case .trainingPartner: "Looking for a training partner who"
        }
    }

    /// What the field says before anything is typed, to show the shape of an
    /// answer without putting words in anyone's mouth.
    var hint: String {
        switch self {
        case .whyITrain: "So my kids never see me quit"
        case .currentGoal: "A 500 lb deadlift before June"
        case .favouriteLift: "Front squat, and it is not close"
        case .hardestPart: "Getting there on a Monday"
        case .bestAdvice: "Leave one in the tank"
        case .proudest: "First unassisted pull-up at 41"
        case .restDay: "A long walk and too much coffee"
        case .preWorkout: "Rice and whatever is left over"
        case .postWorkout: "Eggs, always eggs"
        case .trainingTo: "Old hardcore and podcasts"
        case .oneMoreRep: "Someone counting out loud"
        case .trainingPartner: "Turns up at six and does not chat"
        }
    }
}

/// Which of the three lifts a highlight is for.
///
/// Three and only three: the point of a featured lift is comparison, and a
/// number only compares against the same movement. "Incline Chest" next to
/// somebody else's "Lateral Raises" tells a reader nothing.
nonisolated enum FeaturedLift: String, CaseIterable, Identifiable, Codable, Sendable {
    case bench
    case squat
    case deadlift

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bench: "Bench Press"
        case .squat: "Squat"
        case .deadlift: "Deadlift"
        }
    }

    var symbol: String {
        switch self {
        case .bench: "figure.strengthtraining.traditional"
        case .squat: "figure.strengthtraining.functional"
        case .deadlift: "figure.strengthtraining.traditional"
        }
    }
}

/// Where a featured lift's number came from.
///
/// Kept as its own value rather than inferred from which fields are filled in,
/// because the difference matters to a reader: a set the server read out of a
/// finished session is evidence, and a number somebody typed is a claim.
nonisolated enum HighlightSource: String, Codable, Sendable {
    case logged
    case manual
    case none

    init(_ raw: String) {
        self = HighlightSource(rawValue: raw) ?? .none
    }
}

/// A lift someone chose to show, and what they have to show for it.
nonisolated struct HighlightLift: Identifiable, Equatable, Hashable, Codable, Sendable {
    var lift: FeaturedLift
    var label: String
    var source: HighlightSource
    var weightKilograms: Decimal?
    var reps: Int?
    var estimatedOneRepMaxKilograms: Decimal?
    var performedAt: Date?
    /// What the set was logged under, for a logged one. Nil otherwise.
    var exerciseName: String?

    var id: String { lift.rawValue }

    /// Pounds, rounded, because every other weight the app shows is in pounds.
    static func pounds(_ kilograms: Decimal?) -> Int? {
        guard let kilograms else { return nil }
        let pounds = kilograms / Decimal(string: "0.45359237")!
        return Int(truncating: NSDecimalNumber(decimal: pounds).rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            )
        ))
    }

    static func kilograms(fromPounds pounds: Int) -> Decimal {
        Decimal(pounds) * Decimal(string: "0.45359237")!
    }

    var displayPounds: Int? { Self.pounds(weightKilograms) }
    var estimatedOneRepMaxPounds: Int? { Self.pounds(estimatedOneRepMaxKilograms) }

    /// "265 lb × 3", or nil when there is nothing to show.
    var setSummary: String? {
        guard let pounds = displayPounds, let reps else { return nil }
        return "\(pounds) lb × \(reps)"
    }
}
