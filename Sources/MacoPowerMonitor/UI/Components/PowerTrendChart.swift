import SwiftUI

struct PowerTrendChart: View {
    let series: [PowerChartSeries]
    let metric: ChartMetric
    let range: ChartTimeRange
    let showsXAxis: Bool

    private var visibleSeries: [PowerChartSeries] {
        series
            .map { PowerChartSeries(id: $0.id, points: $0.points.sorted { $0.timestamp < $1.timestamp }) }
            .filter(\.hasData)
    }

    var body: some View {
        if visibleSeries.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 16))
                    .foregroundStyle(PowerMonitorTheme.muted)
                Text(metric.emptyStateTitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PowerMonitorTheme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: chartHeight)
            .background(chartBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    CompactHistoryCanvas(
                        metric: metric,
                        series: visibleSeries,
                        range: range,
                        size: geometry.size
                    )
                }
                .frame(height: chartHeight)

                if showsXAxis {
                    HStack {
                        ForEach(xAxisLabels, id: \.self) { label in
                            Text(label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(PowerMonitorTheme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.leading, 28)
                    .padding(.trailing, 8)
                }
            }
        }
    }

    private var chartHeight: CGFloat {
        switch metric {
        case .batteryLevel:
            return 78
        case .power, .chargeRate:
            return 92
        }
    }

    private var chartBackground: some ShapeStyle {
        Color.white.opacity(0.045)
    }

    private var xAxisLabels: [String] {
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

        let points = visibleSeries.flatMap(\.points)
        guard let first = points.first?.timestamp, let last = points.last?.timestamp else {
            return []
        }

        let ticks = 4
        let interval = last.timeIntervalSince(first) / Double(max(ticks - 1, 1))
        return (0..<ticks).map { formatter.string(from: first.addingTimeInterval(Double($0) * interval)) }
    }
}

private struct CompactHistoryCanvas: View {
    let metric: ChartMetric
    let series: [PowerChartSeries]
    let range: ChartTimeRange
    let size: CGSize

    private var chartRect: CGRect {
        CGRect(x: 28, y: 8, width: max(size.width - 36, 10), height: max(size.height - 14, 10))
    }

