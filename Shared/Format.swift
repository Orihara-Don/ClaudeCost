import Foundation

/// ローカル日付の "yyyy-MM-dd" / "yyyy-MM" キー。
enum DayKey {
    static func string(from date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func month(of day: String) -> String {
        String(day.prefix(7))
    }
}

enum Format {
    private static let usLocale = Locale(identifier: "en_US")

    static func usd(_ value: Double) -> String {
        "$" + value.formatted(.number.precision(.fractionLength(2)).locale(usLocale))
    }

    static func jpy(usd value: Double, rate: Double) -> String {
        "¥" + (value * rate).formatted(.number.precision(.fractionLength(0)).locale(usLocale))
    }

    /// 通貨設定に応じて、主表示と副表示を返す。
    static func amounts(usd value: Double, rate: Double, show: CurrencyDisplay) -> (primary: String, secondary: String?) {
        switch show {
        case .usd: return (usd(value), nil)
        case .jpy: return (jpy(usd: value, rate: rate), nil)
        case .both: return (usd(value), jpy(usd: value, rate: rate))
        }
    }

    static func amounts(usd value: Double, currency: Snapshot.Currency) -> (primary: String, secondary: String?) {
        amounts(usd: value, rate: currency.jpyRate, show: currency.show)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "2026-10-28" → "10/28"
    static func shortDay(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return day }
        return "\(m)/\(d)"
    }

    /// "claude-opus-5-5" → "opus-5-5"
    static func modelName(_ model: String) -> String {
        model.hasPrefix("claude-") ? String(model.dropFirst("claude-".count)) : model
    }

    static func tokens(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(usLocale))
    }
}
