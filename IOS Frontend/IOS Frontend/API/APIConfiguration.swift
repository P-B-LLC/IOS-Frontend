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
        // An origin passed in at build time wins; otherwise the hosted backend.
        //
        // The default used to be http://localhost:5000/, which reached a Django
        // dev server on the Mac that built the app. That server is gone: the
        // backend now runs on the DigitalOcean droplet against the hosted
        // PostgreSQL database, and the Mac holds nothing the app should read.
        //
        // The droplet's certificate is a real Let's Encrypt one issued for the
        // IP itself, so App Transport Security accepts this with no exception
        // and no arbitrary-loads escape hatch.
        //
        // To point a build somewhere else -- a dev server on this machine, or a
        // Mac's address on the network when running on a physical iPhone --
        // pass it in:
        //
        //   xcodebuild ... REPBASE_API_URL=http://192.168.1.20:5000/
        //
        // Plain HTTP is still allowed there only because NSAllowsLocalNetworking
        // covers LAN addresses; NSAllowsArbitraryLoads stays false, so a remote
        // host over HTTP remains unreachable.
        if let declared = declaredOrigin() {
            return APIConfiguration(
                serverURL: declared,
                allowsInsecureLocalhost: declared.scheme?.lowercased() != "https"
            )
        }
        // No trailing slash. The generated client appends paths that already
        // begin with one, so "https://host/" + "/api/v1/auth/login/" asks for
        // "//api/v1/auth/login/" -- which nginx forwards happily and Django's
        // resolver does not match, producing a 404 that looks like a missing
        // endpoint rather than a malformed URL.
        return APIConfiguration(
            serverURL: URL(string: "https://157.230.188.173")!,
            allowsInsecureLocalhost: false
        )
#else
        // Release has no fallback on purpose: an app pointed at nothing is
        // worse than one that refuses to start.
        //
        // The two cases are separated because they mean opposite things. An
        // empty value means the REPBASE_API_URL build setting was never given
        // one -- the substitution in the project resolved to nothing -- and
        // the old single message read as though a value had been set wrongly,
        // which sent you looking in the wrong place.
        guard let rawValue = Bundle.main.object(
            forInfoDictionaryKey: "REPBASE_API_URL"
        ) as? String,
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            preconditionFailure(
                """
                REPBASE_API_URL is empty in this Release build, so there is no \
                backend to talk to. The build setting was never given a value; \
                pass one to the archive, e.g. \
                REPBASE_API_URL=https://api.example.com/
                """
            )
        }
        guard let url = URL(string: rawValue),
              url.scheme?.lowercased() == "https" else {
            preconditionFailure(
                """
                REPBASE_API_URL must be an HTTPS origin in a Release build. \
                Found: \(rawValue)
                """
            )
        }
        return APIConfiguration(
            serverURL: url,
            allowsInsecureLocalhost: false
        )
#endif
    }

#if DEBUG
    /// The origin handed to this build, if it was given one.
    ///
    /// Both schemes are accepted here and only here: a development backend on
    /// the same network is reached over HTTP, and Release above takes HTTPS
    /// alone.
    private static func declaredOrigin() -> URL? {
        guard let rawValue = Bundle.main.object(
            forInfoDictionaryKey: "REPBASE_API_URL"
        ) as? String,
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }
#endif

    var displayName: String {
        serverURL.absoluteString
    }
}
