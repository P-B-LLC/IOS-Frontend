//
//  ProfileAPIRepository.swift
//  IOS Frontend
//
//  OAS-generated profile, photo, and gym operations.
//

import Foundation
import RepbaseAPI

/// Converts between what the profile screens show and what the API stores.
///
/// The app talks in feet, inches and pounds because that is what the user
/// types; the server stores centimetres and kilograms because that is what
/// every other measurement in Repbase is in. The conversion lives here rather
/// than in a view so both directions round-trip through one definition.
nonisolated enum ProfileUnits {
    static let centimetresPerInch = 2.54
    static let kilogramsPerPound = 0.45359237

    static func centimetres(feet: Int, inches: Int) -> Int? {
        let total = feet * 12 + inches
        guard total > 0 else { return nil }
        return Int((Double(total) * centimetresPerInch).rounded())
    }

    static func feetAndInches(centimetres: Int?) -> (feet: Int, inches: Int) {
        guard let centimetres, centimetres > 0 else { return (0, 0) }
        let totalInches = Int((Double(centimetres) / centimetresPerInch).rounded())
        return (totalInches / 12, totalInches % 12)
    }

    /// Kilograms as the decimal string the API expects. Decimal, not Double:
    /// the contract carries these as strings and rounding through a binary
    /// float is what makes 82.5 arrive as 82.499999.
    static func kilogramsString(pounds: Int) -> String? {
        guard pounds > 0 else { return nil }
        let kilograms = Decimal(pounds) * Decimal(string: "0.45359237")!
        return Self.rounded(kilograms)
    }

    static func pounds(kilogramsString: String?) -> Int {
        guard let kilogramsString,
              let kilograms = Decimal(string: kilogramsString) else { return 0 }
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

    private static func rounded(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value)
            .rounding(accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 2,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            ))
            .stringValue
    }
}

/// What the server holds about the signed-in user.
nonisolated struct RemoteProfile: Equatable, Sendable {
    var id: Int
    var username: String
    var firstName: String
    var lastName: String
    var bio: String
    var photoURL: String?
    var heightCentimetres: Int?
    var weightKilograms: String?
    var targetWeightKilograms: String?
    var showsHeight: Bool
    var showsWeight: Bool
    var showsTargetWeight: Bool
    var disciplines: [String]
    var gymID: Int?
    var gymName: String?
    var gymCity: String?
    /// The IANA zone the server files this person's days under. Not shown
    /// anywhere; the app keeps it in step with the phone's own zone.
    var timeZone: String
    /// Answered questions. Empty from `/me/`, which does not carry them;
    /// filled in when this is somebody else's public profile.
    var prompts: [ProfilePromptAnswer] = []
    /// Outbound accounts, on both responses. Defaulted to empty so a profile
    /// built without them is a profile with none, never a nil to unwrap.
    var socialLinks: [ProfileSocialLink] = []
}

/// A gym as the server knows it, with the integer identity the API uses.
nonisolated struct RemoteGym: Identifiable, Equatable, Sendable {
    let id: Int
    var name: String
    var city: String
    var country: String
    var memberCount: Int
}

