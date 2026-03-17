import Charts
import SwiftUI

struct PowerTrendChart: View {
    let points: [PowerChartPoint]
    let metric: ChartMetric
    let range: ChartTimeRange

    var body: some View {
        if points.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 20))
                    .foregroundStyle(PowerMonitorTheme.muted)
                Text(metric.emptyStateTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PowerMonitorTheme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 148)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Chart {
                ForEach(points) { point in
                    if metric == .batteryLevel {
                        BarMark(
                            x: .value("Time", point.timestamp),
                            y: .value(metric.title, point.value),
                            width: .fixed(range == .tenDays ? 8 : 6)
                        )
                        .foregroundStyle(point.isCharging ? PowerMonitorTheme.green.gradient : PowerMonitorTheme.accent.gradient)
                        .cornerRadius(3)
                    } else {
                        AreaMark(
                            x: .value("Time", point.timestamp),
                            y: .value(metric.title, point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [PowerMonitorTheme.accent.opacity(0.28), PowerMonitorTheme.accent.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value(metric.title, point.value)
                        )
                        .foregroundStyle(PowerMonitorTheme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
                        .foregroundStyle(Color.white.opacity(0.12))
                    AxisTick(stroke: StrokeStyle(lineWidth: 0))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(axisLabel(number))
                                .foregroundStyle(PowerMonitorTheme.muted)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisStrideValues) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
                        .foregroundStyle(Color.white.opacity(0.08))
                    AxisTick(stroke: StrokeStyle(lineWidth: 0))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(xAxisLabel(date))
                                .foregroundStyle(PowerMonitorTheme.muted)
                        }
                    }
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxisLabel(position: .bottom, alignment: .trailing) {
                Text(range.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(PowerMonitorTheme.muted)
            }
            .chartPlotStyle { plot in
                plot
                    .frame(height: 118)
                    .background(Color.white.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        if metric == .batteryLevel {
            return 0...100
        }

        if minimum == maximum {
            return 0...(maximum * 1.2 + 1)
        }

        let padding = (maximum - minimum) * 0.18
        return max(0, minimum - padding)...(maximum + padding)
    }

    private var xAxisStrideValues: [Date] {
        guard let first = points.first?.timestamp, let last = points.last?.timestamp else {
            return []
        }

        let ticks = 4
        let interval = last.timeIntervalSince(first) / Double(max(ticks - 1, 1))
        return (0..<ticks).map { first.addingTimeInterval(Double($0) * interval) }
    }

    private func xAxisLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")

        switch range {
        case .oneHour:
            formatter.dateFormat = "HH:mm"
        case .twentyFourHours:
            formatter.dateFormat = "HH"
        case .tenDays:
            formatter.dateFormat = "M/d"
        }

        return formatter.string(from: date)
    }

    private func axisLabel(_ value: Double) -> String {
        switch metric {
        case .power:
            return String(format: "%.0fW", value)
        case .batteryLevel:
            return String(format: "%.0f%%", value)
        case .chargeRate:
            return String(format: "%.1fA", value)
        }
    }
}
