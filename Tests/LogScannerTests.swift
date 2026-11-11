import XCTest

final class LogScannerTests: XCTestCase {
    private var directory: URL!
    private var root: URL!
    private var stateURL: URL!
    private var calendar: Calendar!
    private let now = ISO8601DateFormatter().date(from: "2026-11-10T12:00:00Z")!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        root = directory.appendingPathComponent("projects")
        stateURL = directory.appendingPathComponent("state.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func logFile(_ relative: String = "proj/session.jsonl") throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }

    private func line(id: String, input: Int = 10, time: String = "2026-11-10T01:00:00.000Z", model: String = "claude-opus-5-5") -> String {
        #"{"timestamp":"\#(time)","requestId":"req_\#(id)","message":{"id":"msg_\#(id)","model":"\#(model)","usage":{"input_tokens":\#(input),"output_tokens":1}}}"#
    }

    private func append(_ text: String, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        } else {
            try Data(text.utf8).write(to: url)
        }
    }

    private func scanner() -> LogScanner {
        LogScanner(stateURL: stateURL, calendar: calendar)
    }

    private func totalInput(_ result: ScanResult) -> Int {
        result.rows.map(\.tokens.input).reduce(0, +)
    }

    func testFixtureDedupesAndSkipsBadLines() async throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("Fixtures/basic.jsonl")
        try FileManager.default.copyItem(at: fixture, to: try logFile())

        let result = await scanner().scanOnce(root: root, now: now)

