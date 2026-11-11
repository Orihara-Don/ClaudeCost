import Charts
import SwiftUI

/// 日別・週別の棒グラフ。マウスを乗せた棒の金額を吹き出しで出す。
struct DailyChart: View {
    let bars: [Snapshot.Day]
    let isWeekly: Bool
    let amount: (Double) -> String

    @State private var hoveredDate: String?

    private var hoveredBar: Snapshot.Day? {
        bars.first { $0.date == hoveredDate }
    }

    /// 文字が重ならないよう、最新の棒から数えて間引いた位置にだけ日付を出す。
    private var tickDates: [String] {
        let step = isWeekly ? 2 : 3
        return stride(from: bars.count - 1, through: 0, by: -step).reversed().map { bars[$0].date }
    }

    var body: some View {
        Chart {
            ForEach(bars, id: \.date) { bar in
                BarMark(
                    x: .value("期間", bar.date),
                    y: .value("USD", bar.usd))
                    .opacity(hoveredBar == nil || hoveredBar == bar ? 1 : 0.45)
            }
            if let bar = hoveredBar {
                RuleMark(x: .value("期間", bar.date))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .annotation(
                        position: .top,
                        spacing: 2,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        tooltip(bar)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: tickDates) { value in
                AxisValueLabel(collisionResolution: .disabled) {
                    if let date = value.as(String.self) {
                        // 棒1本分の幅に収めようとして省略されるのを防ぐ
                        Text(Format.shortDay(date)).fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let usd = value.as(Double.self) {
                        Text("$\(usd, specifier: "%.0f")")
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            guard let frame = proxy.plotFrame else { return }
                            hoveredDate = proxy.value(atX: point.x - geometry[frame].minX, as: String.self)
                        case .ended:
                            hoveredDate = nil
                        }
                    }
            }
        }
        .frame(height: 110)
    }

    private func tooltip(_ bar: Snapshot.Day) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isWeekly ? "\(Format.shortDay(bar.date))の週" : Format.shortDay(bar.date))
                .foregroundStyle(.secondary)
            Text(amount(bar.usd))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
