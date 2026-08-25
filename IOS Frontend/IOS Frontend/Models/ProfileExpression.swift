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
nonisolated struct ProfilePromptAnswer: Identifiable, Equatable, Hashable, Sendable {
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

/// A lift someone chose to feature, with the best set behind it.
///
/// Every figure is optional together. Choosing a lift before training it is
/// the ordinary first state of a highlight, and the card says so rather than
/// printing a zero that reads like a failed attempt.
nonisolated struct HighlightLift: Identifiable, Equatable, Hashable, Sendable {
    let exerciseID: Int
    var exerciseName: String
    var bestWeightKilograms: Decimal?
    var bestReps: Int?
    var estimatedOneRepMaxKilograms: Decimal?
    var performedAt: Date?

    var id: Int { exerciseID }

    var hasLoggedSet: Bool { bestWeightKilograms != nil && bestReps != nil }

    /// Pounds, rounded, because every other weight the app shows is in pounds.
    private static func pounds(_ kilograms: Decimal?) -> Int? {
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

    var bestPounds: Int? { Self.pounds(bestWeightKilograms) }
    var estimatedOneRepMaxPounds: Int? { Self.pounds(estimatedOneRepMaxKilograms) }

    /// "225 lb × 5", or nil when nothing has been logged.
    var bestSetSummary: String? {
        guard let pounds = bestPounds, let reps = bestReps else { return nil }
        return "\(pounds) lb × \(reps)"
    }
}
