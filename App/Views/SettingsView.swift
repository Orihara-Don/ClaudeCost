import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Picker("メニューバーに表示するもの", selection: $model.settings.menuBarMode) {
                ForEach(MenuBarMode.allCases) { Text($0.label).tag($0) }
            }
            Picker("通貨の表示", selection: $model.settings.currency) {
                ForEach(CurrencyDisplay.allCases) { Text($0.label).tag($0) }
            }
            TextField("USD/JPYレート", value: $model.settings.jpyRate, format: .number)
            Toggle("リージョナル料金（×1.1）", isOn: $model.settings.regionalPricing)
            TextField("月の予算（USD）", value: $model.settings.monthlyBudget, format: .number, prompt: Text("未設定"))
            Toggle("ログイン時に起動", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.launchAtLogin = $0 }))
            if let error = model.loginItemError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            LabeledContent("ログの場所") {
                HStack {
                    Text(model.settings.projectsURL.path)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Button("選択…", action: chooseLogFolder)
                    Button("既定に戻す") { model.settings.customLogPath = "" }
                        .disabled(model.settings.customLogPath.isEmpty)
                }
            }
            LabeledContent("単価表") {
                Button("prices.json を開く") { model.openPrices() }
            }
            LabeledContent("アプリ") {
                Button("ClaudeCost を終了") { AppDelegate.quit() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseLogFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = model.settings.projectsURL
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.customLogPath = url.path
        }
    }
}
