import SwiftUI

struct ContentView: View {
    @ObservedObject var store: PowerMonitorStore
    @State private var selectedMetric: ChartMetric = .power

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                headerSection
                chartSection
                sessionSection
                batteryHealthSection
                electricalSection
                activitySection
                footerSection
            }
            .padding(16)
        }
        .frame(width: AppConstants.panelWidth)
        .background(PowerMonitorTheme.backgroundGradient)
    }

    private var headerSection: some View {
        VStack(spacing: 14) {
            HStack {
                Label("电源监控", systemImage: "menubar.dock.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))

                Spacer()

                Button {
                    store.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("立即刷新")
            }

            VStack(spacing: 4) {
                Text(headerTime)
                    .font(.system(size: 50, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Text(headerSubtitle)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(PowerMonitorTheme.accent)
            }

            HStack(spacing: 24) {
                SummaryMetricView(title: "实时功耗", value: PowerFormatting.watts(store.latestSnapshot?.preferredPowerWatts))
                SummaryMetricView(
                    title: "当前电量",
                    value: store.latestSnapshot.map { PowerFormatting.percent($0.batteryLevel) } ?? "--%",
                    accent: PowerMonitorTheme.green
                )
            }
        }
        .padding(18)
        .background(PowerMonitorTheme.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(PowerMonitorTheme.cardBorder))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var chartSection: some View {
        VStack(spacing: 14) {
            Picker("指标", selection: $selectedMetric) {
                ForEach(ChartMetric.allCases) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            .pickerStyle(.segmented)

            let points = store.chartPoints(for: selectedMetric)
            PowerLineChart(
                values: points,
                lineColor: PowerMonitorTheme.accent,
                fillColor: PowerMonitorTheme.accent.opacity(0.25),
                topTrailingText: selectedMetric == .power ? "历史趋势 (1 小时)" : "电量趋势 (1 小时)",
                leadingLabel: chartLeadingLabel(points: points),
                trailingLabel: "现在",
                emptyStateTitle: selectedMetric.emptyStateTitle
            )
        }
        .padding(16)
        .background(PowerMonitorTheme.sectionBackground)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(PowerMonitorTheme.cardBorder))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var sessionSection: some View {
        SectionCard(title: "电池详细统计") {
            if let session = store.sessionSummary {
                VStack(spacing: 12) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                            Text(store.latestSnapshot?.source == .battery ? "电池已使用时间" : "当前连接时长")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                        }

                        Spacer()

                        Text(PowerFormatting.duration(session.elapsed))
                            .font(.system(size: 28, weight: .light, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    }

                    HStack {
                        SessionDeltaView(label: "电量变化", value: PowerFormatting.signedPercent(session.batteryPercentDelta))
                        SessionDeltaView(label: "容量变化", value: PowerFormatting.signedCapacity(session.capacityDeltaMah))
                    }
                }
            } else {
                EmptySectionStateView(text: "需要积累几个样本后才能计算连接会话。")
            }
        }
    }

    private var batteryHealthSection: some View {
        SectionCard(title: "电池健康与充电") {
            let snapshot = store.latestSnapshot

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                DetailMetricCard(title: "设计容量", value: PowerFormatting.milliampHours(snapshot?.designCapacityMah))
                DetailMetricCard(title: "满充容量", value: PowerFormatting.milliampHours(snapshot?.maxCapacityMah))
                DetailMetricCard(title: "循环次数", value: snapshot?.cycleCount.map(String.init) ?? "--")
                DetailMetricCard(title: "健康度", value: PowerFormatting.health(snapshot?.batteryHealthRatio))
            }

            Divider()
                .overlay(.white.opacity(0.08))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("电池状态")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(snapshot?.batteryHealthCondition ?? snapshot?.batteryHealthState ?? snapshot?.displayStatusText ?? "未知")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("预计时长")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(headerTime)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(PowerMonitorTheme.accent)
                        .monospacedDigit()
                }
            }
        }
    }

    private var electricalSection: some View {
        SectionCard(title: "实时电气指标") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                DetailMetricCard(title: "系统输入功率", value: PowerFormatting.watts(store.latestSnapshot?.systemPowerWatts))
                DetailMetricCard(title: "电池功率流", value: PowerFormatting.watts(store.latestSnapshot?.batteryFlowWatts))
                DetailMetricCard(title: "电池电压", value: PowerFormatting.volts(fromMillivolts: store.latestSnapshot?.voltageMillivolts))
                DetailMetricCard(title: "电池电流", value: PowerFormatting.amps(fromMilliamps: store.latestSnapshot?.amperageMilliamps))
                DetailMetricCard(title: "适配器功率", value: store.latestSnapshot?.adapterWatts.map { "\($0) W" } ?? "-- W")
                DetailMetricCard(title: "电池温度", value: PowerFormatting.temperature(store.latestSnapshot?.temperatureCelsius))
            }
        }
    }

    private var activitySection: some View {
        SectionCard(title: "最近运行记录") {
            VStack(alignment: .leading, spacing: 10) {
                Text("下方每个方块都来自真实采样，颜色越亮代表当次功耗越高。")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))

                RecentActivityGrid(snapshots: store.recentSnapshots(limit: 40))
            }
        }
    }

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("数据源")
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Text("IOPowerSources + AppleSmartBattery")
                    .foregroundStyle(.white.opacity(0.82))
            }

            HStack {
                Text("刷新策略")
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Text("每 30 秒采样，带 5 秒容差")
                    .foregroundStyle(.white.opacity(0.82))
            }

            HStack {
                Text("最近更新")
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Text(store.lastUpdatedText)
                    .foregroundStyle(store.lastErrorMessage == nil ? .white.opacity(0.82) : PowerMonitorTheme.red)
            }

            if let error = store.lastErrorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(PowerMonitorTheme.red)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(14)
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

    private func chartLeadingLabel(points: [Double]) -> String {
        guard let highest = points.max() else {
            return "--"
        }

        switch selectedMetric {
        case .power:
            return PowerFormatting.watts(highest)
        case .batteryLevel:
            return "\(Int(highest.rounded()))%"
        }
    }
}

private struct SummaryMetricView: View {
    let title: String
    let value: String
    var accent: Color = .white

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
                .monospacedDigit()

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SessionDeltaView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct EmptySectionStateView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
