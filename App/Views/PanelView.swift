import AppKit
import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsWeeks = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let data = model.panel {
                content(data)
            } else {
                scanningView
            }
            buttons
        }
        .padding(14)
        .frame(width: 320)
    }

    private var scanningView: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            if let progress = model.progress {
                Text("集計中… \(progress.done)/\(progress.total) ファイル")
            } else {
                Text("集計中…")
            }
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func content(_ data: PanelData) -> some View {
        let snapshot = data.snapshot

        HStack(alignment: .top) {
            amountBlock(title: "今日", usd: snapshot.today.usd, size: 30)
            Spacer()
            amountBlock(title: "今週", usd: data.weeks.last?.usd ?? 0, size: 18)
        }

        HStack(alignment: .top) {
            amountBlock(title: "今月", usd: snapshot.month.usd, size: 18)
            Spacer()
            amountBlock(title: "月末見込み", usd: snapshot.month.forecastUsd, size: 18)
                .foregroundStyle(model.isOverBudget ? Color.red : Color.primary)
        }

        Divider()
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(showsWeeks ? "直近8週" : "直近14日").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("期間", selection: $showsWeeks) {
                    Text("日別").tag(false)
                    Text("週別").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
            }
            DailyChart(
                bars: showsWeeks ? data.weeks : snapshot.days,
                isWeekly: showsWeeks,
                amount: { usd in
                    let text = model.amounts(usd)
                    return [text.primary, text.secondary].compactMap { $0 }.joined(separator: "  ")
                })
        }

        if !data.models.isEmpty {
            Divider()
            section("モデル別（今月）") {
                ForEach(data.models) { row in
                    breakdownRow(
                        name: Format.modelName(row.model),
                        value: row.usd.map { model.amounts($0).primary }
                            ?? "単価未登録 \(Format.tokens(row.tokens)) tokens")
                }
            }
        }

        if !data.projects.isEmpty {
            Divider()
            section("プロジェクト別（今月・上位5件）") {
                ForEach(data.projects) { row in
                    breakdownRow(
                        name: ProjectName.display(row.project),
                        value: model.amounts(row.usd).primary)
                }
            }
        }

        warnings(data)

        Text("最終更新 \(Format.time(snapshot.generatedAt)) ・ 金額は推計値です")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func warnings(_ data: PanelData) -> some View {
        if !data.snapshot.logsFound {
            warning("Claude Codeのログが見つかりません")
        }
        if !data.snapshot.unpricedModels.isEmpty {
            let names = data.snapshot.unpricedModels.map(Format.modelName).joined(separator: ", ")
            warning("単価未登録のため金額に含まれていません: \(names)")
        }
        if model.logFormatWarning {
            warning("ログは増えていますが利用量を読み取れません。ログ形式が変わった可能性があります")
        }
        if let error = model.pricesError {
            warning(error)
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func amountBlock(title: String, usd: Double, size: CGFloat) -> some View {
        let text = model.amounts(usd)
        return VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text.primary)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if let secondary = text.secondary {
                Text(secondary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func breakdownRow(name: String, value: String) -> some View {
        HStack {
            Text(name).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }

    private var buttons: some View {
        HStack {
            Button {
                model.refresh()
            } label: {
                Label("今すぐ更新", systemImage: "arrow.clockwise")
            }
            .disabled(model.isScanning)
            Spacer()
            Button("設定") { SettingsWindow.shared.show() }
            Button("終了") { AppDelegate.quit() }
        }
        .controlSize(.small)
    }
}

enum ProjectName {
    /// "-Users-me-develop-foo" のホーム部分を省いて表示する。
    static func display(_ directory: String) -> String {
        let home = NSHomeDirectory()
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        guard directory.hasPrefix(home + "-") else { return directory }
        return String(directory.dropFirst(home.count + 1))
    }
}
