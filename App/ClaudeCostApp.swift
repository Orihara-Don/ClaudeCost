import AppKit
import SwiftUI

@main
struct ClaudeCostApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        // 表示・非表示はmacOSのシステム設定に任せる。isInserted を使うと、macOS側の表示状態と
        // 更新し合って無限ループになることがあった。
        MenuBarExtra {
            PanelView()
                .environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
        askLaunchAtLoginOnce()
    }

    /// ウィジェットをタップしたときの claudecost://open
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "claudecost" }) else { return }
        showPanelOrSettings()
    }

    private static var userRequestedQuit = false

    static func quit() {
        userRequestedQuit = true
        NSApp.terminate(nil)
    }

    /// メニューバーから隠されても集計を続けるため、利用者の「終了」と
    /// ログアウトなどの外部からの要求（Apple Event あり）以外では終了しない。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppDelegate.userRequestedQuit || NSAppleEventManager.shared().currentAppleEvent != nil {
            return .terminateNow
        }
        NSLog("ClaudeCost: 利用者の操作ではない終了要求を取り消しました")
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("ClaudeCost: 終了します")
    }

    /// 起動中のアプリをもう一度開いたとき。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanelOrSettings()
        return false
    }

    /// macOSの設定でメニューバーから隠されていてパネルを開けないときは、設定を開く。
    private func showPanelOrSettings() {
        if !MenuBarPanel.open() {
            SettingsWindow.shared.show()
        }
    }

    private func askLaunchAtLoginOnce() {
        let defaults = SharedStore.defaults
        guard !defaults.bool(forKey: AppSettings.didAskLaunchAtLoginKey) else { return }
        defaults.set(true, forKey: AppSettings.didAskLaunchAtLoginKey)

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "ログイン時に起動しますか？"
        alert.informativeText = "起動しておくと、メニューバーとウィジェットの金額が常に更新されます。設定からいつでも変更できます。"
        alert.addButton(withTitle: "起動する")
        alert.addButton(withTitle: "起動しない")
        if alert.runModal() == .alertFirstButtonReturn {
            AppModel.shared.launchAtLogin = true
        }
    }
}

enum MenuBarPanel {
    /// MenuBarExtra を開く公開APIが無いため、ステータス項目のボタンを押して開く。
    @MainActor
    @discardableResult
    static func open() -> Bool {
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
            if window.isVisible, let button = findButton(in: window.contentView) {
                button.performClick(nil)
                return true
            }
        }
        return false
    }

    @MainActor
    private static func findButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton { return button }
        for child in view.subviews {
            if let found = findButton(in: child) { return found }
        }
        return nil
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.isInitialScan {
            Text("集計中…")
        } else if let title = model.menuBarTitle {
            if model.isOverBudget {
                // ステータス項目の Text は単色で描かれるため、警告色は画像にして出す
                Image(nsImage: ColoredMenuBarText.image(title, color: .systemRed))
            } else {
                Text(title).monospacedDigit()
            }
        } else {
            Image(systemName: "dollarsign.circle")
        }
    }
}

enum ColoredMenuBarText {
    static func image(_ text: String, color: NSColor) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: color,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let image = NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)), flipped: false) { rect in
            string.draw(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }
}

@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    /// メニューバー常駐アプリでも前面に出るよう、AppKit のウィンドウで開く。
    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(AppModel.shared))
            let created = NSWindow(contentViewController: host)
            created.title = "ClaudeCost の設定"
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
