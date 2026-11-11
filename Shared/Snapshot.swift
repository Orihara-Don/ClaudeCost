import Foundation

enum CurrencyDisplay: String, Codable, CaseIterable, Sendable {
    case usd, jpy, both
}

/// snapshot.json のモデル。ウィジェットは金額を計算せず、これを表示するだけ。
struct Snapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let dayCount = 14

    struct Currency: Codable, Equatable, Sendable {
        var jpyRate: Double
        var show: CurrencyDisplay
    }

    struct Today: Codable, Equatable, Sendable {
        var date: String
        var usd: Double
    }

    struct Month: Codable, Equatable, Sendable {
        var month: String
        var usd: Double
        var forecastUsd: Double
    }

    struct Day: Codable, Equatable, Sendable {
        var date: String
        var usd: Double
    }

    struct ModelCost: Codable, Equatable, Sendable {
        var model: String
        var usd: Double
    }

    var schemaVersion: Int = Snapshot.currentSchemaVersion
    var generatedAt: Date
    var currency: Currency
    var regionalPricing: Bool
    var today: Today
    var month: Month
    var days: [Day]
    var topModels: [ModelCost]
    var unpricedModels: [String]
    var logsFound: Bool

    /// generatedAt を除いた表示内容が同じかを判定する（金額はセント単位に丸め済み）。
    func hasSameDisplay(as other: Snapshot) -> Bool {
        var a = self
        var b = other
        a.generatedAt = .distantPast
        b.generatedAt = .distantPast
        return a == b
    }

    /// 0時のタイムラインエントリ用。今日を$0.00にして日付を進める。
    func rolledOver(to date: Date, calendar: Calendar = .current) -> Snapshot {
        var next = self
        let day = DayKey.string(from: date, calendar: calendar)
        next.generatedAt = date
        next.today = Today(date: day, usd: 0)
        if DayKey.month(of: day) != month.month {
            next.month = Month(month: DayKey.month(of: day), usd: 0, forecastUsd: 0)
        }
        next.days = Array((days + [Day(date: day, usd: 0)]).suffix(Snapshot.dayCount))
        return next
    }
}
