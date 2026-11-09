import Foundation

/// A bounded appearance preference, never a sharing permission.
nonisolated enum PlannerItemColor: String, CaseIterable, Identifiable, Codable, Sendable {
    case coral, amber, sage, teal, sky, lavender, rose, slate
    var id: String { rawValue }

    var title: String {
        switch self {
        case .coral: String(localized: "Coral", bundle: .app, locale: .app)
        case .amber: String(localized: "Amber", bundle: .app, locale: .app)
        case .sage: String(localized: "Sage", bundle: .app, locale: .app)
        case .teal: String(localized: "Teal", bundle: .app, locale: .app)
        case .sky: String(localized: "Sky", bundle: .app, locale: .app)
        case .lavender: String(localized: "Lavender", bundle: .app, locale: .app)
        case .rose: String(localized: "Rose", bundle: .app, locale: .app)
        case .slate: String(localized: "Slate", bundle: .app, locale: .app)
        }
    }
}
