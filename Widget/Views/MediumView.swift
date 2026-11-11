import Charts
import SwiftUI

struct MediumView: View {
    let snapshot: Snapshot
    let entryDate: Date

    var body: some View {
        HStack(spacing: 14) {
            SummaryColumn(snapshot: snapshot, entryDate: entryDate)
                .frame(maxWidth: 130)
            TrendColumn(snapshot: snapshot)
        }
    }
}

/// 直近14日の棒グラフと月末見込み。
struct TrendColumn: View {
    let snapshot: Snapshot

    var body: some View {
        let forecast = Format.amounts(usd: snapshot.month.forecastUsd, currency: snapshot.currency)

        VStack(alignment: .leading, spacing: 4) {
            Chart(snapshot.days, id: \.date) { day in
                BarMark(x: .value("日付", day.date), y: .value("USD", day.usd))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .widgetAccentable()

            HStack(spacing: 4) {
                Text("月末見込み").foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(forecast.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .font(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }
}
