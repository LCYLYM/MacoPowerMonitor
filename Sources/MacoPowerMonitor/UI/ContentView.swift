import SwiftUI

struct ContentView: View {
    @ObservedObject var store: PowerMonitorStore
    @State private var selectedChartMetrics: Set<ChartMetric> = Set(ChartMetric.allCases)
    @State private var selectedRange: ChartTimeRange = .twentyFourHours
    @State private var showingSettings = false

    init(store: PowerMonitorStore) {
        self.store = store
        _selectedChartMetrics = State(initialValue: store.selectedHistoryMetrics)
        _selectedRange = State(initialValue: store.selectedHistoryRange)
    }

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
                VStack(spacing: 8) {
                    headerSection
                    adapterSection
                    chartSection
                    summaryGridSection
                    processSection
                    footerSection
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .frame(width: AppConstants.panelWidth)
        .frame(height: AppConstants.panelHeight)
        .clipped()
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store)
        }
        .onAppear {
            store.updateHistorySelection(metrics: selectedChartMetrics, range: selectedRange)
        }
        .onChange(of: selectedChartMetrics) { metrics in
            store.updateHistorySelection(metrics: metrics, range: selectedRange)
        }
        .onChange(of: selectedRange) { range in
            store.updateHistorySelection(metrics: selectedChartMetrics, range: range)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "menubar.dock.rectangle")
                    .foregroundStyle(PowerMonitorTheme.tertiary)
                    .help("Maco Power Monitor 控制面板。")

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
                HeaderCapsule(title: "实时输入功率", value: PowerFormatting.watts(store.latestSnapshot?.adapterRealtimePowerWatts))
                    .help("每秒读取 Mac 电源遥测报告的当前输入功率。")
                HeaderCapsule(title: "实时输入电流", value: PowerFormatting.amps(fromMilliamps: store.latestSnapshot?.adapterRealtimeCurrentMilliamps))
                    .help("每秒读取 PowerTelemetryData.SystemCurrentIn；不是电源合约的最大电流。")
                HeaderCapsule(title: "电池实时电流", value: PowerFormatting.amps(fromMilliamps: store.latestSnapshot?.amperageMilliamps))
                    .help("每秒直接读取 AppleSmartBattery 的充电或放电电流。")
            }
        }
        .padding(10)
        .background(PowerMonitorTheme.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(PowerMonitorTheme.cardBorder))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var adapterSection: some View {
        let snapshot = store.latestSnapshot
        let isConnected = snapshot?.source == .acPower

        return SectionCard(title: "充电器 / 电源适配器") {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill((isConnected ? PowerMonitorTheme.accent : PowerMonitorTheme.muted).opacity(0.14))
                        Image(systemName: isConnected ? "powerplug.fill" : "powerplug")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(isConnected ? PowerMonitorTheme.accent : PowerMonitorTheme.muted)
                    }
                    .frame(width: 42, height: 42)
                    .help(isConnected ? "已连接电源适配器。" : "当前未连接电源适配器。")

                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot?.adapterProtocolDisplayName ?? "等待首次采样")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PowerMonitorTheme.secondary)
                        Text(adapterProtocolDetail)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(PowerMonitorTheme.muted)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 6)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(PowerFormatting.watts(snapshot?.adapterRealtimePowerWatts))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(isConnected ? PowerMonitorTheme.green : PowerMonitorTheme.tertiary)
                            .monospacedDigit()
                        Text("实时输入功率")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(PowerMonitorTheme.muted)
                        Text(PowerFormatting.amps(fromMilliamps: snapshot?.adapterRealtimeCurrentMilliamps))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(PowerMonitorTheme.cyan)
                            .monospacedDigit()
                    }
                }

                HStack(spacing: 6) {
                    InlineInfoPill(label: "实时输入电压", value: PowerFormatting.volts(fromMillivolts: snapshot?.adapterRealtimeVoltageMillivolts))
                        .help("每秒读取 PowerTelemetryData.SystemVoltageIn。")
                    InlineInfoPill(label: "实时输入电流", value: PowerFormatting.amps(fromMilliamps: snapshot?.adapterRealtimeCurrentMilliamps))
                        .help("每秒读取 PowerTelemetryData.SystemCurrentIn。")
                    InlineInfoPill(label: "电池实时电流", value: PowerFormatting.amps(fromMilliamps: snapshot?.amperageMilliamps))
                        .help("正值为充电，负值为放电；每秒读取一次。")
                    InlineInfoPill(label: "协商电流上限", value: PowerFormatting.amps(fromMilliamps: snapshot?.adapterCurrentMilliamps))
                        .help("电源合约允许的最大电流，不是瞬时电流。")
                }

                HStack(spacing: 6) {
                    InlineInfoPill(label: "协商电压", value: PowerFormatting.volts(fromMillivolts: snapshot?.adapterVoltageMillivolts))
                    InlineInfoPill(label: "合约上限", value: snapshot?.adapterWatts.map { "\($0) W" } ?? "-- W")
                    InlineInfoPill(label: "PD 修订", value: adapterPDRevisionText)
                    InlineInfoPill(label: "刷新频率", value: "1 秒")
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "info.circle")
                        .help("查看电源数据来源与协议识别说明。")
                    Text("功率、输入电压和输入电流每秒读取 Mac 侧 PowerTelemetryData；macOS 不公开墙插侧损耗。QC/Apple 私有协议仅在系统有明确标识时显示，不做猜测。")
                }
                .font(.system(size: 9))
                .foregroundStyle(PowerMonitorTheme.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
                        series: store.chartSeriesByMetric[metric] ?? [],
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
        SectionCard(title: "CPU 活跃应用") {
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
                    Text("IOPowerSources / IORegistry / system_profiler")
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

    private var adapterProtocolDetail: String {
        guard let snapshot = store.latestSnapshot else {
            return "正在读取电源协商信息"
        }
        guard snapshot.source == .acPower else {
            return "当前由电池供电"
        }
        return snapshot.adapterProtocolDetail ?? "macOS 未公开更详细的协议字段"
    }

    private var adapterPDRevisionText: String {
        guard let code = store.latestSnapshot?.adapterPDRevisionCode else {
            return "--"
        }
        return "修订码 \(code)"
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

        if let chargeHoldReason = snapshot.chargeHoldReason {
            return chargeHoldReason.displayText
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
                .help(selectedChartMetrics.contains(metric) ? "隐藏\(metric.title)趋势图。" : "显示\(metric.title)趋势图。")
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
        guard let snapshot = store.latestSnapshot else {
            return "--"
        }

        let readings = [snapshot.cpuPowerWatts, snapshot.gpuPowerWatts, snapshot.anePowerWatts]
        guard readings.contains(where: { $0 != nil }) else {
            if snapshot.subsystemPowerUnavailableReason?.contains("正在启动") == true {
                return "采样启动中"
            }
            if snapshot.subsystemPowerUnavailableReason?.contains("暂未返回") == true {
                return "采样中断"
            }
            return "需授权"
        }

        let values = readings.map { value in
            value.map { String(format: "%.1f", $0) } ?? "--"
        }
        return values.joined(separator: "/") + "W"
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
            return "同时显示适配器实时输入、电池输出和电池回充，便于看清功率从哪里来、流向哪里去。"
        case .batteryLevel:
            return "显示电池百分比变化；横轴固定对应所选时间范围，便于对照每个时间点的电量。"
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
        case .adapterInputPower, .batteryLevel:
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
        .help("PID \(process.pid) · CPU \(String(format: "%.1f%%", process.cpuPercent)) · 内存 \(process.memoryText)")
    }
}

private struct SettingsView: View {
    @ObservedObject var store: PowerMonitorStore
    @ObservedObject private var runtimeSettings = AppRuntimeSettings.shared
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

            VStack(alignment: .leading, spacing: 8) {
                Toggle(
                    "后台保活（保持状态栏常驻）",
                    isOn: Binding(
                        get: { runtimeSettings.backgroundKeepAliveEnabled },
                        set: { runtimeSettings.setBackgroundKeepAlive(enabled: $0) }
                    )
                )
                .help("开启后，应用会向系统声明自己不应被自动或突然终止。不会阻止系统睡眠，也不会额外持续提权。")

                Text(runtimeSettings.backgroundKeepAliveEnabled
                     ? "当前已启用后台保活，应用会更偏向保持状态栏常驻。"
                     : "当前未启用后台保活，系统可在合适时机自动终止空闲应用。")
                    .font(.system(size: 11))
                    .foregroundStyle(PowerMonitorTheme.tertiary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(
                    "开机自动启动",
                    isOn: Binding(
                        get: { runtimeSettings.launchAtLoginEnabled },
                        set: { runtimeSettings.setLaunchAtLogin(enabled: $0) }
                    )
                )
                .help("开启后，登录当前用户时会自动启动本应用。该功能仅在打包后的 .app 中可用。")

                HStack {
                    Text("当前状态")
                        .foregroundStyle(PowerMonitorTheme.muted)
                    Spacer()
                    Text(runtimeSettings.launchAtLoginStatusText)
                        .foregroundStyle(runtimeSettings.launchAtLoginEnabled ? PowerMonitorTheme.green : PowerMonitorTheme.secondary)
                }
                .font(.system(size: 11, weight: .medium))

                Text(runtimeSettings.launchAtLoginDetailText)
                    .font(.system(size: 11))
                    .foregroundStyle(PowerMonitorTheme.tertiary)

                if let loginItemError = runtimeSettings.launchAtLoginErrorMessage {
                    Text(loginItemError)
                        .font(.system(size: 11))
                        .foregroundStyle(PowerMonitorTheme.red)
                }
            }

            Toggle("自动尝试无密码 sudo 获取 SoC 分项功耗", isOn: $autoAttempt)
                .help("开启后，应用会在后台尝试用无密码 sudo 读取 powermetrics。如果系统没有配置 NOPASSWD，这条路径仍然会失败。")

            VStack(alignment: .leading, spacing: 6) {
                Text("管理员采样")
                    .font(.system(size: 13, weight: .semibold))
                Text("授权一次后，会在本次 App 运行期间持续更新 CPU / GPU / ANE 分项功耗；退出 App 后自动停止。")
                    .font(.system(size: 11))
                    .foregroundStyle(PowerMonitorTheme.tertiary)
                Button("启动管理员持续采样") {
                    store.requestPrivilegedSubsystemSample()
                }
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("说明")
                    .font(.system(size: 13, weight: .semibold))
                Text("适配器协商上限不是实时功率；实时输入来自 Mac 侧电源遥测，也不等于墙插侧功率。")
                Text("设计循环是公开电源字典里的设计指标，实际循环次数来自系统电池统计。")
            }
            .font(.system(size: 11))
            .foregroundStyle(PowerMonitorTheme.tertiary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("项目")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("v\(AppConstants.appVersion)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PowerMonitorTheme.tertiary)
                }

                HStack(spacing: 10) {
                    Button("GitHub") {
                        AppControlActions.openRepository()
                    }
                    .buttonStyle(.bordered)
                    .help("打开项目 GitHub 仓库。")

                    Button("最新 Release") {
                        AppControlActions.openLatestRelease()
                    }
                    .buttonStyle(.bordered)
                    .help("打开最新版本下载页。")

                    Spacer()

                    Button("退出应用") {
                        AppControlActions.quitApplication()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PowerMonitorTheme.red)
                    .help("退出状态栏应用并结束后台运行。")
                }
            }

            Spacer()
        }
        .padding(18)
        .frame(width: 430, height: 470)
    }
}

extension ChartMetric: CustomStringConvertible {
    var description: String { title }
}

extension ChartTimeRange: CustomStringConvertible {
    var description: String { title }
}
