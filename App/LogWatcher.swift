import AppKit
import CoreServices

/// 更新のきっかけ（FSEvents、定期実行、スリープ復帰、日付の変化）をまとめる。
final class LogWatcher {
    private static let debounce: TimeInterval = 5
    private static let period: TimeInterval = 300

    private var stream: FSEventStreamRef?
    private var path = ""
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    private let onChange: () -> Void
    private let onDayChange: () -> Void

    init(onChange: @escaping () -> Void, onDayChange: @escaping () -> Void) {
        self.onChange = onChange
        self.onDayChange = onDayChange
    }

    deinit {
        stopStream()
        timer?.invalidate()
        observers.forEach { $0.0.removeObserver($0.1) }
    }

    func start(path: String) {
        self.path = path
        stopStream()
        startStreamIfPossible()

        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: LogWatcher.period, repeats: true) { [weak self] _ in
            // 起動時にログのディレクトリが無かった場合も、ここで監視を始める
            self?.startStreamIfPossible()
            self?.onChange()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.onChange() }))
        let center = NotificationCenter.default
        observers.append((center, center.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.onDayChange() }))
    }

    /// 変更から5秒後にまとめて実行する。連続して書かれても待ち続けない。
    fileprivate func scheduleChange() {
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.pending = nil
            self?.onChange()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + LogWatcher.debounce, execute: work)
    }

    private func startStreamIfPossible() {
        guard stream == nil, FileManager.default.fileExists(atPath: path) else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<LogWatcher>.fromOpaque(info).takeUnretainedValue().scheduleChange()
        }
        guard let created = FSEventStreamCreate(
            nil, callback, &context, [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)
        ) else { return }
        FSEventStreamSetDispatchQueue(created, .main)
        FSEventStreamStart(created)
        stream = created
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
