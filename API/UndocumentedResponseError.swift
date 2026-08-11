//
//  UndocumentedResponseError.swift
//  RepbaseAPI
//
//  Safe fallback handling for error responses that are not modeled by the OAS.
//

import Foundation
import OpenAPIRuntime

/// A user-facing error for a non-success response that is not documented by
/// the OpenAPI contract.
///
/// The current contract does not define error schemas. For client-validation
/// statuses, this type makes a best-effort pass over a small JSON response and
/// surfaces only plain text. Every other response keeps the generic fallback.
public struct RepbaseAPIHTTPError: LocalizedError, Sendable {
    public let statusCode: Int
    public let serverMessage: String?

    public var errorDescription: String? {
        if let serverMessage {
            return serverMessage
        }
        if statusCode == 401 {
            return "The username, password, or saved session is not valid."
        }
        return "The server returned an unexpected response (HTTP \(statusCode))."
    }

    public static func decode(
        statusCode: Int,
        payload: UndocumentedPayload
    ) async -> Self {
        guard Self.userActionableStatuses.contains(statusCode),
              let body = payload.body,
              let data = try? await Data(collecting: body, upTo: 16 * 1024),
              let value = try? JSONSerialization.jsonObject(with: data),
              let message = Self.readableMessage(from: value) else {
            return Self(statusCode: statusCode, serverMessage: nil)
        }

        return Self(statusCode: statusCode, serverMessage: message)
    }

    private static let userActionableStatuses = [400, 409, 422]

    private static func readableMessage(from value: Any) -> String? {
        let lines: [String]

        if let dictionary = value as? [String: Any] {
            lines = dictionary.keys.sorted().flatMap { key -> [String] in
                guard let fieldValue = dictionary[key] else { return [] }
                let values = textValues(from: fieldValue)
                guard !values.isEmpty else { return [] }

                if key == "detail" || key == "non_field_errors" {
                    return values
                }

                let label = key
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized
                return values.map { "\(label): \($0)" }
            }
        } else {
            lines = textValues(from: value)
        }

        let limitedLines = lines
            .map(clean)
            .filter { !$0.isEmpty }
            .prefix(6)
        guard !limitedLines.isEmpty else { return nil }
        return limitedLines.joined(separator: "\n")
    }

    private static func textValues(from value: Any) -> [String] {
        if let string = value as? String {
            return [string]
        }
        if let array = value as? [Any] {
            return array.flatMap(textValues)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.keys.sorted().flatMap { key in
                guard let nestedValue = dictionary[key] else { return [] }
                return textValues(from: nestedValue)
            }
        }
        return []
    }

    private static func clean(_ message: String) -> String {
        let collapsed = message
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return String(collapsed.prefix(300))
    }
}
