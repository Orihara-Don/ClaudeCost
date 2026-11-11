import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var panel: PanelData?
    @Published private(set) var progress: ScanProgress?
    @Published private(set) var isScanning = false
    @Published private(set) var logFormatWarning = false
    @Published private(set) var pricesError: String?
    @Published var loginItemError: String?

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            if settings.jpyRate <= 0 { settings.jpyRate = oldValue.jpyRate }
            settings.save(to: SharedStore.defaults)
            if settings.projectsURL != oldValue.projectsURL {
                watcher.start(path: settings.projectsURL.path)
                refresh()
            }
            rebuild(force: true)
        }
    }

    private var scanner: LogScanner!
    private var watcher: LogWatcher!
    private let publisher = SnapshotPublisher()
    private var lastResult: ScanResult?

    private init() {
        settings = AppSettings.load(from: SharedStore.defaults)
        scanner = LogScanner(
            stateURL: AppPaths.state,
            onProgress: { [weak self] value in await self?.updateProgress(value) },
            onResult: { [weak self] result in await self?.apply(result) })
        watcher = LogWatcher(
            onChange: { [weak self] in self?.refresh() },
            onDayChange: { [weak self] in
                self?.rebuild(force: true)
                self?.refresh()
            })
    }

    func start() {
        settings.save(to: SharedStore.defaults)
        watcher.start(path: settings.projectsURL.path)
        refresh()
    }

    func refresh() {
        isScanning = true
        let root = settings.projectsURL
        Task { await scanner.requestScan(root: root) }
    }

    private func updateProgress(_ value: ScanProgress?) {
        progress = value
    }

    private func apply(_ result: ScanResult) {
        lastResult = result
        logFormatWarning = result.logFormatWarning
        isScanning = false
        rebuild(force: false)
    }

    private func rebuild(force: Bool) {
        guard let result = lastResult else { return }
        let prices = PriceTable.loadMerged()
        pricesError = prices.error
        let data = SnapshotBuilder.build(
            rows: result.rows,
            prices: prices.table,
            options: BuildOptions(
                jpyRate: settings.jpyRate,
                show: settings.currency,
                regionalPricing: settings.regionalPricing),
            logsFound: result.logsFound,
            now: Date())
        panel = data
        publisher.publish(data.snapshot, force: force)
    }

    // MARK: - 表示

    var isInitialScan: Bool { panel == nil }

    /// 月末見込みが予算を超えているか。
    var isOverBudget: Bool {
        guard let budget = settings.monthlyBudget, let panel else { return false }
        return panel.snapshot.month.forecastUsd > budget
    }

    /// メニューバーの金額。「両方」のときは幅を取らないようUSDだけを出す。
    var menuBarTitle: String? {
        guard let snapshot = panel?.snapshot else { return nil }
        let usd: Double
        switch settings.menuBarMode {
        case .today: usd = snapshot.today.usd
        case .month: usd = snapshot.month.usd
        case .iconOnly: return nil
        }
        return settings.currency == .jpy
            ? Format.jpy(usd: usd, rate: settings.jpyRate)
            : Format.usd(usd)
    }

    func amounts(_ usd: Double) -> (primary: String, secondary: String?) {
        Format.amounts(usd: usd, rate: settings.jpyRate, show: settings.currency)
    }

    // MARK: - ログイン時の起動

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                loginItemError = nil
            } catch {
                loginItemError = error.localizedDescription
            }
        }
    }

    // MARK: - 単価表

    func openPrices() {
        let url = AppPaths.userPrices
        if !FileManager.default.fileExists(atPath: url.path),
           let bundled = Bundle.main.url(forResource: "prices", withExtension: "json") {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: bundled, to: url)
        }
        NSWorkspace.shared.open(url)
    }
}
