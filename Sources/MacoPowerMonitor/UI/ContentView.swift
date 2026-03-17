import SwiftUI

struct ContentView: View {
    @ObservedObject var store: PowerMonitorStore
    @State private var selectedMetric: ChartMetric = .batteryLevel
    @State private var selectedRange: ChartTimeRange = .twentyFourHours

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.clear)
                .background(
                    VisualEffectGlassView(material: .hudWindow, blendingMode: .behindWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(PowerMonitorTheme.backgroundGradient.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Color.white.opacity(0.12))
                )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    headerSection
                    chartSection
                    quickInfoSection
                    activitySection
                    subsystemSection
                    batteryHealthSection
                    footerSection
                }
                .padding(12)
            }
        }
        .frame(width: AppConstants.panelWidth)
        .compositingGroup()
    }

    private var headerSection: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "menubar.dock.rectangle")
                    .foregroundStyle(PowerMonitorTheme.tertiary)

                Spacer()

                Text("电源监控")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    store.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(PowerMonitorTheme.tertiary)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerTime)
                        .font(.system(size: 34, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)

                    Text(headerSubtitle)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(PowerMonitorTheme.accent)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(store.latestSnapshot.map { PowerFormatting.percent($0.batteryLevel) } ?? "--%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(PowerMonitorTheme.green)
                        .monospacedDigit()
                    Text(store.latestSnapshot?.displayStatusText ?? "等待采样")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PowerMonitorTheme.tertiary)
                }
            }

            HStack(spacing: 8) {
                HeaderCapsule(title: "系统输入", value: PowerFormatting.watts(store.latestSnapshot?.systemPowerWatts))
                HeaderCapsule(title: "电池电流", value: PowerFormatting.amps(fromMilliamps: store.latestSnapshot?.amperageMilliamps))
                HeaderCapsule(title: "适配器", value: store.latestSnapshot?.adapterWatts.map { "\($0)W" } ?? "--")
            }
        }
        .padding(12)
        .background(PowerMonitorTheme.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(PowerMonitorTheme.cardBorder))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var chartSection: some View {
        let points = store.chartPoints(for: selectedMetric, range: selectedRange)

        return SectionCard(title: "历史趋势") {
            VStack(spacing: 8) {
                CompactSegmentedControl(selection: $selectedRange, items: ChartTimeRange.allCases)
                CompactSegmentedControl(selection: $selectedMetric, items: ChartMetric.allCases)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(chartSummaryTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(PowerMonitorTheme.secondary)
                        Spacer()
                        Text(chartSummaryValue(points))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(PowerMonitorTheme.tertiary)
                    }

                    PowerTrendChart(points: points, metric: selectedMetric, range: selectedRange)
                }
            }
        }
    }

    private var quickInfoSection: some View {
        SectionCard(title: "实时详情") {
            VStack(spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    DetailMetricCard(title: "设计容量", value: PowerFormatting.milliampHours(store.latestSnapshot?.designCapacity))
                    DetailMetricCard(title: "满充容量", value: PowerFormatting.milliampHours(store.latestSnapshot?.fullChargeCapacity))
                    DetailMetricCard(title: "实际循环", value: store.latestSnapshot?.cycleCount.map(String.init) ?? "--")
                    DetailMetricCard(title: "健康度", value: PowerFormatting.health(store.latestSnapshot?.batteryHealthRatio))
                    DetailMetricCard(title: "电池电压", value: PowerFormatting.volts(fromMillivolts: store.latestSnapshot?.voltageMillivolts))
                    DetailMetricCard(title: "电池温度", value: PowerFormatting.temperature(store.latestSnapshot?.temperatureCelsius))
                }

                HStack(spacing: 8) {
                    InlineInfoPill(label: "当前会话", value: PowerFormatting.duration(store.sessionSummary?.elapsed ?? 0))
                    InlineInfoPill(label: "开始时间", value: store.sessionSummary.map { PowerFormatting.clockTime($0.startedAt) } ?? "--:--")
                    InlineInfoPill(label: "电量变化", value: store.sessionSummary.map { PowerFormatting.signedPercent($0.batteryPercentDelta) } ?? "--")
                }
            }
        }
    }

    private var activitySection: some View {
        SectionCard(title: "连接历史") {
            VStack(alignment: .leading, spacing: 8) {
                RecentActivityGrid(snapshots: store.recentSnapshots(limit: 72))
                Text("亮色代表功耗更高，所有方块都来自实际采样。")
                    .font(.system(size: 10))
                    .foregroundStyle(PowerMonitorTheme.muted)
            }
        }
    }

    private var subsystemSection: some View {
        SectionCard(title: "SoC 分项功耗") {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    DetailMetricCard(title: "CPU", value: PowerFormatting.watts(store.latestSnapshot?.cpuPowerWatts))
                    DetailMetricCard(title: "GPU", value: PowerFormatting.watts(store.latestSnapshot?.gpuPowerWatts))
                    DetailMetricCard(title: "ANE", value: PowerFormatting.watts(store.latestSnapshot?.anePowerWatts))
                }

                if let reason = store.latestSnapshot?.subsystemPowerUnavailableReason {
                    Text(reason)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PowerMonitorTheme.muted)
                } else {
                    Text("来自 powermetrics 的真实估算值，仅在系统允许时显示。")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PowerMonitorTheme.muted)
                }
            }
        }
    }

    private var batteryHealthSection: some View {
        SectionCard(title: "电池健康与充电") {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("状态")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(PowerMonitorTheme.muted)
                        Text(store.latestSnapshot?.batteryHealthCondition?.isEmpty == false ? store.latestSnapshot?.batteryHealthCondition ?? "正常" : (store.latestSnapshot?.batteryHealthState ?? "正常"))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("充电完成预计")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(PowerMonitorTheme.muted)
                        Text(headerTime)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(PowerMonitorTheme.accent)
                            .monospacedDigit()
                    }
                }

                HStack(spacing: 8) {
                    InlineInfoPill(label: "序列号", value: store.latestSnapshot?.hardwareSerialNumber ?? "不可用")
                    InlineInfoPill(label: "设计循环", value: store.latestSnapshot?.designCycleCount.map(String.init) ?? "--")
                }
            }
        }
    }

    private var footerSection: some View {
        VStack(spacing: 5) {
            FooterRow(label: "实时层", value: "IOPowerSources + 事件/轮询")
            FooterRow(label: "扩展层", value: "ioreg + system_profiler")
            FooterRow(label: "更新", value: store.lastUpdatedText)
            if let error = store.lastErrorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(PowerMonitorTheme.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(PowerMonitorTheme.footerBackground)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(PowerMonitorTheme.cardBorder))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var headerTime: String {
        guard let snapshot = store.latestSnapshot else {
            return "--:--"
        }

        if snapshot.source == .acPower && snapshot.isCharging {
            return PowerFormatting.timeString(minutes: snapshot.timeToFullChargeMinutes)
        }

        return PowerFormatting.timeString(minutes: snapshot.timeToEmptyMinutes)
    }

    private var headerSubtitle: String {
        guard let snapshot = store.latestSnapshot else {
            return "等待首次采样"
        }

        if snapshot.source == .acPower && snapshot.isCharging {
            return "预计充满时间"
        }

        if snapshot.source == .acPower && snapshot.isCharged {
            return "电池已充满"
        }

        return "预计剩余时间"
    }

    private var chartSummaryTitle: String {
        switch selectedMetric {
        case .power:
            return "当前功耗趋势"
        case .batteryLevel:
            return "电池电量走势"
        case .chargeRate:
            return "电池电流走势"
        }
    }

    private func chartSummaryValue(_ points: [PowerChartPoint]) -> String {
        guard let latest = points.last?.value else {
            return "--"
        }

        switch selectedMetric {
        case .power:
            return String(format: "%.1f W", latest)
        case .batteryLevel:
            return String(format: "%.0f%%", latest)
        case .chargeRate:
            return String(format: "%.2f A", latest)
        }
    }
}

private struct HeaderCapsule: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(PowerMonitorTheme.muted)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PowerMonitorTheme.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}

private struct CompactSegmentedControl<Item: Identifiable & Hashable>: View where Item: CustomStringConvertible {
    @Binding var selection: Item
    let items: [Item]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    Text(item.description)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selection == item ? .white : PowerMonitorTheme.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(selection == item ? PowerMonitorTheme.accent : Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}

private struct InlineInfoPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(PowerMonitorTheme.muted)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PowerMonitorTheme.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}

private struct FooterRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(PowerMonitorTheme.muted)
            Spacer()
            Text(value)
                .foregroundStyle(PowerMonitorTheme.secondary)
        }
        .font(.system(size: 10, weight: .medium))
    }
}

extension ChartMetric: CustomStringConvertible {
    var description: String { title }
}

extension ChartTimeRange: CustomStringConvertible {
    var description: String { title }
}
