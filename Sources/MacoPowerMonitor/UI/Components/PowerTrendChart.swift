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

    /// The battery chart always carries its own time scale so its percentage
    /// columns remain readable when other metric charts are visible above or
    /// below it. Other charts keep the shared scale on the final chart.
    private var showsTimeAxis: Bool {
        metric == .batteryLevel || showsXAxis
    }

    var body: some View {
        if visibleSeries.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 16))
                    .foregroundStyle(PowerMonitorTheme.muted)
                    .help("\(metric.title)趋势图暂缺足够的历史样本。")
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
                        showsTimeAxis: showsTimeAxis,
                        size: geometry.size
                    )
                }
                .frame(height: chartHeight)
            }
        }
    }

    private var chartHeight: CGFloat {
        switch metric {
        case .batteryLevel:
            return 94
        case .power, .chargeRate:
            return showsTimeAxis ? 106 : 92
        }
    }

    private var chartBackground: some ShapeStyle {
        Color.white.opacity(0.045)
    }
}

private struct CompactHistoryCanvas: View {
    let metric: ChartMetric
    let series: [PowerChartSeries]
    let range: ChartTimeRange
    let showsTimeAxis: Bool
    let size: CGSize
    private let referenceDate = Date()

    private var chartRect: CGRect {
        let bottomInset: CGFloat = showsTimeAxis ? 28 : 14
        return CGRect(x: 28, y: 8, width: max(size.width - 36, 10), height: max(size.height - bottomInset, 10))
    }

