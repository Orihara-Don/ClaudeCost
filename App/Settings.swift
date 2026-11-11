import Foundation

enum MenuBarMode: String, CaseIterable, Identifiable {
    case today, month, iconOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: return "今日"
        case .month: return "今月"
        case .iconOnly: return "アイコンのみ"
        }
    }
}

extension CurrencyDisplay: Identifiable {
    var id: String { rawValue }
    var label: String {
        switch self {
        case .usd: return "USD"
        case .jpy: return "円"
        case .both: return "両方"
        }
    }
}

/// App Group の UserDefaults に保存する設定。
struct AppSettings: Equatable {
    var menuBarMode: MenuBarMode = .today
    var currency: CurrencyDisplay = .both
    var jpyRate: Double = 150
    var regionalPricing = true
    var monthlyBudget: Double?
    /// 空なら既定の場所を使う
    var customLogPath = ""

    private enum Key {
        static let menuBarMode = "menuBarMode"
        static let currency = "currency"
        static let jpyRate = "jpyRate"
        static let regionalPricing = "regionalPricing"
        static let monthlyBudget = "monthlyBudget"
        static let customLogPath = "customLogPath"
    }

    static let didAskLaunchAtLoginKey = "didAskLaunchAtLogin"

    /// 設定 > CLAUDE_CONFIG_DIR > ~/.claude の順で決める。
    var projectsURL: URL {
        if !customLogPath.isEmpty {
            return URL(fileURLWithPath: customLogPath, isDirectory: true)
        }
        if let config = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !config.isEmpty {
            return URL(fileURLWithPath: config, isDirectory: true).appendingPathComponent("projects")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    static func load(from d: UserDefaults) -> AppSettings {
        var s = AppSettings()
        if let v = d.string(forKey: Key.menuBarMode).flatMap(MenuBarMode.init) { s.menuBarMode = v }
        if let v = d.string(forKey: Key.currency).flatMap(CurrencyDisplay.init) { s.currency = v }
        if d.object(forKey: Key.jpyRate) != nil { s.jpyRate = d.double(forKey: Key.jpyRate) }
        if d.object(forKey: Key.regionalPricing) != nil { s.regionalPricing = d.bool(forKey: Key.regionalPricing) }
        if d.object(forKey: Key.monthlyBudget) != nil { s.monthlyBudget = d.double(forKey: Key.monthlyBudget) }
        s.customLogPath = d.string(forKey: Key.customLogPath) ?? ""
        return s
    }

    func save(to d: UserDefaults) {
        d.set(menuBarMode.rawValue, forKey: Key.menuBarMode)
        d.set(currency.rawValue, forKey: Key.currency)
        d.set(jpyRate, forKey: Key.jpyRate)
        d.set(regionalPricing, forKey: Key.regionalPricing)
        if let monthlyBudget {
            d.set(monthlyBudget, forKey: Key.monthlyBudget)
        } else {
            d.removeObject(forKey: Key.monthlyBudget)
        }
        d.set(customLogPath, forKey: Key.customLogPath)
    }
}
