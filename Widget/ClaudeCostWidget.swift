import SwiftUI
import WidgetKit

enum WidgetContent {
    case placeholder
    case missing
    case snapshot(Snapshot)
}

struct CostEntry: TimelineEntry {
    let date: Date
    let content: WidgetContent
}

struct CostProvider: TimelineProvider {
    private static let sample = Snapshot(
        generatedAt: Date(),
        currency: .init(jpyRate: 150, show: .both),
        regionalPricing: true,
        today: .init(date: "2026-11-10", usd: 3.42),
        month: .init(month: "2026-11", usd: 41.80, forecastUsd: 125.40),
        days: (1...14).map { .init(date: String(format: "2026-11-%02d", $0), usd: Double(($0 * 7) % 5) + 1) },
        topModels: [
            .init(model: "opus-5-5", usd: 35.20),
            .init(model: "sonnet-5-5", usd: 6.60),
        ],
        unpricedModels: [],
        logsFound: true)

    func placeholder(in context: Context) -> CostEntry {
        CostEntry(date: Date(), content: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (CostEntry) -> Void) {
        if let snapshot = SharedStore.readSnapshot() {
            completion(CostEntry(date: Date(), content: .snapshot(snapshot)))
        } else if context.isPreview {
            completion(CostEntry(date: Date(), content: .snapshot(Self.sample)))
        } else {
            completion(CostEntry(date: Date(), content: .missing))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CostEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        // 通常の更新は本体からの reloadTimelines で行い、これは保険
        let refresh = Timeline<CostEntry>.self
        let after = now.addingTimeInterval(15 * 60)

        guard let snapshot = SharedStore.readSnapshot() else {
            completion(refresh.init(entries: [CostEntry(date: now, content: .missing)], policy: .after(after)))
            return
        }
        var entries = [CostEntry(date: now, content: .snapshot(snapshot))]
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            entries.append(CostEntry(date: midnight, content: .snapshot(snapshot.rolledOver(to: midnight, calendar: calendar))))
        }
        completion(refresh.init(entries: entries, policy: .after(after)))
    }
}

struct CostEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CostEntry

    var body: some View {
        Group {
            switch entry.content {
            case .placeholder:
                sizedView(CostProvider.placeholderSnapshot)
                    .redacted(reason: .placeholder)
            case .missing:
                message("アプリを起動してください")
            case .snapshot(let snapshot):
                if snapshot.logsFound {
                    sizedView(snapshot)
                } else {
                    message("Claude Codeのログが見つかりません")
                }
            }
        }
        .containerBackground(for: .widget) {
            Color(nsColor: .windowBackgroundColor)
        }
        .widgetURL(URL(string: "claudecost://open"))
    }

    @ViewBuilder
    private func sizedView(_ snapshot: Snapshot) -> some View {
        switch family {
        case .systemLarge: LargeView(snapshot: snapshot, entryDate: entry.date)
        case .systemMedium: MediumView(snapshot: snapshot, entryDate: entry.date)
        default: SmallView(snapshot: snapshot, entryDate: entry.date)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension CostProvider {
    static var placeholderSnapshot: Snapshot { sample }
}

struct ClaudeCostWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.widgetKind, provider: CostProvider()) { entry in
            CostEntryView(entry: entry)
        }
        .configurationDisplayName("Claude Code 費用")
        .description("Claude Codeの今日と今月の推計額を表示します。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ClaudeCostWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudeCostWidget()
    }
}