    /// Keep every chart aligned to the selected time window instead of
    /// stretching the currently available samples across the entire width.
    private var timeDomain: DateInterval {
        DateInterval(
            start: referenceDate.addingTimeInterval(-range.interval),
            end: referenceDate
        )
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

            if showsTimeAxis {
                xAxisLabelsLayer
            }
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
                let segments = pointSegmentsForSeries(series)
                ForEach(Array(segments.enumerated()), id: \.offset) { _, points in
                    if points.count >= 2 {
                        HistoryAreaShape(points: points, baselineY: chartRect.maxY)
                            .fill(style(for: series.id).fillGradient)

                        HistoryLineShape(points: points)
                            .stroke(style(for: series.id).lineColor, style: style(for: series.id).strokeStyle)
                    }
                }

                if let lastPoint = segments.last?.last {
                    Circle()
                        .fill(style(for: series.id).lineColor)
                        .frame(width: 8, height: 8)
                        .position(lastPoint)
                }
            }
        }
    }

    private var batteryBarsLayer: some View {
        let primarySeries = series.first(where: { $0.id == .batteryLevel }) ?? series.first
        let points = primarySeries.map(pointsForSeries) ?? []
        let bars = compactBatteryBars(from: points)
        let slotWidth = chartRect.width / CGFloat(max(min(points.count, Self.maximumBatteryBarCount), 1))
        let barWidth = min(max(slotWidth * 0.58, 3.5), 8)

        return ZStack {
            ForEach(bars) { bar in
                let y = bar.point.y
                let height = chartRect.maxY - y

                RoundedRectangle(cornerRadius: min(barWidth / 2, 3.5))
                    .fill(bar.isLatest ? PowerMonitorTheme.green : PowerMonitorTheme.accent)
                    .frame(width: barWidth, height: max(height, 2))
                    .position(x: bar.point.x, y: y + height / 2)
            }
        }
    }

    /// The store retains many samples per range. Showing every sample turns a
    /// bar chart into a solid comb, so render at most 48 time-based columns.
    /// Each visual column is the average height of its samples and stays in
    /// chronological position on the chart.
    private func compactBatteryBars(from points: [CGPoint]) -> [BatteryBar] {
        guard points.count > Self.maximumBatteryBarCount else {
            return points.enumerated().map { index, point in
                BatteryBar(id: index, point: point, isLatest: index == points.indices.last)
            }
        }

        var sums = Array(repeating: CGFloat.zero, count: Self.maximumBatteryBarCount)
        var counts = Array(repeating: 0, count: Self.maximumBatteryBarCount)

        for point in points {
            let relativeX = (point.x - chartRect.minX) / max(chartRect.width, 1)
            let index = min(
                max(Int(relativeX * CGFloat(Self.maximumBatteryBarCount)), 0),
                Self.maximumBatteryBarCount - 1
            )
            sums[index] += point.y
            counts[index] += 1
        }

        return (0..<Self.maximumBatteryBarCount).compactMap { index in
            guard counts[index] > 0 else { return nil }

            let x = chartRect.minX + chartRect.width * (CGFloat(index) + 0.5) / CGFloat(Self.maximumBatteryBarCount)
            let point = CGPoint(x: x, y: sums[index] / CGFloat(counts[index]))
            return BatteryBar(
                id: index,
                point: point,
                isLatest: index == Self.maximumBatteryBarCount - 1
            )
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

    private var xAxisLabelsLayer: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(xAxisTicks.enumerated()), id: \.offset) { index, timestamp in
                let isFirst = index == 0
                let isLast = index == xAxisTicks.count - 1
                let gridX = chartRect.minX + chartRect.width * CGFloat(index) / CGFloat(max(xAxisTicks.count - 1, 1))
                let labelX = gridX + (isFirst ? Self.xAxisLabelWidth / 2 : isLast ? -Self.xAxisLabelWidth / 2 : 0)

                Text(xAxisFormatter.string(from: timestamp))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(PowerMonitorTheme.muted)
                    .frame(
                        width: Self.xAxisLabelWidth,
                        alignment: isFirst ? .leading : isLast ? .trailing : .center
                    )
                    .position(
                        x: labelX,
                        y: chartRect.maxY + 10
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private var xAxisTicks: [Date] {
        let tickCount = 4
        let interval = timeDomain.duration / Double(tickCount - 1)
        return (0..<tickCount).map { index in
            timeDomain.start.addingTimeInterval(Double(index) * interval)
        }
    }

    private var xAxisFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")

        switch range {
        case .oneHour:
            formatter.dateFormat = "HH:mm"
        case .twentyFourHours:
            formatter.dateFormat = "HH:mm"
        case .tenDays:
            formatter.dateFormat = "M/d"
        }

        return formatter
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

    private func pointSegmentsForSeries(_ series: PowerChartSeries) -> [[CGPoint]] {
        let sortedPoints = series.points.sorted { $0.timestamp < $1.timestamp }
        guard !sortedPoints.isEmpty else { return [] }

        let maximumContinuousGap = (range.interval / Double(range.bucketCount)) * 1.5
        var segments: [[PowerChartPoint]] = [[sortedPoints[0]]]
        for point in sortedPoints.dropFirst() {
            if let previous = segments.last?.last,
               point.timestamp.timeIntervalSince(previous.timestamp) > maximumContinuousGap {
                segments.append([point])
            } else {
                segments[segments.count - 1].append(point)
            }
        }

        return segments.map { points in
            points.map { point in
                CGPoint(
                    x: xPosition(for: point.timestamp),
                    y: yPosition(for: point.value)
                )
            }
        }
    }

    private func xPosition(for timestamp: Date) -> CGFloat {
        let offset = timestamp.timeIntervalSince(timeDomain.start)
        let normalized = min(max(offset / max(timeDomain.duration, 1), 0), 1)
        return chartRect.minX + chartRect.width * CGFloat(normalized)
    }

    private func yPosition(for value: Double) -> CGFloat {
        let maximum = max(yAxisTicks.first?.value ?? 1, 1)
        let normalized = min(max(value / maximum, 0), 1)
        return chartRect.maxY - chartRect.height * CGFloat(normalized)
    }

    private func style(for kind: PowerChartSeriesKind) -> ChartSeriesStyle {
        switch kind {
        case .adapterInputPower:
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

    private static let maximumBatteryBarCount = 48
    private static let xAxisLabelWidth: CGFloat = 42
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

private struct BatteryBar: Identifiable {
    let id: Int
    let point: CGPoint
    let isLatest: Bool
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