        XCTAssertEqual(result.rows.count, 2, "synthetic と欠損行は除外され、モデルは2種類")
        let opus = try XCTUnwrap(result.rows.first { $0.model == "claude-opus-5-5" })
        XCTAssertEqual(opus.tokens, TokenCounts(input: 1000, output: 2000, cacheWrite5m: 1000, cacheWrite1h: 3000, cacheRead: 3000))
        XCTAssertEqual(opus.day, "2026-11-10")
        XCTAssertEqual(opus.project, "proj")
        let haiku = try XCTUnwrap(result.rows.first { $0.model == "claude-haiku-4-5" })
        XCTAssertEqual(haiku.tokens.cacheWrite5m, 300, "cache_creation が無ければ全部5分")
    }

    func testPartialLineIsReadNextTime() async throws {
        let file = try logFile()
        let scanner = scanner()
        let whole = line(id: "1")
        try append(line(id: "0") + "\n" + whole.prefix(20), to: file)

        var result = await scanner.scanOnce(root: root, now: now)
        XCTAssertEqual(totalInput(result), 10)

        try append(String(whole.dropFirst(20)), to: file)
        result = await scanner.scanOnce(root: root, now: now)
        XCTAssertEqual(totalInput(result), 10, "改行がまだ無い")

        try append("\n", to: file)
        result = await scanner.scanOnce(root: root, now: now)
        XCTAssertEqual(totalInput(result), 20)
    }

    func testRescanAfterRestartReadsOnlyDifference() async throws {
        let file = try logFile()
        try append(line(id: "1") + "\n", to: file)
        _ = await scanner().scanOnce(root: root, now: now)

        try append(line(id: "2") + "\n", to: file)
        let result = await scanner().scanOnce(root: root, now: now)
        XCTAssertEqual(totalInput(result), 20)
        let store = UsageStore.load(from: stateURL)
        XCTAssertEqual(store.cursors[file.standardizedFileURL.path]?.offset, UInt64(try Data(contentsOf: file).count))
    }

    func testRecreatedFileIsReadFromStartWithoutDoubleCount() async throws {
        let file = try logFile()
        let scanner = scanner()
        try append(line(id: "1") + "\n" + line(id: "2") + "\n", to: file)
        _ = await scanner.scanOnce(root: root, now: now)

        try FileManager.default.removeItem(at: file)
        try append(line(id: "1") + "\n" + line(id: "3") + "\n", to: file)
        let result = await scanner.scanOnce(root: root, now: now)
        XCTAssertEqual(totalInput(result), 30)
    }

    func testShrunkFileIsReadFromStart() async throws {
        let file = try logFile()
        let scanner = scanner()
        try append(line(id: "1") + "\n" + line(id: "2") + "\n", to: file)
        _ = await scanner.scanOnce(root: root, now: now)

        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.close()
        try append(line(id: "3") + "\n", to: file)
        let result = await scanner.scanOnce(root: root, now: now)
        XCTAssertEqual(totalInput(result), 30)
    }

    func testHistorySurvivesLogDeletion() async throws {
        let file = try logFile()
        try append(line(id: "1") + "\n", to: file)
        _ = await scanner().scanOnce(root: root, now: now)

        try FileManager.default.removeItem(at: file)
        let result = await scanner().scanOnce(root: root, now: now)
        XCTAssertEqual(totalInput(result), 10)
        XCTAssertFalse(result.logsFound)
    }

    func testOldKeysArePrunedButRereadDoesNotDoubleCount() async throws {
        let file = try logFile()
        let scanner = scanner()
        try append(line(id: "old", time: "2026-09-01T00:00:00.000Z") + "\n", to: file)
        var result = await scanner.scanOnce(root: root, now: now)
        XCTAssertEqual(totalInput(result), 10)
        XCTAssertTrue(UsageStore.load(from: stateURL).seen.isEmpty)

        try FileManager.default.removeItem(at: file)
        try append(line(id: "old", time: "2026-09-01T00:00:00.000Z") + "\n", to: file)
        result = await scanner.scanOnce(root: root, now: now)
        XCTAssertEqual(totalInput(result), 10)
    }

    func testSubagentLogsUseFirstPathComponentAsProject() async throws {
        try append(line(id: "1") + "\n", to: try logFile("proj-a/session/subagents/agent.jsonl"))
        let result = await scanner().scanOnce(root: root, now: now)
        XCTAssertEqual(result.rows.first?.project, "proj-a")
    }

    func testHaikuLongPromptIsCountedSeparately() async throws {
        let cacheHeavy = #"{"timestamp":"2026-11-10T01:00:00.000Z","requestId":"req_c","message":{"id":"msg_c","model":"claude-haiku-5-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":100000}}}"#
        let lines = [
            line(id: "a", input: 100_000, model: "claude-haiku-5-5"),
            cacheHeavy,
            line(id: "o", input: 200_000, model: "claude-opus-5-5"),
        ]
        try append(lines.joined(separator: "\n") + "\n", to: try logFile())
        let result = await scanner().scanOnce(root: root, now: now)
        XCTAssertEqual(Set(result.rows.map(\.model)), ["claude-haiku-5-5", "claude-haiku-5-5-over-100k", "claude-opus-5-5"])
        XCTAssertEqual(result.rows.first { $0.model == "claude-haiku-5-5" }?.tokens.input, 100_000, "ちょうど10万は通常単価")
        XCTAssertEqual(result.rows.first { $0.model == "claude-haiku-5-5-over-100k" }?.tokens.cacheRead, 100_000, "キャッシュ読込も数える")
    }

    func testDayUsesLocalTimeZone() async throws {
        try append(line(id: "1", time: "2026-11-09T16:00:00.000Z") + "\n", to: try logFile())
        let result = await scanner().scanOnce(root: root, now: now)
        XCTAssertEqual(result.rows.first?.day, "2026-11-10", "JSTでは翌日の1時")
    }

    func testWarnsWhenLogsGrowWithoutUsage() async throws {
        let file = try logFile()
        let scanner = scanner()
        try append(#"{"type":"user","new_format":true}"# + "\n", to: file)
        var result = await scanner.scanOnce(root: root, now: now)
        XCTAssertFalse(result.logFormatWarning)

        try append(#"{"type":"user","new_format":true}"# + "\n", to: file)
        result = await scanner.scanOnce(root: root, now: now.addingTimeInterval(3700))
        XCTAssertTrue(result.logFormatWarning)

        try append(line(id: "1") + "\n", to: file)
        result = await scanner.scanOnce(root: root, now: now.addingTimeInterval(3800))
        XCTAssertFalse(result.logFormatWarning)
    }
}
