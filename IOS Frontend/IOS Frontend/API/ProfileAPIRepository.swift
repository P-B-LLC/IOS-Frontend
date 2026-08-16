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
            gymCity: payload.gymCity
        )
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
}
