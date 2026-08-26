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

/// What a question is about, so the library reads as sections rather than a
/// list of twenty-four.
nonisolated enum PromptCategory: String, CaseIterable, Identifiable, Sendable {
    case why = "Why you train"
    case gym = "In the gym"
    case food = "Food"
    case life = "Rest of your life"
    case together = "Training together"

    var id: String { rawValue }

    var blurb: String {
        switch self {
        case .why: "What got you here, and what you are chasing"
        case .gym: "How you train, and what you have learned"
        case .food: "What you eat, and what is worth it"
        case .life: "The other six days"
        case .together: "For anyone thinking of training with you"
        }
    }
}

/// The questions this build knows how to offer.
///
/// Only the library uses this. Answers already given are drawn from the label
/// the server sent, so if the server learns a new question before the app
/// does, the answer still displays properly — it just cannot be chosen here
/// until the app catches up.
nonisolated enum PromptQuestion: String, CaseIterable, Identifiable, Sendable {
    case whyITrain = "why_i_train"
    case currentGoal = "current_goal"
    case proudest = "proudest"
    case hardestPart = "hardest_part"
    case startedBecause = "started_because"
    case trainingChanged = "training_changed"

    case favouriteLift = "favourite_lift"
    case skippedLift = "skipped_lift"
    case oneMoreRep = "one_more_rep"
    case bestAdvice = "best_advice"
    case trainingTo = "training_to"
    case gymPetPeeve = "gym_pet_peeve"
    case warmUp = "warm_up"

    case preWorkout = "pre_workout"
    case postWorkout = "post_workout"
    case worthIt = "worth_it"
    case onRepeat = "on_repeat"

    case restDay = "rest_day"
    case outsideGym = "outside_gym"
    case recovery = "recovery"
    case sunday = "sunday"

    case trainingPartner = "training_partner"
    case spotMe = "spot_me"
    case partnerNever = "partner_never"

    var id: String { rawValue }

    var category: PromptCategory {
        switch self {
        case .whyITrain, .currentGoal, .proudest, .hardestPart,
             .startedBecause, .trainingChanged:
            .why
        case .favouriteLift, .skippedLift, .oneMoreRep, .bestAdvice,
             .trainingTo, .gymPetPeeve, .warmUp:
            .gym
        case .preWorkout, .postWorkout, .worthIt, .onRepeat:
            .food
        case .restDay, .outsideGym, .recovery, .sunday:
            .life
        case .trainingPartner, .spotMe, .partnerNever:
            .together
        }
    }

    var label: String {
        switch self {
        case .whyITrain: "Why I train"
        case .currentGoal: "What I am working towards"
        case .proudest: "Proudest moment in the gym"
        case .hardestPart: "The hardest part for me"
        case .startedBecause: "I started training because"
        case .trainingChanged: "Training changed this about me"
        case .favouriteLift: "Favourite lift"
        case .skippedLift: "The lift I skip if I can"
        case .oneMoreRep: "What gets me one more rep"
        case .bestAdvice: "Best advice I have been given"
        case .trainingTo: "What I train to"
        case .gymPetPeeve: "My gym pet peeve"
        case .warmUp: "My warm-up is"
        case .preWorkout: "What I eat before training"
        case .postWorkout: "What I eat after"
        case .worthIt: "Worth every calorie"
        case .onRepeat: "The meal I make on repeat"
        case .restDay: "A rest day looks like"
        case .outsideGym: "Outside the gym you will find me"
        case .recovery: "How I actually recover"
        case .sunday: "My Sunday in three words"
        case .trainingPartner: "Looking for a training partner who"
        case .spotMe: "Ask me to spot you if"
        case .partnerNever: "A training partner should never"
        }
    }

    /// What the field says before anything is typed, to show the shape of an
    /// answer without putting words in anyone's mouth.
    var hint: String {
        switch self {
        case .whyITrain: "So my kids never see me quit"
        case .currentGoal: "A 500 lb deadlift before June"
        case .proudest: "First unassisted pull-up at 41"
        case .hardestPart: "Getting there on a Monday"
        case .startedBecause: "A doctor said the word borderline"
        case .trainingChanged: "I stopped apologising for taking up space"
        case .favouriteLift: "Front squat, and it is not close"
        case .skippedLift: "Walking lunges, every single time"
        case .oneMoreRep: "Someone counting out loud"
        case .bestAdvice: "Leave one in the tank"
        case .trainingTo: "Old hardcore and podcasts"
        case .gymPetPeeve: "Curling in the squat rack, obviously"
        case .warmUp: "Ten minutes I pretend not to need"
        case .preWorkout: "Rice and whatever is left over"
        case .postWorkout: "Eggs, always eggs"
        case .worthIt: "My mother's roast potatoes"
        case .onRepeat: "Chicken, rice, too much hot sauce"
        case .restDay: "A long walk and too much coffee"
        case .outsideGym: "Out on a bike, or asleep"
        case .recovery: "Badly. I am working on it"
        case .sunday: "Slow, loud, full"
        case .trainingPartner: "Turns up at six and does not chat"
        case .spotMe: "You actually want the spot, not a lift-off"
        case .partnerNever: "Count a rep I did not earn"
        }
    }

    /// Whether this question matches what somebody typed into the search box.
    func matches(_ search: String) -> Bool {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        return label.lowercased().contains(needle)
            || category.rawValue.lowercased().contains(needle)
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
