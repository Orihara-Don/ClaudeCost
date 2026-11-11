import SwiftUI

struct LargeView: View {
    let snapshot: Snapshot
    let entryDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MediumView(snapshot: snapshot, entryDate: entryDate)
                .frame(maxHeight: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("モデル別（今月）").font(.caption).foregroundStyle(.secondary)
                ForEach(snapshot.topModels.prefix(4), id: \.model) { row in
                    HStack {
                        Text(row.model).lineLimit(1)
                        Spacer()
                        Text(Format.amounts(usd: row.usd, currency: snapshot.currency).primary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .font(.callout)
                }
            }
        }
    }
}