actor ProfileAPIRepository {
    private let configuration: APIConfiguration
    private let client: Client

    init(configuration: APIConfiguration, token: String) throws {
        self.configuration = configuration
        client = try RepbaseAPIClientFactory.makeAuthenticated(
            serverURL: configuration.serverURL,
            token: token,
            allowInsecureLocalhost: configuration.allowsInsecureLocalhost
        )
    }

    // MARK: - The profile

    func profile() async throws -> RemoteProfile {
        let output = try await client.meRetrieve()
        switch output {
        case .ok(let response):
            return Self.profile(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Sends only what the profile screens own.
    ///
    /// Email and birthdate are deliberately absent: nothing in this flow edits
    /// them, and sending them back unchanged would overwrite anything altered
    /// elsewhere in the meantime.
    @discardableResult
    func save(_ profile: RemoteProfile) async throws -> RemoteProfile {
        let output = try await client.mePartialUpdate(
            body: .json(
                Components.Schemas.PatchedRepbaseUserRequest(
                    username: profile.username,
                    firstName: profile.firstName,
                    lastName: profile.lastName,
                    bio: profile.bio,
                    disciplines: profile.disciplines.compactMap {
                        Components.Schemas.DisciplinesEnum(rawValue: $0)
                    },
                    gym: profile.gymID,
                    showsHeight: profile.showsHeight,
                    showsWeight: profile.showsWeight,
                    showsTargetWeight: profile.showsTargetWeight
                )
            )
        )
        switch output {
        case .ok(let response):
            return Self.profile(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Measurements are sent separately so a nil clears rather than skips.
    @discardableResult
    func saveMeasurements(
        heightCentimetres: Int?,
        weightKilograms: String?,
        targetWeightKilograms: String?
    ) async throws -> RemoteProfile {
        let output = try await client.mePartialUpdate(
            body: .json(
                Components.Schemas.PatchedRepbaseUserRequest(
                    heightCm: heightCentimetres.map(Int64.init),
                    weightKg: weightKilograms,
                    targetWeightKg: targetWeightKilograms
                )
            )
        )
        switch output {
        case .ok(let response):
            return Self.profile(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - The photo

    @discardableResult
    func uploadPhoto(_ data: Data, contentType: String) async throws -> RemoteProfile {
        guard let type = Components.Schemas.ContentTypeEnum(rawValue: contentType) else {
            throw APIServiceError.malformedResponse
        }

        let output = try await client.mePhotoUpdate(
            body: .json(
                Components.Schemas.ProfilePhotoUploadRequest(
                    contentType: type,
                    imageBase64: data.base64EncodedString()
                )
            )
        )
        switch output {
        case .ok(let response):
            return Self.profile(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    @discardableResult
    func removePhoto() async throws -> RemoteProfile {
        let output = try await client.mePhotoDestroy()
        switch output {
        case .ok(let response):
            return Self.profile(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Gyms

    /// Gyms matching what the user typed. Searching before creating is what
    /// keeps one gym from being listed six ways.
    /// Somebody else's profile, as the public is allowed to see it.
    ///
    /// A different shape from `/me/`: measurements arrive already withheld by
    /// the server according to their three switches, and the answered
    /// questions ride along, so a visited profile costs one request rather
    /// than three.
    func publicProfile(userID: Int) async throws -> RemoteProfile {
        let output = try await client.usersRetrieve(path: .init(id: userID))
        switch output {
        case .ok(let response):
            let payload = try response.body.json
            return RemoteProfile(
                id: payload.id,
                username: payload.username,
                firstName: payload.firstName,
                lastName: payload.lastName,
                bio: payload.bio ?? "",
                photoURL: payload.profilePhotoUrl,
                heightCentimetres: payload.heightCm,
                weightKilograms: payload.weightKg,
                targetWeightKilograms: payload.targetWeightKg,
                showsHeight: payload.showsHeight ?? false,
                showsWeight: payload.showsWeight ?? false,
                showsTargetWeight: payload.showsTargetWeight ?? false,
                // Already strings here, unlike on /me/ where the contract
                // gives a closed enum.
                disciplines: payload.disciplines,
                gymID: payload.gym,
                gymName: payload.gymName,
                gymCity: payload.gymCity,
                // Not public, and not needed: the app only ever corrects its
                // own. Somebody else's zone is a hint about where they live.
                timeZone: "UTC",
                prompts: payload.prompts.map {
                    ProfilePromptAnswer(
                        question: $0.question,
                        questionLabel: $0.questionLabel,
                        answer: $0.answer
                    )
                },
                socialLinks: Self.socialLinks(from: payload.socialLinks)
            )
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Tells the server which zone this phone is in.
    ///
    /// Sent on its own, not folded into a profile save: it is not something
    /// the user edits, and it has to be corrected on a launch where they
    /// changed nothing else -- after a flight, most obviously.
    @discardableResult
    func saveTimeZone(_ identifier: String) async throws -> RemoteProfile {
        let output = try await client.mePartialUpdate(
            body: .json(
                Components.Schemas.PatchedRepbaseUserRequest(timeZone: identifier)
            )
        )
        switch output {
        case .ok(let response):
            return Self.profile(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Social links

    /// Replaces every outbound account with the set given.
    ///
    /// One request rather than one per link, matching `me/prompts/`: the
    /// editor behind this changes them together, and sending the set that
    /// should exist afterwards cannot leave a link behind that its owner has
    /// stopped seeing.
    ///
    /// Each entry may carry a full URL or a bare handle. Which it is, and what
    /// the canonical URL for it should be, is the server's decision -- so what
    /// comes back is what was stored, not what was sent.
    @discardableResult
    func saveSocialLinks(_ links: [ProfileSocialLinkDraft]) async throws -> [ProfileSocialLink] {
        let output = try await client.meSocialLinksUpdate(
            body: .json(
                Components.Schemas.ProfileSocialLinksRequestRequest(
                    socialLinks: links.map {
                        Components.Schemas.ProfileSocialLinkWriteRequest(
                            platform: Components.Schemas.PlatformEnum(
                                rawValue: $0.platform.rawValue
                            ) ?? .website,
                            url: $0.value
                        )
                    }
                )
            )
        )
        switch output {
        case .ok(let response):
            return Self.socialLinks(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Prompts and highlights

    /// The questions the signed-in user has answered.
    func prompts() async throws -> [ProfilePromptAnswer] {
        let output = try await client.mePromptsList()
        switch output {
        case .ok(let response):
            return try response.body.json.map(Self.prompt(from:))
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Replaces every answer with the set given.
    ///
    /// The whole set rather than one at a time, because the screen behind this
    /// edits all three together: sending what should exist afterwards cannot
    /// leave a fourth answer stranded where nobody can see to delete it.
    @discardableResult
    func savePrompts(_ answers: [ProfilePromptAnswer]) async throws -> [ProfilePromptAnswer] {
        let written = answers.compactMap { answer -> Components.Schemas.ProfilePromptWriteRequest? in
            // A question this build cannot name is one it must not send: the
            // request enum is closed, and inventing a value would be refused.
            guard let question = Components.Schemas.QuestionEnum(rawValue: answer.question)
            else { return nil }
            return .init(question: question, answer: answer.answer)
        }

        let output = try await client.mePromptsUpdate(
            body: .json(Components.Schemas.ProfilePromptsRequestRequest(prompts: written))
        )
        switch output {
        case .ok(let response):
            return try response.body.json.map(Self.prompt(from:))
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// The lifts the signed-in user features, each with their best logged set.
    func highlights() async throws -> [HighlightLift] {
        let output = try await client.meHighlightsList()
        switch output {
        case .ok(let response):
            return try response.body.json.map(Self.highlight(from:))
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Somebody else's featured lifts. Its own request rather than part of
    /// their profile, because each highlight costs a look through their set
    /// history and a list of people would pay it per person.
    func highlights(forUser userID: Int) async throws -> [HighlightLift] {
        let output = try await client.usersHighlightsList(path: .init(id: userID))
        switch output {
        case .ok(let response):
            return try response.body.json.map(Self.highlight(from:))
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Replaces the featured lifts.
    ///
    /// A typed weight goes out only when a rep count goes with it: the server
    /// refuses half a set, and sending one would fail the whole save over a
    /// field the user may not have meant to fill in.
    @discardableResult
    func saveHighlights(_ lifts: [HighlightLift]) async throws -> [HighlightLift] {
        let written = lifts.compactMap { entry -> Components.Schemas.ProfileHighlightWriteRequest? in
            guard let lift = Components.Schemas.LiftEnum(rawValue: entry.lift.rawValue)
            else { return nil }
            // Only a typed pair is sent back. A logged figure belongs to the
            // session it came from, and echoing it here would freeze it.
            let manual = entry.source == .manual ? entry : nil
            let weight = manual?.weightKilograms
            let reps = manual?.reps
            return .init(
                lift: lift,
                manualWeightKg: (weight != nil && reps != nil)
                    ? FoodDecimal.string(weight!) : nil,
                manualReps: (weight != nil && reps != nil) ? reps : nil
            )
        }

        let output = try await client.meHighlightsUpdate(
            body: .json(
                Components.Schemas.ProfileHighlightsRequestRequest(highlights: written)
            )
        )
        switch output {
        case .ok(let response):
            return try response.body.json.map(Self.highlight(from:))
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    private static func prompt(
        from payload: Components.Schemas.ProfilePrompt
    ) -> ProfilePromptAnswer {
        ProfilePromptAnswer(
            question: payload.question,
            questionLabel: payload.questionLabel,
            answer: payload.answer
        )
    }

    private static func highlight(
        from payload: Components.Schemas.ProfileHighlight
    ) -> HighlightLift {
        HighlightLift(
            // A lift this build does not know falls back to bench rather than
            // dropping the row: the label comes from the server anyway, so the
            // card still reads correctly.
            lift: FeaturedLift(rawValue: payload.lift) ?? .bench,
            label: payload.liftLabel,
            source: HighlightSource(payload.source),
            weightKilograms: payload.weightKg.flatMap { Decimal(string: $0) },
            reps: payload.reps,
            estimatedOneRepMaxKilograms: payload.estimatedOneRepMaxKg
                .flatMap { Decimal(string: $0) },
            performedAt: payload.performedAt,
            exerciseName: payload.exerciseName
        )
    }

    func searchGyms(_ query: String) async throws -> [RemoteGym] {
        let output = try await client.gymsList(query: .init(search: query))
        switch output {
        case .ok(let response):
            return try response.body.json.results.map(Self.gym(from:))
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    func createGym(name: String, city: String, country: String) async throws -> RemoteGym {
        let output = try await client.gymsCreate(
            body: .json(
                Components.Schemas.GymRequest(name: name, city: city, country: country)
            )
        )
        switch output {
        case .created(let response):
            return Self.gym(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Mapping

    private static func profile(
        from payload: Components.Schemas.RepbaseUser
    ) -> RemoteProfile {
        RemoteProfile(
            id: payload.id,
            username: payload.username,
            firstName: payload.firstName,
            lastName: payload.lastName,
            bio: payload.bio ?? "",
            photoURL: payload.profilePhotoUrl,
            heightCentimetres: payload.heightCm.map(Int.init),
            weightKilograms: payload.weightKg,
            targetWeightKilograms: payload.targetWeightKg,
            showsHeight: payload.showsHeight ?? false,
            showsWeight: payload.showsWeight ?? false,
            showsTargetWeight: payload.showsTargetWeight ?? false,
            disciplines: (payload.disciplines ?? []).map(\.rawValue),
            gymID: payload.gym,
            gymName: payload.gymName,
            gymCity: payload.gymCity,
            timeZone: payload.timeZone ?? "UTC",
            socialLinks: socialLinks(from: payload.socialLinks)
        )
    }

    /// Drops anything that will not make a URL rather than failing the whole
    /// profile over one link. The server stores them already canonical, so a
    /// value that does not parse here means the two ends disagree about what a
    /// URL is -- which is worth losing one icon over, not somebody's profile.
    private static func socialLinks(
        from payload: [Components.Schemas.ProfileSocialLink]
    ) -> [ProfileSocialLink] {
        payload.compactMap { link in
            guard let platform = ProfileSocialLink.Platform(rawValue: link.platform.rawValue),
                  let url = URL(string: link.url) else { return nil }
            return ProfileSocialLink(platform: platform, url: url)
        }
    }

    private static func gym(from payload: Components.Schemas.Gym) -> RemoteGym {
        RemoteGym(
            id: payload.id,
            name: payload.name,
            city: payload.city ?? "",
            country: payload.country ?? "",
            memberCount: payload.memberCount
        )
    }

    // MARK: - Personalization

    /// What this account said it wanted from Repbase.
    ///
    /// Never absent: the server creates the record on first read, so an
    /// account that has not finished the flow answers with the defaults
    /// rather than a 404 the caller would have to treat as a special case.
    func personalization() async throws -> Personalization {
        let output = try await client.mePersonalizationRetrieve()
        switch output {
        case .ok(let response):
            return Self.personalization(from: try response.body.json)
        case .undocumented(let statusCode, let payload):
            throw await RepbaseAPIHTTPError.decode(
                statusCode: statusCode,
                payload: payload
            )
        }
    }

    @discardableResult
    func savePersonalization(_ values: Personalization) async throws -> Personalization {
        let output = try await client.mePersonalizationPartialUpdate(
            body: .json(
                Components.Schemas.PatchedPersonalizationRequest(
                    trainingTypes: values.trainingTypes,
                    weeklyTarget: Int64(values.weeklyTarget),
                    emphasis: values.emphasis
                )
            )
        )
        switch output {
        case .ok(let response):
            return Self.personalization(from: try response.body.json)
        case .undocumented(let statusCode, let payload):
            throw await RepbaseAPIHTTPError.decode(
                statusCode: statusCode,
                payload: payload
            )
        }
    }

    private static func personalization(
        from payload: Components.Schemas.Personalization
    ) -> Personalization {
        Personalization(
            trainingTypes: payload.trainingTypes ?? [],
            weeklyTarget: Int(payload.weeklyTarget ?? 3),
            emphasis: payload.emphasis ?? ""
        )
    }
}

/// The three answers the first-run flow asks for.
///
/// Held as the strings the flow already uses rather than as its private
/// enums, so retiring a choice from the app cannot fail to decode an account
/// that picked it. The flow maps them back to its own cases and ignores
/// anything it no longer offers.
///
/// There were five. The two that are gone were never read: one asked what
/// another question had already asked, and the other was stored against a
/// use that was never built.
nonisolated struct Personalization: Equatable, Sendable {
    var trainingTypes: [String] = []
    var weeklyTarget: Int = 3
    var emphasis: String = ""
}
