import SwiftUI

struct SmallView: View {
    let snapshot: Snapshot
    let entryDate: Date

    var body: some View {
        SummaryColumn(snapshot: snapshot, entryDate: entryDate)
    }
}

/// 小サイズの内容。中・大サイズの左側でも使う。
struct SummaryColumn: View {
    private static let staleInterval: TimeInterval = 30 * 60

    let snapshot: Snapshot
    let entryDate: Date

    private var isStale: Bool {
        entryDate.timeIntervalSince(snapshot.generatedAt) >= Self.staleInterval
    }

    var body: some View {
        let today = Format.amounts(usd: snapshot.today.usd, currency: snapshot.currency)
        let month = Format.amounts(usd: snapshot.month.usd, currency: snapshot.currency)

        VStack(alignment: .leading, spacing: 2) {
            Text("今日").font(.caption2).foregroundStyle(.secondary)
            Text(today.primary)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .widgetAccentable()
            if let secondary = today.secondary {
                Text(secondary)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 2)
            HStack(spacing: 4) {
                Text("今月").foregroundStyle(.secondary)
                Text(month.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .font(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(isStale ? "本体アプリが停止中" : "推計 ・ \(Format.time(snapshot.generatedAt))")
                .font(.system(size: 10))
                .foregroundStyle(isStale ? Color.orange : Color.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
