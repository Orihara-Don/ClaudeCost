import Foundation

struct ScanProgress: Sendable {
    var done: Int
    var total: Int
}

struct ScanResult: Sendable {
    var rows: [UsageRow]
    var logsFound: Bool
    var logFormatWarning: Bool
}

/// 必要なフィールドだけを読む。未知のフィールドは無視する。
private struct LogLine: Decodable {
    struct Message: Decodable {
        var id: String?
        var model: String?
        var usage: Usage?
    }

    struct Usage: Decodable {
        var input_tokens: Int?
        var output_tokens: Int?
        var cache_read_input_tokens: Int?
        var cache_creation_input_tokens: Int?
        var cache_creation: CacheCreation?
    }

    struct CacheCreation: Decodable {
        var ephemeral_5m_input_tokens: Int?
        var ephemeral_1h_input_tokens: Int?
    }

    var timestamp: String?
    var requestId: String?
    var message: Message?
}

actor LogScanner {
    static let seenRetention: TimeInterval = 31 * 24 * 3600
    static let formatWarningInterval: TimeInterval = 3600
    private static let chunkSize = 4 << 20

    private let stateURL: URL
    private let calendar: Calendar
    private let onProgress: @Sendable (ScanProgress?) async -> Void
    private let onResult: @Sendable (ScanResult) async -> Void

    private var store: UsageStore?
    private var isRunning = false
    private var rerunRequested = false

    private let decoder = JSONDecoder()
    private let fractionalParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let plainParser = ISO8601DateFormatter()

    init(
        stateURL: URL,
        calendar: Calendar = .current,
        onProgress: @escaping @Sendable (ScanProgress?) async -> Void = { _ in },
        onResult: @escaping @Sendable (ScanResult) async -> Void = { _ in }
    ) {
        self.stateURL = stateURL
        self.calendar = calendar
        self.onProgress = onProgress
        self.onResult = onResult
    }

    /// 実行中に来た要求は、終わった後に1回だけ再実行する。
    func requestScan(root: URL) async {
        if isRunning {
            rerunRequested = true
            return
        }
        isRunning = true
        repeat {
            rerunRequested = false
            let result = await scanOnce(root: root)
            await onResult(result)
        } while rerunRequested
        isRunning = false
    }

    func scanOnce(root: URL, now: Date = Date()) async -> ScanResult {
        var current = store ?? UsageStore.load(from: stateURL)
        store = nil
        defer { store = current }

        let isInitial = current.cursors.isEmpty
        let files = LogScanner.listLogFiles(root: root)
        var dirty = false
        var grew = false
        var foundUsage = false

        for (index, file) in files.enumerated() {
            if isInitial {
                await onProgress(ScanProgress(done: index, total: files.count))
            }
            let outcome = await ingest(file: file, root: root, now: now, store: &current)
            dirty = dirty || outcome.moved
            grew = grew || outcome.moved
            foundUsage = foundUsage || outcome.foundUsage
        }
        if isInitial { await onProgress(nil) }

        let existing = Set(files.map(\.path))
        let staleCursors = current.cursors.keys.filter { !existing.contains($0) }
        for path in staleCursors { current.cursors[path] = nil }

        let cutoff = Int64(now.timeIntervalSince1970 - LogScanner.seenRetention)
        let countBefore = current.seen.count
        current.seen = current.seen.filter { $0.value >= cutoff }

        if foundUsage {
            current.growthWithoutUsageStart = nil
            current.growthWithoutUsageLast = nil
        } else if grew {
            current.growthWithoutUsageStart = current.growthWithoutUsageStart ?? now
            current.growthWithoutUsageLast = now
        }

        if dirty || !staleCursors.isEmpty || countBefore != current.seen.count {
            do {
                try current.save(to: stateURL)
            } catch {
                NSLog("ClaudeCost: state.json の保存に失敗: \(error.localizedDescription)")
            }
        }

        var warning = false
        if let start = current.growthWithoutUsageStart, let last = current.growthWithoutUsageLast {
            warning = last.timeIntervalSince(start) >= LogScanner.formatWarningInterval
        }
        return ScanResult(rows: current.rows, logsFound: !files.isEmpty, logFormatWarning: warning)
    }

    private static func listLogFiles(root: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            files.append(url.standardizedFileURL)
        }
        return files.sorted { $0.path < $1.path }
    }

    private func projectName(file: URL, root: URL) -> String {
        let base = root.standardizedFileURL.pathComponents.count
        let parts = file.pathComponents
        return parts.count > base + 1 ? parts[base] : "(unknown)"
    }

    /// 読めないファイルは位置を進めず、次回に再試行する。
    private func ingest(
        file: URL, root: URL, now: Date, store: inout UsageStore
    ) async -> (moved: Bool, foundUsage: Bool) {
        var info = stat()
        guard stat(file.path, &info) == 0 else { return (false, false) }
        let size = UInt64(info.st_size)
        let inode = UInt64(info.st_ino)

        var offset: UInt64 = 0
        var isReread = false
        if let cursor = store.cursors[file.path] {
            if cursor.inode == inode && size >= cursor.offset {
                offset = cursor.offset
            } else {
                isReread = true
            }
        }
        if size == offset && !isReread { return (false, false) }

        guard let handle = try? FileHandle(forReadingFrom: file) else { return (false, false) }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return (false, false)
        }

        let project = projectName(file: file, root: root)
        var committed = offset
        var carry = Data()
        var foundUsage = false
        while let chunk = try? handle.read(upToCount: LogScanner.chunkSize), !chunk.isEmpty {
            var buffer = carry
            buffer.append(chunk)
            guard let lastNewline = buffer.lastIndex(of: 0x0A) else {
                carry = buffer
                continue
            }
            let complete = buffer[buffer.startIndex...lastNewline]
            if processLines(complete, project: project, isReread: isReread, now: now, store: &store) {
                foundUsage = true
            }
            committed += UInt64(complete.count)
            carry = Data(buffer[(lastNewline + 1)...])
            await Task.yield()
        }

        let moved = committed != offset || isReread
        store.cursors[file.path] = FileCursor(offset: committed, inode: inode)
        return (moved, foundUsage)
    }

    private func processLines(
        _ data: Data, project: String, isReread: Bool, now: Date, store: inout UsageStore
    ) -> Bool {
        var foundUsage = false
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: 0x0A) ?? data.endIndex
            let line = data[start..<end]
            start = end + 1
            guard LogScanner.containsUsageMarker(line) else { continue }
            if processLine(line, project: project, isReread: isReread, now: now, store: &store) {
                foundUsage = true
            }
        }
        return foundUsage
    }

    private static let usageMarker = Array("\"usage\"".utf8)

    private static func containsUsageMarker(_ line: Data) -> Bool {
        line.withUnsafeBytes { bytes in
            usageMarker.withUnsafeBytes { marker in
                memmem(bytes.baseAddress, bytes.count, marker.baseAddress, marker.count) != nil
            }
        }
    }

    private func parseDate(_ text: String) -> Date? {
        fractionalParser.date(from: text) ?? plainParser.date(from: text)
    }

    /// 形式どおりの usage 行なら true（重複や synthetic でも形式確認としては true）。
    private func processLine(
        _ line: Data, project: String, isReread: Bool, now: Date, store: inout UsageStore
    ) -> Bool {
        guard let record = try? decoder.decode(LogLine.self, from: line),
              let message = record.message,
              let usage = message.usage,
              let input = usage.input_tokens,
              let output = usage.output_tokens,
              let rawModel = message.model,
              let messageID = message.id,
              let requestID = record.requestId,
              let timestamp = record.timestamp,
              let date = parseDate(timestamp) else { return false }

        guard rawModel != "<synthetic>" else { return true }

        let key = messageID + "|" + requestID
        guard store.seen[key] == nil else { return true }

        // 重複排除キーを捨てた古い行は、読み直しでは集計済みなので数えない
        if isReread && date.timeIntervalSince(now) < -LogScanner.seenRetention { return true }

        store.seen[key] = Int64(date.timeIntervalSince1970)

        var tokens = TokenCounts()
        tokens.input = input
        tokens.output = output
        tokens.cacheRead = usage.cache_read_input_tokens ?? 0
        let write5m = usage.cache_creation?.ephemeral_5m_input_tokens ?? 0
        let write1h = usage.cache_creation?.ephemeral_1h_input_tokens ?? 0
        if write5m + write1h > 0 {
            tokens.cacheWrite5m = write5m
            tokens.cacheWrite1h = write1h
        } else {
            tokens.cacheWrite5m = usage.cache_creation_input_tokens ?? 0
        }

        store.add(
            day: DayKey.string(from: date, calendar: calendar),
            model: ModelName.applyingLongPromptTier(
                ModelName.normalize(rawModel),
                promptTokens: tokens.input + tokens.cacheRead + tokens.cacheWrite5m + tokens.cacheWrite1h),
            project: project,
            tokens: tokens)
        return true
    }
}
