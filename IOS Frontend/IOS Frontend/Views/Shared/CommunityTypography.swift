//
//  CommunityTypography.swift
//  IOS Frontend
//
//  Community Warmth: a welcoming, social-first type system built on
//  Nunito Sans while preserving Dynamic Type throughout the app.
//

import SwiftUI

enum RepbaseTypography {
    static let family = "Nunito Sans"
    static let regularWeight = "Regular"
    static let semiboldWeight = "SemiBold"
    static let boldWeight = "Bold"

    fileprivate static let regularPostScriptName = "NunitoSans-Regular"
    fileprivate static let semiboldPostScriptName = "NunitoSans-SemiBold"
    fileprivate static let boldPostScriptName = "NunitoSans-Bold"
}

extension Font {
    /// Community Warmth for semantic iOS text styles. Passing no weight keeps
    /// the familiar iOS hierarchy: headlines are emphasized and supporting
    /// copy remains relaxed.
    static func community(
        _ style: Font.TextStyle,
        weight: Font.Weight? = nil
    ) -> Font {
        let resolvedWeight = weight ?? defaultCommunityWeight(for: style)
        return .custom(
            communityPostScriptName(for: resolvedWeight),
            size: communityPointSize(for: style),
            relativeTo: style
        )
    }

    /// Community Warmth for compact labels and display moments with explicit
    /// sizes. The nearest semantic style is used so Dynamic Type still scales
    /// the result appropriately.
    static func community(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        // Monospaced values are functional data, not brand typography.
        guard design != .monospaced else {
            return .system(size: size, weight: weight, design: design)
        }

        return .custom(
            communityPostScriptName(for: weight),
            size: size,
            relativeTo: communityRelativeStyle(for: size)
        )
    }

    private static func communityPostScriptName(for weight: Font.Weight) -> String {
        if weight == .bold || weight == .heavy || weight == .black {
            return RepbaseTypography.boldPostScriptName
        }
        if weight == .medium || weight == .semibold {
            return RepbaseTypography.semiboldPostScriptName
        }
        return RepbaseTypography.regularPostScriptName
    }

    private static func defaultCommunityWeight(for style: Font.TextStyle) -> Font.Weight {
        switch style {
        case .largeTitle, .title, .title2:
            return .bold
        case .title3, .headline:
            return .semibold
        default:
            return .regular
        }
    }

    private static func communityPointSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }

    private static func communityRelativeStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 30...: .largeTitle
        case 25..<30: .title
        case 21..<25: .title2
        case 19..<21: .title3
        case 17..<19: .body
        case 16..<17: .callout
        case 14..<16: .subheadline
        case 12..<14: .footnote
        case 11..<12: .caption
        default: .caption2
        }
    }
}
