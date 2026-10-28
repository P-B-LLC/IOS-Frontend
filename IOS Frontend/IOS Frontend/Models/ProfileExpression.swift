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

    /// The question in the app's language.
    ///
    /// The server's label is English. A question this build knows is named
    /// from its own table so it follows the language chosen in Settings; one
    /// it does not still reads correctly from the server's wording.
    var displayLabel: String {
        PromptQuestion(rawValue: question)?.label ?? questionLabel
    }
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

    /// The section heading. The raw value stays English as the identifier.
    var title: String {
        switch self {
        case .why: String(localized: "Why you train", bundle: .app, locale: .app)
        case .gym: String(localized: "In the gym", bundle: .app, locale: .app)
        case .food: String(localized: "Food", bundle: .app, locale: .app, comment: "A section of profile questions about food")
        case .life: String(localized: "Rest of your life", bundle: .app, locale: .app)
        case .together: String(localized: "Training together", bundle: .app, locale: .app)
        }
    }

    var blurb: String {
        switch self {
        case .why: String(localized: "What got you here, and what you are chasing", bundle: .app, locale: .app)
        case .gym: String(localized: "How you train, and what you have learned", bundle: .app, locale: .app)
        case .food: String(localized: "What you eat, and what is worth it", bundle: .app, locale: .app)
        case .life: String(localized: "The other six days", bundle: .app, locale: .app)
        case .together: String(localized: "For anyone thinking of training with you", bundle: .app, locale: .app)
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
        case .whyITrain: String(localized: "Why I train", bundle: .app, locale: .app)
        case .currentGoal: String(localized: "What I am working towards", bundle: .app, locale: .app)
        case .proudest: String(localized: "Proudest moment in the gym", bundle: .app, locale: .app)
        case .hardestPart: String(localized: "The hardest part for me", bundle: .app, locale: .app)
        case .startedBecause: String(localized: "I started training because", bundle: .app, locale: .app)
        case .trainingChanged: String(localized: "Training changed this about me", bundle: .app, locale: .app)
        case .favouriteLift: String(localized: "Favourite lift", bundle: .app, locale: .app)
        case .skippedLift: String(localized: "The lift I skip if I can", bundle: .app, locale: .app)
        case .oneMoreRep: String(localized: "What gets me one more rep", bundle: .app, locale: .app)
        case .bestAdvice: String(localized: "Best advice I have been given", bundle: .app, locale: .app)
        case .trainingTo: String(localized: "What I train to", bundle: .app, locale: .app)
        case .gymPetPeeve: String(localized: "My gym pet peeve", bundle: .app, locale: .app)
        case .warmUp: String(localized: "My warm-up is", bundle: .app, locale: .app)
        case .preWorkout: String(localized: "What I eat before training", bundle: .app, locale: .app)
        case .postWorkout: String(localized: "What I eat after", bundle: .app, locale: .app)
        case .worthIt: String(localized: "Worth every calorie", bundle: .app, locale: .app)
        case .onRepeat: String(localized: "The meal I make on repeat", bundle: .app, locale: .app)
        case .restDay: String(localized: "A rest day looks like", bundle: .app, locale: .app)
        case .outsideGym: String(localized: "Outside the gym you will find me", bundle: .app, locale: .app)
        case .recovery: String(localized: "How I actually recover", bundle: .app, locale: .app)
        case .sunday: String(localized: "My Sunday in three words", bundle: .app, locale: .app)
        case .trainingPartner: String(localized: "Looking for a training partner who", bundle: .app, locale: .app)
        case .spotMe: String(localized: "Ask me to spot you if", bundle: .app, locale: .app)
        case .partnerNever: String(localized: "A training partner should never", bundle: .app, locale: .app)
        }
    }

    /// What the field says before anything is typed, to show the shape of an
    /// answer without putting words in anyone's mouth.
    var hint: String {
        switch self {
        case .whyITrain: String(localized: "So my kids never see me quit", bundle: .app, locale: .app)
        case .currentGoal: String(localized: "A 500 lb deadlift before June", bundle: .app, locale: .app)
        case .proudest: String(localized: "First unassisted pull-up at 41", bundle: .app, locale: .app)
        case .hardestPart: String(localized: "Getting there on a Monday", bundle: .app, locale: .app)
        case .startedBecause: String(localized: "A doctor said the word borderline", bundle: .app, locale: .app)
        case .trainingChanged: String(localized: "I stopped apologising for taking up space", bundle: .app, locale: .app)
        case .favouriteLift: String(localized: "Front squat, and it is not close", bundle: .app, locale: .app)
        case .skippedLift: String(localized: "Walking lunges, every single time", bundle: .app, locale: .app)
        case .oneMoreRep: String(localized: "Someone counting out loud", bundle: .app, locale: .app)
        case .bestAdvice: String(localized: "Leave one in the tank", bundle: .app, locale: .app)
        case .trainingTo: String(localized: "Old hardcore and podcasts", bundle: .app, locale: .app)
        case .gymPetPeeve: String(localized: "Curling in the squat rack, obviously", bundle: .app, locale: .app)
        case .warmUp: String(localized: "Ten minutes I pretend not to need", bundle: .app, locale: .app)
        case .preWorkout: String(localized: "Rice and whatever is left over", bundle: .app, locale: .app)
        case .postWorkout: String(localized: "Eggs, always eggs", bundle: .app, locale: .app)
        case .worthIt: String(localized: "My mother's roast potatoes", bundle: .app, locale: .app)
        case .onRepeat: String(localized: "Chicken, rice, too much hot sauce", bundle: .app, locale: .app)
        case .restDay: String(localized: "A long walk and too much coffee", bundle: .app, locale: .app)
        case .outsideGym: String(localized: "Out on a bike, or asleep", bundle: .app, locale: .app)
        case .recovery: String(localized: "Badly. I am working on it", bundle: .app, locale: .app)
        case .sunday: String(localized: "Slow, loud, full", bundle: .app, locale: .app)
        case .trainingPartner: String(localized: "Turns up at six and does not chat", bundle: .app, locale: .app)
        case .spotMe: String(localized: "You actually want the spot, not a lift-off", bundle: .app, locale: .app)
        case .partnerNever: String(localized: "Count a rep I did not earn", bundle: .app, locale: .app)
        }
    }

    /// Whether this question matches what somebody typed into the search box.
    func matches(_ search: String) -> Bool {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        return label.lowercased().contains(needle)
            || category.title.lowercased().contains(needle)
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
        case .bench: String(localized: "Bench Press", bundle: .app, locale: .app)
        case .squat: String(localized: "Squat", bundle: .app, locale: .app, comment: "The barbell lift")
        case .deadlift: String(localized: "Deadlift", bundle: .app, locale: .app)
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

    /// The lift's name in the app's language.
    ///
    /// `label` is the server's English wording, so the lifts this build knows
    /// are named from `FeaturedLift` instead. One it does not know arrives as
    /// bench (see the repository) under a label that is not bench's, and keeps
    /// the server's wording so the card still reads correctly.
    var displayLabel: String {
        lift == .bench && label != "Bench Press" ? label : lift.label
    }

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
        return String(localized: "\(pounds) lb × \(reps)", bundle: .app, locale: .app, comment: "A set: weight in pounds × repetitions")
    }
}
