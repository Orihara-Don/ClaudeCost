import Foundation

enum AppPaths {
    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeCost", isDirectory: true)
    }
    static var state: URL { supportDirectory.appendingPathComponent("state.json") }
    static var userPrices: URL { supportDirectory.appendingPathComponent("prices.json") }
}

struct TokenCounts: Codable, Equatable, Sendable {
    var input = 0
    var output = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0
    var cacheRead = 0

    var total: Int { input + output + cacheWrite5m + cacheWrite1h + cacheRead }

    static func += (a: inout TokenCounts, b: TokenCounts) {
        a.input += b.input
        a.output += b.output
        a.cacheWrite5m += b.cacheWrite5m
        a.cacheWrite1h += b.cacheWrite1h
        a.cacheRead += b.cacheRead
    }
}

struct UsageRow: Codable, Equatable, Sendable {
    var day: String
    var model: String
    var project: String
    var tokens: TokenCounts
}

struct UsageKey: Hashable, Sendable {
    var day: String
    var model: String
    var project: String
}

struct FileCursor: Codable, Equatable, Sendable {
    var offset: UInt64
    var inode: UInt64
}

/// state.json の内容。バイト位置、重複排除キー、全期間の日別集計を持つ。
struct UsageStore: Sendable {
    static let schemaVersion = 1

    var cursors: [String: FileCursor] = [:]
    /// 重複排除キー → イベント時刻（UNIX秒）
    var seen: [String: Int64] = [:]
    var usage: [UsageKey: TokenCounts] = [:]
    /// usage付きの行が無いままログが伸び続けている期間（形式変更の検知用）
    var growthWithoutUsageStart: Date?
    var growthWithoutUsageLast: Date?

    private struct Disk: Codable {
        var schemaVersion: Int
        var cursors: [String: FileCursor]
        var seen: [String: Int64]
        var rows: [UsageRow]
        var growthWithoutUsageStart: Date?
        var growthWithoutUsageLast: Date?
    }

    var rows: [UsageRow] {
        usage.map { UsageRow(day: $0.key.day, model: $0.key.model, project: $0.key.project, tokens: $0.value) }
    }

    mutating func add(day: String, model: String, project: String, tokens: TokenCounts) {
        usage[UsageKey(day: day, model: model, project: project), default: TokenCounts()] += tokens
    }

    /// 壊れたファイルは上書きせず退避して、空の状態から始める。
    static func load(from url: URL) -> UsageStore {
        guard let data = try? Data(contentsOf: url) else { return UsageStore() }
        guard let disk = try? JSONDecoder().decode(Disk.self, from: data),
              disk.schemaVersion == schemaVersion else {
            let backup = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            return UsageStore()
        }
        var store = UsageStore()
        store.cursors = disk.cursors
        store.seen = disk.seen
        store.growthWithoutUsageStart = disk.growthWithoutUsageStart
        store.growthWithoutUsageLast = disk.growthWithoutUsageLast
        for row in disk.rows {
            store.add(day: row.day, model: row.model, project: row.project, tokens: row.tokens)
        }
        return store
    }

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let disk = Disk(
            schemaVersion: UsageStore.schemaVersion,
            cursors: cursors,
            seen: seen,
            rows: rows,
            growthWithoutUsageStart: growthWithoutUsageStart,
            growthWithoutUsageLast: growthWithoutUsageLast)
        try JSONEncoder().encode(disk).write(to: url, options: .atomic)
    }
}
