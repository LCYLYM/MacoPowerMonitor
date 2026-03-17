import SwiftUI

struct RecentActivityGrid: View {
    let snapshots: [PowerSnapshot]

    var body: some View {
        let values = snapshots.compactMap(\.preferredPowerWatts)
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 1

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 20), spacing: 4) {
            ForEach(Array(snapshots.enumerated()), id: \.offset) { _, snapshot in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color(for: snapshot.preferredPowerWatts, minimum: minimum, maximum: maximum))
                    .frame(height: 12)
            }
        }
    }

    private func color(for value: Double?, minimum: Double, maximum: Double) -> Color {
        guard let value else {
            return Color.white.opacity(0.08)
        }

        let range = max(maximum - minimum, 0.1)
        let normalized = (value - minimum) / range
        return PowerMonitorTheme.accent.opacity(0.25 + normalized * 0.75)
    }
}
