//
//  APIConfiguration.swift
//  IOS Frontend
//
//  Runtime origin selection for the OAS-generated client.
//

import Foundation

struct APIConfiguration: Hashable, Sendable {
    let serverURL: URL
    let allowsInsecureLocalhost: Bool

    static var current: APIConfiguration {
#if DEBUG
        // Development builds run in the iOS Simulator on the same Mac as the
        // backend. Release builds never inherit this HTTP exception.
        APIConfiguration(
            serverURL: URL(string: "http://localhost:5000/")!,
            allowsInsecureLocalhost: true
        )
#else
        guard let rawValue = Bundle.main.object(
            forInfoDictionaryKey: "REPBASE_API_URL"
        ) as? String,
              let url = URL(string: rawValue),
              url.scheme?.lowercased() == "https" else {
            preconditionFailure(
                "Release builds require an HTTPS REPBASE_API_URL Info.plist value."
            )
        }
        return APIConfiguration(
            serverURL: url,
            allowsInsecureLocalhost: false
        )
#endif
    }

    var displayName: String {
        serverURL.absoluteString
    }
}
