import Foundation

nonisolated enum GFChannelLabelTime {
    static let serverTimeZone = TimeZone(identifier: "Europe/Riga")!

    static func resolve(_ text: String, now: Date, serverTimeZone: TimeZone = serverTimeZone) -> Date? {
        nil
    }

    static func badgeText(start: Date, now: Date, zone: TimeZone = .current, locale: Locale = .current) -> String {
        ""
    }
}
