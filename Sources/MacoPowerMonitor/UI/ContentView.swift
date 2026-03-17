import SwiftUI

struct ContentView: View {
    @ObservedObject var store: PowerMonitorStore
    @State private var selectedChartMetrics: Set<ChartMetric> = Set(ChartMetric.allCases)
    @State private var selectedRange: ChartTimeRange = .twentyFourHours
    @State private var showingSettings = false

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

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 8) {
                    headerSection
                    chartSection
                    summaryGridSection
                    processSection
                    footerSection
                }
                .padding(10)
            }
        }
        .frame(width: AppConstants.panelWidth)
        .frame(height: AppConstants.panelHeight)
        .clipped()
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "menubar.dock.rectangle")
                    .foregroundStyle(PowerMonitorTheme.tertiary)

                Spacer()

                Text("电源监控")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                HStack(spacing: 10) {
                    Button {
                        store.refreshNow()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(PowerMonitorTheme.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("立即刷新当前电源数据。")

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(PowerMonitorTheme.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("打开设置。")
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(headerTime)
                        .font(.system(size: 30, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(headerSubtitle)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(PowerMonitorTheme.accent)
                        .help("充电时显示预计充满时间，放电时显示预计剩余使用时间。")
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(store.latestSnapshot.map { PowerFormatting.percent($0.batteryLevel) } ?? "--%")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(PowerMonitorTheme.green)
                        .monospacedDigit()
                    Text(store.latestSnapshot?.displayStatusText ?? "等待采样")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PowerMonitorTheme.tertiary)
                }
            }

            HStack(spacing: 6) {
                HeaderCapsule(title: "系统输入", value: PowerFormatting.watts(store.latestSnapshot?.systemPowerWatts))
                    .help("当前整机输入功率，反映系统这一刻大概正在消耗多少功率。")
                HeaderCapsule(title: "电池电流", value: PowerFormatting.amps(fromMilliamps: store.latestSnapshot?.amperageMilliamps))
                    .help("电池侧即时电流。")
                HeaderCapsule(title: "适配器额定", value: store.latestSnapshot?.adapterWatts.map { "\($0)W" } ?? "--")
                    .help("适配器协商到的最大供电能力。本机当前是 65W，不代表系统此刻真的用到 65W。")
            }
        }
        .padding(10)
        .background(PowerMonitorTheme.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(PowerMonitorTheme.cardBorder))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var chartSection: some View {
        let visibleMetrics = ChartMetric.allCases.filter { selectedChartMetrics.contains($0) }

        return SectionCard(title: "趋势图") {
            VStack(spacing: 7) {
                CompactSegmentedControl(selection: $selectedRange, items: ChartTimeRange.allCases)
                metricSelectionRow

                ForEach(Array(visibleMetrics.enumerated()), id: \.element) { index, metric in
                    MetricTrendSection(
                        metric: metric,
                        series: store.chartSeries(for: metric, range: selectedRange),
                        range: selectedRange,
                        showsXAxis: index == visibleMetrics.count - 1
                    )
                }
            }
        }
    }

    private var summaryGridSection: some View {
        SectionCard(title: "关键读数") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                DetailMetricCard(title: "设计容量", value: PowerFormatting.milliampHours(store.latestSnapshot?.designCapacity))
                    .help("电池出厂设计容量。")
                DetailMetricCard(title: "满充容量", value: PowerFormatting.milliampHours(store.latestSnapshot?.fullChargeCapacity))
                    .help("电池当前实际满充容量。")
                DetailMetricCard(title: "实际循环", value: store.latestSnapshot?.cycleCount.map(String.init) ?? "--")
                    .help("当前实际循环次数。")
                DetailMetricCard(title: "健康度", value: PowerFormatting.health(store.latestSnapshot?.batteryHealthRatio))
                    .help("系统最大容量百分比或容量比值。")
                DetailMetricCard(title: "电池电压", value: PowerFormatting.volts(fromMillivolts: store.latestSnapshot?.voltageMillivolts))
                    .help("当前电池包电压。")
                DetailMetricCard(title: "温度", value: PowerFormatting.temperature(store.latestSnapshot?.temperatureCelsius))
                    .help("当前电池温度。")
                DetailMetricCard(title: "CPU/GPU/ANE", value: subsystemSummary)
                    .help("需要管理员权限才能拿到精细分项功耗。")
                DetailMetricCard(title: "充电状态", value: store.latestSnapshot?.displayStatusText ?? "--")
                    .help("当前处于外接电源、充电中或电池供电状态。")
            }
        }
    }

    private var processSection: some View {
        SectionCard(title: "较耗电应用") {
            VStack(spacing: 6) {
                ForEach(Array(store.topProcesses.prefix(4))) { process in
                    ProcessEnergyRow(process: process)
                }

                HStack(spacing: 6) {
                    InlineInfoPill(label: "会话", value: PowerFormatting.duration(store.sessionSummary?.elapsed ?? 0))
                        .help("当前电源会话时长。")
                    InlineInfoPill(label: "开始", value: store.sessionSummary.map { PowerFormatting.clockTime($0.startedAt) } ?? "--:--")
                        .help("当前会话开始时间。")
                    InlineInfoPill(label: "电量变化", value: store.sessionSummary.map { PowerFormatting.signedPercent($0.batteryPercentDelta) } ?? "--")
                        .help("当前会话的净电量变化。")
                }
            }
        }
    }

    private var footerSection: some View {
        SectionCard(title: "电池健康与说明") {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    InlineInfoPill(label: "状态", value: store.latestSnapshot?.batteryHealthState ?? "正常")
                        .help("系统给出的电池健康状态。")
                    InlineInfoPill(label: "序列号", value: store.latestSnapshot?.hardwareSerialNumber ?? "不可用")
                        .help("电池硬件序列号。")
                    InlineInfoPill(label: "设计循环", value: store.latestSnapshot?.designCycleCount.map(String.init) ?? "--")
                        .help("公开电源字典里的设计循环指标，不等于实际循环次数。")
                }

                HStack {
                    Text("数据源")
                        .foregroundStyle(PowerMonitorTheme.muted)
                    Spacer()
                    Text("IOPowerSources / ioreg / system_profiler")
                        .foregroundStyle(PowerMonitorTheme.secondary)
                }
                .font(.system(size: 10, weight: .medium))

                HStack {
                    Text("更新")
                        .foregroundStyle(PowerMonitorTheme.muted)
                    Spacer()
                    Text(store.lastUpdatedText)
                        .foregroundStyle(PowerMonitorTheme.secondary)
                }
                .font(.system(size: 10, weight: .medium))

                if let error = store.lastErrorMessage {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(PowerMonitorTheme.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
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

    private var metricSelectionRow: some View {
        HStack(spacing: 4) {
            ForEach(ChartMetric.allCases) { metric in
                Button {
                    toggleChartMetric(metric)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: selectedChartMetrics.contains(metric) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text(metric.title)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selectedChartMetrics.contains(metric) ? .white : PowerMonitorTheme.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(selectedChartMetrics.contains(metric) ? PowerMonitorTheme.accent : Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .help("勾选后会在同一时间范围内同时显示多个指标，不再来回切换。")
    }

    private func toggleChartMetric(_ metric: ChartMetric) {
        if selectedChartMetrics.contains(metric) {
            if selectedChartMetrics.count > 1 {
                selectedChartMetrics.remove(metric)
            }
        } else {
            selectedChartMetrics.insert(metric)
        }
    }

    private var subsystemSummary: String {
        if let snapshot = store.latestSnapshot,
           let cpu = snapshot.cpuPowerWatts,
           let gpu = snapshot.gpuPowerWatts,
           let ane = snapshot.anePowerWatts {
            return String(format: "%.1f/%.1f/%.1fW", cpu, gpu, ane)
        }

        return "需授权"
    }
}

private struct HeaderCapsule: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(PowerMonitorTheme.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(PowerMonitorTheme.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(selection == item ? .white : PowerMonitorTheme.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(selection == item ? PowerMonitorTheme.accent : Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct MetricTrendSection: View {
    let metric: ChartMetric
    let series: [PowerChartSeries]
    let range: ChartTimeRange
    let showsXAxis: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PowerMonitorTheme.secondary)
                    Text(metric.subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(PowerMonitorTheme.muted)
                }

                Spacer()

                Text(metricHelpLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(PowerMonitorTheme.tertiary)
            }

            HStack(spacing: 4) {
                ForEach(series) { series in
                    ChartSeriesValuePill(series: series)
                }
            }

            PowerTrendChart(series: series, metric: metric, range: range, showsXAxis: showsXAxis)
                .help(metricHelpText)
        }
        .padding(8)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var metricHelpLabel: String {
        switch metric {
        case .power:
            return "输入 / 输出"
        case .batteryLevel:
            return "剩余容量"
        case .chargeRate:
            return "充 / 放电"
        }
    }

    private var metricHelpText: String {
        switch metric {
        case .power:
            return "同时显示系统输入、电池输出和电池回充，便于看清功率到底从哪里来、流向哪里去。"
        case .batteryLevel:
            return "显示电池百分比变化，和功耗、电流时间轴保持一致。"
        case .chargeRate:
            return "同时显示充电电流和放电电流，避免把正负方向混在一条线上。"
        }
    }
}

private struct ChartSeriesValuePill: View {
    let series: PowerChartSeries

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 6, height: 6)
                Text(series.title)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(PowerMonitorTheme.muted)
            }
            Text(series.metric.formatValue(series.latestValue))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(PowerMonitorTheme.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var indicatorColor: Color {
        switch series.id {
        case .systemInputPower, .batteryLevel:
            return PowerMonitorTheme.accent
        case .batteryDischargePower:
            return Color(red: 1.00, green: 0.66, blue: 0.21)
        case .batteryChargePower:
            return PowerMonitorTheme.green
        case .batteryDischargeCurrent:
            return PowerMonitorTheme.red
        case .batteryChargeCurrent:
            return Color(red: 0.26, green: 0.78, blue: 0.94)
        }
    }
}

private struct InlineInfoPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(PowerMonitorTheme.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(PowerMonitorTheme.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ProcessEnergyRow: View {
    let process: ProcessEnergyStat

    var body: some View {
        HStack(spacing: 8) {
            Text(process.command)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PowerMonitorTheme.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(process.primaryScoreText)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(PowerMonitorTheme.secondary)
                .monospacedDigit()
                .frame(width: 76, alignment: .trailing)

            Text(process.memoryText)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(PowerMonitorTheme.muted)
                .frame(width: 42, alignment: .trailing)
        }
        .help("PID \(process.pid) · CPU \(String(format: "%.1f%%", process.cpuPercent)) · POWER \(String(format: "%.1f", process.powerScore)) · 内存 \(process.memoryText)")
    }
}

private struct SettingsView: View {
    @ObservedObject var store: PowerMonitorStore
    @AppStorage(PowermetricsSubsystemPowerProvider.autoAttemptDefaultsKey) private var autoAttempt = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("设置")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            Toggle("自动尝试无密码 sudo 获取 SoC 分项功耗", isOn: $autoAttempt)
                .help("开启后，应用会在后台尝试用无密码 sudo 读取 powermetrics。如果系统没有配置 NOPASSWD，这条路径仍然会失败。")

            VStack(alignment: .leading, spacing: 6) {
                Text("管理员采样")
                    .font(.system(size: 13, weight: .semibold))
                Text("点击下面按钮会调用系统管理员鉴权弹窗，读取一次 CPU / GPU / ANE 分项功耗。")
                    .font(.system(size: 11))
                    .foregroundStyle(PowerMonitorTheme.tertiary)
                Button("运行管理员权限采样") {
                    store.requestPrivilegedSubsystemSample()
                }
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("说明")
                    .font(.system(size: 13, weight: .semibold))
                Text("适配器额定功率表示供电上限，系统输入功率表示当前整机真实消耗。两者不是同一个概念。")
                Text("设计循环是公开电源字典里的设计指标，实际循环次数来自系统电池统计。")
            }
            .font(.system(size: 11))
            .foregroundStyle(PowerMonitorTheme.tertiary)

            Spacer()
        }
        .padding(18)
        .frame(width: 420, height: 300)
    }
}

extension ChartMetric: CustomStringConvertible {
    var description: String { title }
}

extension ChartTimeRange: CustomStringConvertible {
    var description: String { title }
}