    private var allPoints: [PowerChartPoint] {
        series.flatMap(\.points).sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.045))

            gridLayer

            if metric == .batteryLevel {
                batteryBarsLayer
            } else {
                historyLinesLayer
            }

            yAxisLabelsLayer
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var gridLayer: some View {
        Canvas { context, _ in
            let horizontalTicks = yAxisTicks
            for tick in horizontalTicks {
                let y = yPosition(for: tick.value)
                var path = Path()
                path.move(to: CGPoint(x: chartRect.minX, y: y))
                path.addLine(to: CGPoint(x: chartRect.maxX, y: y))
                context.stroke(
                    path,
                    with: .color(Color.white.opacity(tick.value == 0 ? 0.12 : 0.08)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 5])
                )
            }

            for index in 0..<4 {
                let x = chartRect.minX + chartRect.width * CGFloat(index) / 3.0
                var path = Path()
                path.move(to: CGPoint(x: x, y: chartRect.minY))
                path.addLine(to: CGPoint(x: x, y: chartRect.maxY))
                context.stroke(
                    path,
                    with: .color(Color.white.opacity(0.05)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 5])
                )
            }
        }
    }

    private var historyLinesLayer: some View {
        ZStack {
            ForEach(series) { series in
                let points = pointsForSeries(series)
                if points.count >= 2 {
                    HistoryAreaShape(points: points, baselineY: chartRect.maxY)
                        .fill(style(for: series.id).fillGradient)

                    HistoryLineShape(points: points)
                        .stroke(style(for: series.id).lineColor, style: style(for: series.id).strokeStyle)

                    if let lastPoint = points.last {
                        Circle()
                            .fill(style(for: series.id).lineColor)
                            .frame(width: 8, height: 8)
                            .position(lastPoint)
                    }
                }
            }
        }
    }

    private var batteryBarsLayer: some View {
        let primarySeries = series.first(where: { $0.id == .batteryLevel }) ?? series.first
        let points = primarySeries.map(pointsForSeries) ?? []
        let stepWidth = chartRect.width / CGFloat(max(points.count, 1))
        let barWidth = min(max(stepWidth * 0.54, 3), 7)

        return ZStack {
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                let x = chartRect.minX + stepWidth * (CGFloat(index) + 0.5)
                let y = point.y
                let height = chartRect.maxY - y

                RoundedRectangle(cornerRadius: 2)
                    .fill(index == points.count - 1 ? PowerMonitorTheme.green : PowerMonitorTheme.accent)
                    .frame(width: barWidth, height: max(height, 2))
                    .position(x: x, y: y + height / 2)
            }
        }
    }

    private var yAxisLabelsLayer: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(yAxisTicks) { tick in
                Text(tick.label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(PowerMonitorTheme.muted)
                    .frame(height: tick.slotHeight, alignment: .topLeading)
            }
        }
        .padding(.top, 4)
        .padding(.leading, 6)
    }

    private var yAxisTicks: [AxisTick] {
        let maxValue = max(series.flatMap(\.points).map(\.value).max() ?? 0, metric == .batteryLevel ? 100 : 1)

        switch metric {
        case .batteryLevel:
            return axisTicks(values: [100, 50, 0], labels: ["100%", "50%", "0%"])
        case .power:
            let capped = niceCeiling(for: maxValue, preferredSteps: [10, 20, 30])
            return axisTicks(
                values: [capped, capped * 2.0 / 3.0, capped / 3.0, 0],
                labels: [
                    formatYAxisValue(capped),
                    formatYAxisValue(capped * 2.0 / 3.0),
                    formatYAxisValue(capped / 3.0),
                    formatYAxisValue(0)
                ]
            )
        case .chargeRate:
            let capped = niceCeiling(for: maxValue, preferredSteps: [0.5, 1.0, 2.0])
            return axisTicks(
                values: [capped, capped * 2.0 / 3.0, capped / 3.0, 0],
                labels: [
                    formatYAxisValue(capped),
                    formatYAxisValue(capped * 2.0 / 3.0),
                    formatYAxisValue(capped / 3.0),
                    formatYAxisValue(0)
                ]
            )
        }
    }

    private func axisTicks(values: [Double], labels: [String]) -> [AxisTick] {
        let slotHeight = chartRect.height / CGFloat(max(values.count - 1, 1))
        return zip(values, labels).map { value, label in
            AxisTick(value: value, label: label, slotHeight: slotHeight)
        }
    }

    private func pointsForSeries(_ series: PowerChartSeries) -> [CGPoint] {
        series.points.map { point in
            CGPoint(
                x: xPosition(for: point.timestamp),
                y: yPosition(for: point.value)
            )
        }
    }

    private func xPosition(for timestamp: Date) -> CGFloat {
        guard let first = allPoints.first?.timestamp, let last = allPoints.last?.timestamp else {
            return chartRect.minX
        }

        let total = max(last.timeIntervalSince(first), 1)
        let offset = timestamp.timeIntervalSince(first)
        return chartRect.minX + chartRect.width * CGFloat(offset / total)
    }

    private func yPosition(for value: Double) -> CGFloat {
        let maximum = max(yAxisTicks.first?.value ?? 1, 1)
        let normalized = min(max(value / maximum, 0), 1)
        return chartRect.maxY - chartRect.height * CGFloat(normalized)
    }

    private func style(for kind: PowerChartSeriesKind) -> ChartSeriesStyle {
        switch kind {
        case .systemInputPower:
            return ChartSeriesStyle(
                lineColor: PowerMonitorTheme.accent,
                fillGradient: LinearGradient(colors: [PowerMonitorTheme.accent.opacity(0.20), PowerMonitorTheme.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom),
                strokeStyle: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round)
            )
        case .batteryDischargePower:
            return ChartSeriesStyle(
                lineColor: PowerMonitorTheme.orange,
                fillGradient: LinearGradient(colors: [PowerMonitorTheme.orange.opacity(0.12), PowerMonitorTheme.orange.opacity(0.02)], startPoint: .top, endPoint: .bottom),
                strokeStyle: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
            )
        case .batteryChargePower:
            return ChartSeriesStyle(
                lineColor: PowerMonitorTheme.green,
                fillGradient: LinearGradient(colors: [PowerMonitorTheme.green.opacity(0.12), PowerMonitorTheme.green.opacity(0.02)], startPoint: .top, endPoint: .bottom),
                strokeStyle: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
            )
        case .batteryDischargeCurrent:
            return ChartSeriesStyle(
                lineColor: PowerMonitorTheme.red,
                fillGradient: LinearGradient(colors: [PowerMonitorTheme.red.opacity(0.12), PowerMonitorTheme.red.opacity(0.02)], startPoint: .top, endPoint: .bottom),
                strokeStyle: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
            )
        case .batteryChargeCurrent:
            return ChartSeriesStyle(
                lineColor: PowerMonitorTheme.cyan,
                fillGradient: LinearGradient(colors: [PowerMonitorTheme.cyan.opacity(0.12), PowerMonitorTheme.cyan.opacity(0.02)], startPoint: .top, endPoint: .bottom),
                strokeStyle: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
            )
        case .batteryLevel:
            return ChartSeriesStyle(
                lineColor: PowerMonitorTheme.green,
                fillGradient: LinearGradient(colors: [PowerMonitorTheme.green.opacity(0.18), PowerMonitorTheme.green.opacity(0.02)], startPoint: .top, endPoint: .bottom),
                strokeStyle: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func formatYAxisValue(_ value: Double) -> String {
        switch metric {
        case .power:
            return String(format: "%.0fW", value)
        case .batteryLevel:
            return String(format: "%.0f%%", value)
        case .chargeRate:
            return String(format: "%.1fA", value)
        }
    }

    private func niceCeiling(for value: Double, preferredSteps: [Double]) -> Double {
        for step in preferredSteps {
            let candidate = ceil(value / step) * step
            if candidate > 0 {
                return candidate
            }
        }

        return ceil(value)
    }
}

private struct AxisTick: Identifiable {
    let value: Double
    let label: String
    let slotHeight: CGFloat

    var id: Double { value }
}

private struct ChartSeriesStyle {
    let lineColor: Color
    let fillGradient: LinearGradient
    let strokeStyle: StrokeStyle
}

private struct HistoryLineShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        guard let first = points.first else {
            return Path()
        }

        var path = Path()
        path.move(to: first)

        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        return path
    }
}

private struct HistoryAreaShape: Shape {
    let points: [CGPoint]
    let baselineY: CGFloat

    func path(in rect: CGRect) -> Path {
        guard let first = points.first, let last = points.last else {
            return Path()
        }

        var path = Path()
        path.move(to: CGPoint(x: first.x, y: baselineY))
        path.addLine(to: first)

        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        path.addLine(to: CGPoint(x: last.x, y: baselineY))
        path.closeSubpath()
        return path
    }
}
