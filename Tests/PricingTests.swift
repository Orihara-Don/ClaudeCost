import XCTest

final class PricingTests: XCTestCase {
    private func bundledPrices() throws -> PriceTable {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Resources/prices.json")
        return try PriceTable.decode(Data(contentsOf: url))
    }

    func testNormalize() {
        let cases = [
            "us.anthropic.claude-opus-5-5-v1:0": "claude-opus-5-5",
            "global.anthropic.claude-sonnet-5-5-v1:0": "claude-sonnet-5-5",
            "jp.anthropic.claude-haiku-4-5-20251001-v1:0": "claude-haiku-4-5",
            "apac.anthropic.claude-sonnet-4-20250514-v1:0": "claude-sonnet-4",
            "claude-haiku-4-5-20251001": "claude-haiku-4-5",
            "claude-opus-5-5[1m]": "claude-opus-5-5",
            "claude-opus-5-5": "claude-opus-5-5",
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(ModelName.normalize(raw), expected, raw)
        }
    }

    func testLookupDoesNotCrossVersions() throws {
        let prices = try bundledPrices()
        XCTAssertEqual(prices.price(for: "claude-opus-5-5")?.input, 4)
        XCTAssertEqual(prices.price(for: "claude-opus-5")?.input, 5)
        XCTAssertEqual(prices.price(for: "claude-sonnet-5")?.input, 2)
        XCTAssertEqual(prices.price(for: "claude-sonnet-5-5")?.cacheRead, 0.10)
        XCTAssertEqual(prices.price(for: "claude-haiku-5-5-over-100k")?.input, 0.50)
        XCTAssertNil(prices.price(for: "claude-sonnet-5-9"), "別バージョンに一致させない")
        XCTAssertNil(prices.price(for: "claude-opus-5-9"), "別バージョンに一致させない")
        XCTAssertEqual(prices.price(for: "claude-opus-5-5-preview")?.input, 4)
    }

    func testCostFormula() throws {
        let prices = try bundledPrices()
        var tokens = TokenCounts()
        tokens.input = 1_000_000
        tokens.output = 1_000_000
        tokens.cacheWrite5m = 1_000_000
        tokens.cacheWrite1h = 1_000_000
        tokens.cacheRead = 1_000_000
        // Opus 5.5: 4 + 20 + 5 + 8 + 0.2
        let base = try XCTUnwrap(prices.cost(tokens, model: "claude-opus-5-5", regionalPricing: false))
        XCTAssertEqual(base, 37.2, accuracy: 1e-9)
        let regional = try XCTUnwrap(prices.cost(tokens, model: "claude-opus-5-5", regionalPricing: true))
        XCTAssertEqual(regional, 37.2 * 1.1, accuracy: 1e-9)
    }

    func testRegionalAppliesOnlyToEligibleModels() throws {
        let prices = try bundledPrices()
        var tokens = TokenCounts()
        tokens.input = 1_000_000
        XCTAssertEqual(prices.cost(tokens, model: "claude-sonnet-4", regionalPricing: true) ?? 0, 3, accuracy: 1e-9)
        XCTAssertEqual(prices.cost(tokens, model: "claude-sonnet-4-5", regionalPricing: true) ?? 0, 3.3, accuracy: 1e-9)
    }

    func testUnpricedModelIsReportedAndExcluded() throws {
        var tokens = TokenCounts()
        tokens.input = 1_000_000
        let rows = [
            UsageRow(day: "2026-11-10", model: "claude-unknown-1", project: "p", tokens: tokens),
            UsageRow(day: "2026-11-10", model: "claude-opus-5-5", project: "p", tokens: tokens),
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let now = ISO8601DateFormatter().date(from: "2026-11-10T03:00:00Z")!
        let data = SnapshotBuilder.build(
            rows: rows,
            prices: try bundledPrices(),
            options: BuildOptions(jpyRate: 150, show: .both, regionalPricing: false),
            logsFound: true,
            now: now,
            calendar: calendar)
        XCTAssertEqual(data.snapshot.today.usd, 4)
        XCTAssertEqual(data.snapshot.unpricedModels, ["claude-unknown-1"])
        XCTAssertEqual(data.snapshot.topModels.map(\.model), ["opus-5-5"])
        XCTAssertEqual(data.snapshot.month.forecastUsd, 12, "4 ÷ 10日 × 30日")
        XCTAssertEqual(data.snapshot.days.count, 14)
        XCTAssertEqual(data.models.last?.usd, nil)
    }

    func testWeeksStartOnMonday() throws {
        var tokens = TokenCounts()
        tokens.input = 1_000_000
        let rows = ["2026-11-08", "2026-11-09", "2026-11-10"].map {
            UsageRow(day: $0, model: "claude-opus-5-5", project: "p", tokens: tokens)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let now = ISO8601DateFormatter().date(from: "2026-11-10T03:00:00Z")!
        let data = SnapshotBuilder.build(
            rows: rows,
            prices: try bundledPrices(),
            options: BuildOptions(jpyRate: 150, show: .both, regionalPricing: false),
            logsFound: true,
            now: now,
            calendar: calendar)
        XCTAssertEqual(data.weeks.count, 8)
        XCTAssertEqual(data.weeks.last, Snapshot.Day(date: "2026-11-09", usd: 8), "11/9(月)と11/10の2日分")
        XCTAssertEqual(data.weeks[6], Snapshot.Day(date: "2026-11-02", usd: 4), "11/8(日)は前の週")
    }

    func testRolloverAcrossMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let snapshot = Snapshot(
            generatedAt: Date(timeIntervalSince1970: 0),
            currency: .init(jpyRate: 150, show: .both),
            regionalPricing: true,
            today: .init(date: "2026-11-30", usd: 5),
            month: .init(month: "2026-11", usd: 50, forecastUsd: 50),
            days: [],
            topModels: [],
            unpricedModels: [],
            logsFound: true)
        let midnight = ISO8601DateFormatter().date(from: "2026-11-30T15:00:00Z")!
        let next = snapshot.rolledOver(to: midnight, calendar: calendar)
        XCTAssertEqual(next.today.date, "2026-12-01")
        XCTAssertEqual(next.today.usd, 0)
        XCTAssertEqual(next.month.month, "2026-12")
        XCTAssertEqual(next.month.usd, 0)
    }
}
