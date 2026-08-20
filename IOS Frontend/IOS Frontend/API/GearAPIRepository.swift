//
//  GearAPIRepository.swift
//  IOS Frontend
//
//  OAS-generated gear operations.
//
//  Mileage is never added up here. It is a property of every session a shoe or
//  bike was used for, and only the server has them all; the device asks and
//  draws the answer.
//

import Foundation
import RepbaseAPI

actor GearAPIRepository {
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

    // MARK: - Reading

    /// Every piece of gear, retired ones included only when asked for.
    func gear(includingRetired: Bool = false) async throws -> [Gear] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [Gear] = []
        repeat {
            let output = try await client.gearList(
                query: .init(includeRetired: includingRetired, page: page)
            )
            let response: Components.Schemas.PaginatedGearList
            switch output {
            case .ok(let success):
                response = try success.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            values.append(contentsOf: response.results.compactMap(Self.gear(from:)))
            page = try nextPage(response.next, visited: &visited)
        } while page != nil
        return values
    }

    // MARK: - Writing

    @discardableResult
    func create(_ draft: GearDraft) async throws -> Gear {
        let output = try await client.gearCreate(
            body: .json(
                Components.Schemas.GearRequest(
                    kind: Self.kindPayload(draft.kind),
                    name: draft.name,
                    brand: draft.brand,
                    notes: draft.notes,
                    initialDistanceKm: Self.decimalString(draft.initialDistanceKilometers),
                    retireAtKm: draft.retireAtKilometers.map(Self.decimalString),
                    isDefault: draft.isDefault
                )
            )
        )
        switch output {
        case .created(let response):
            guard let gear = Self.gear(from: try response.body.json) else {
                throw APIServiceError.malformedResponse
            }
            return gear
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    @discardableResult
    func update(_ gear: Gear) async throws -> Gear {
        let output = try await client.gearPartialUpdate(
            path: .init(id: gear.id),
            body: .json(
                Components.Schemas.PatchedGearRequest(
                    name: gear.name,
                    brand: gear.brand,
                    notes: gear.notes,
                    initialDistanceKm: Self.decimalString(gear.initialDistanceKilometers),
                    retireAtKm: gear.retireAtKilometers.map(Self.decimalString),
                    isDefault: gear.isDefault,
                    retiredAt: gear.retiredAt
                )
            )
        )
        switch output {
        case .ok(let response):
            guard let updated = Self.gear(from: try response.body.json) else {
                throw APIServiceError.malformedResponse
            }
            return updated
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Retires or un-retires. Nothing is deleted: what was worn is the record,
    /// and a shoe's mileage is the only evidence of how long its kind lasts.
    @discardableResult
    func setRetired(_ gear: Gear, retired: Bool) async throws -> Gear {
        var updated = gear
        updated.retiredAt = retired ? Date() : nil
        // A retired shoe cannot also be the one preselected for new runs.
        if retired { updated.isDefault = false }
        return try await update(updated)
    }

    func delete(_ gear: Gear) async throws {
        let output = try await client.gearDestroy(path: .init(id: gear.id))
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Attaches gear to a finished or running session, or clears it with nil.
    func assign(gearID: Int?, toSession sessionID: Int) async throws {
        let output = try await client.sessionsPartialUpdate(
            path: .init(id: sessionID),
            body: .json(
                Components.Schemas.PatchedWorkoutSessionRequest(gear: gearID)
            )
        )
        switch output {
        case .ok:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Mapping

    private nonisolated static func gear(
        from payload: Components.Schemas.Gear
    ) -> Gear? {
        guard let kind = GearKind(rawValue: payload.kind.rawValue) else {
            // A kind this build does not know about is left alone rather than
            // guessed at; drawing a bike as a shoe would be worse than absent.
            return nil
        }

        return Gear(
            id: payload.id,
            kind: kind,
            name: payload.name,
            brand: payload.brand ?? "",
            notes: payload.notes ?? "",
            totalDistanceKilometers: payload.totalDistanceKm,
            initialDistanceKilometers: payload.initialDistanceKm
                .flatMap(Double.init) ?? 0,
            retireAtKilometers: payload.retireAtKm.flatMap(Double.init),
            isDefault: payload.isDefault ?? false,
            retiredAt: payload.retiredAt,
            sessionCount: payload.sessionCount,
            lastUsedAt: payload.lastUsedAt
        )
    }

    private nonisolated static func kindPayload(
        _ kind: GearKind
    ) -> Components.Schemas.GearKindEnum {
        switch kind {
        case .shoe: .shoe
        case .bike: .bike
        }
    }

    /// Decimals cross as strings, which is how the server sends and expects
    /// them: a decimal put through a JSON number gives away the exactness the
    /// type exists to keep.
    private nonisolated static func decimalString(_ value: Double) -> String {
        String(format: "%.3f", max(0, value))
    }

    private func nextPage(
        _ next: String?,
        visited: inout Set<Int>
    ) throws -> Int? {
        guard let next else { return nil }
        guard let url = URL(string: next, relativeTo: configuration.serverURL)?.absoluteURL,
              Self.sameOrigin(url, configuration.serverURL),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let pageValue = components.queryItems?
                .first(where: { $0.name == "page" })?.value,
              let page = Int(pageValue),
              page > 0,
              visited.insert(page).inserted else {
            throw APIServiceError.untrustedPaginationURL
        }
        return page
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}

/// A new piece of gear, before the server has given it an identity.
nonisolated struct GearDraft: Hashable, Sendable {
    var kind: GearKind
    var name: String = ""
    var brand: String = ""
    var notes: String = ""
    var initialDistanceKilometers: Double = 0
    var retireAtKilometers: Double?
    var isDefault: Bool = false
}
