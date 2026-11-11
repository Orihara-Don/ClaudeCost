import Foundation

/// App Group コンテナの読み書き。
enum SharedStore {
    static let widgetKind = "ClaudeCostWidget"

    /// Info.plist で $(TeamIdentifierPrefix)claudecost を展開した値。
    static var appGroupID: String {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? "claudecost"
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("snapshot.json")
    }

    static func encode(_ snapshot: Snapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) -> Snapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data),
              snapshot.schemaVersion == Snapshot.currentSchemaVersion else { return nil }
        return snapshot
    }

    static func readSnapshot() -> Snapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    /// 一時ファイルへの書き出しとリネームで置き換える。
    static func write(_ snapshot: Snapshot) throws {
        guard let url = snapshotURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(snapshot).write(to: url, options: .atomic)
    }
}
