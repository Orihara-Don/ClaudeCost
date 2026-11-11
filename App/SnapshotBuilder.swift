import Foundation
import WidgetKit

struct BuildOptions: Sendable {
    var jpyRate: Double
    var show: CurrencyDisplay
    var regionalPricing: Bool
}

/// パネル表示用。スナップショットより詳しい今月の内訳を持つ。
struct PanelData: Sendable {
    struct ModelRow: Identifiable, Sendable {
        var id: String { model }
        var model: String
        var usd: Double?
        var tokens: Int
    }

    struct ProjectRow: Identifiable, Sendable {
        var id: String { project }
        var project: String
        var usd: Double
    }

    var snapshot: Snapshot
    /// 月曜始まりの直近8週。date は週の開始日で、最後の要素が今週。
    var weeks: [Snapshot.Day]
    var models: [ModelRow]
    var projects: [ProjectRow]
}

enum SnapshotBuilder {
    private static let weekCount = 8

    private static func cents(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    static func build(
        rows: [UsageRow],
        prices: PriceTable,
        options: BuildOptions,
        logsFound: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> PanelData {
        let todayKey = DayKey.string(from: now, calendar: calendar)
        let monthKey = DayKey.month(of: todayKey)

        var perDay: [String: Double] = [:]
        var perModel: [String: (usd: Double?, tokens: Int)] = [:]
        var perProject: [String: Double] = [:]

        for row in rows {
            let cost = prices.cost(row.tokens, model: row.model, regionalPricing: options.regionalPricing)
            if let cost { perDay[row.day, default: 0] += cost }
            guard DayKey.month(of: row.day) == monthKey else { continue }
            var entry = perModel[row.model] ?? (nil, 0)
            entry.tokens += row.tokens.total
            if let cost {
                entry.usd = (entry.usd ?? 0) + cost
                perProject[row.project, default: 0] += cost
            }
            perModel[row.model] = entry
        }

        let monthUsd = perDay.filter { DayKey.month(of: $0.key) == monthKey }.values.reduce(0, +)
        let elapsedDays = calendar.component(.day, from: now)
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? elapsedDays
        let forecast = monthUsd / Double(elapsedDays) * Double(daysInMonth)

        let days: [Snapshot.Day] = (0..<Snapshot.dayCount).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let key = DayKey.string(from: date, calendar: calendar)
            return Snapshot.Day(date: key, usd: cents(perDay[key] ?? 0))
        }

        let models = perModel
            .map { PanelData.ModelRow(model: $0.key, usd: $0.value.usd, tokens: $0.value.tokens) }
            .sorted { ($0.usd ?? -1, $0.model) > ($1.usd ?? -1, $1.model) }

        let topModels = models.compactMap { row in
            row.usd.map { Snapshot.ModelCost(model: Format.modelName(row.model), usd: cents($0)) }
        }.prefix(4)

        let projects = perProject
            .map { PanelData.ProjectRow(project: $0.key, usd: $0.value) }
            .sorted { ($0.usd, $0.project) > ($1.usd, $1.project) }
            .prefix(5)

        let snapshot = Snapshot(
            generatedAt: now,
            currency: .init(jpyRate: options.jpyRate, show: options.show),
            regionalPricing: options.regionalPricing,
            today: .init(date: todayKey, usd: cents(perDay[todayKey] ?? 0)),
            month: .init(month: monthKey, usd: cents(monthUsd), forecastUsd: cents(forecast)),
            days: days,
            topModels: Array(topModels),
            unpricedModels: models.filter { $0.usd == nil }.map(\.model).sorted(),
            logsFound: logsFound)

        return PanelData(
            snapshot: snapshot,
            weeks: weeks(perDay: perDay, now: now, calendar: calendar),
            models: models,
            projects: Array(projects))
    }

    private static func weeks(perDay: [String: Double], now: Date, calendar: Calendar) -> [Snapshot.Day] {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        guard let thisWeek = mondayFirst.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        return (0..<weekCount).reversed().compactMap { offset in
            guard let start = mondayFirst.date(byAdding: .day, value: -7 * offset, to: thisWeek) else { return nil }
            let total = (0..<7).reduce(0.0) { sum, day in
                guard let date = mondayFirst.date(byAdding: .day, value: day, to: start) else { return sum }
                return sum + (perDay[DayKey.string(from: date, calendar: calendar)] ?? 0)
            }
            return Snapshot.Day(date: DayKey.string(from: start, calendar: calendar), usd: cents(total))
        }
    }
}

/// snapshot.json を書き出し、必要なときだけウィジェットに再描画を促す。
@MainActor
final class SnapshotPublisher {
    static let minimumReloadInterval: TimeInterval = 60

    private var lastPublished: Snapshot?
    private var lastReloadAt: Date?
    private var deferredReload: Task<Void, Never>?

    /// force は設定変更時など、間隔制限なしで通知したいときに使う。
    func publish(_ snapshot: Snapshot, force: Bool) {
        do {
            try SharedStore.write(snapshot)
        } catch {
            NSLog("ClaudeCost: snapshot.json の書き込みに失敗: \(error.localizedDescription)")
            return
        }
        let dayChanged = lastPublished.map { $0.today.date != snapshot.today.date } ?? false
        let changed = lastPublished.map { !$0.hasSameDisplay(as: snapshot) } ?? true
        lastPublished = snapshot

        if force || dayChanged {
            reloadNow()
        } else if changed {
            reloadThrottled()
        }
    }

    private func reloadNow() {
        deferredReload?.cancel()
        deferredReload = nil
        lastReloadAt = Date()
        WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.widgetKind)
    }

    private func reloadThrottled() {
        let elapsed = lastReloadAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if elapsed >= SnapshotPublisher.minimumReloadInterval {
            reloadNow()
            return
        }
        guard deferredReload == nil else { return }
        let wait = SnapshotPublisher.minimumReloadInterval - elapsed
        deferredReload = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.reloadNow()
        }
    }
}
