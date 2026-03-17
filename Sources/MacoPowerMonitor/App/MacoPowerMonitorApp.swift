import SwiftUI

@main
struct MacoPowerMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: PowerMonitorStore

    init() {
        _store = StateObject(wrappedValue: PowerMonitorStore.shared)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: store)
        } label: {
            MenuBarStatusLabel(snapshot: store.latestSnapshot)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarStatusLabel: View {
    let snapshot: PowerSnapshot?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
            Text(labelText)
                .monospacedDigit()
        }
        .help(tooltipText)
    }

    private var labelText: String {
        guard let snapshot else {
            return "--%"
        }

        return PowerFormatting.percent(snapshot.batteryLevel)
    }

    private var symbolName: String {
        guard let snapshot else {
            return "battery.0"
        }

        if snapshot.isCharging {
            return "bolt.batteryblock.fill"
        }

        switch snapshot.batteryLevel {
        case ..<0.15:
            return "battery.0"
        case ..<0.35:
            return "battery.25"
        case ..<0.60:
            return "battery.50"
        case ..<0.85:
            return "battery.75"
        default:
            return "battery.100"
        }
    }

    private var tooltipText: String {
        guard let snapshot else {
            return "正在读取电源信息"
        }

        let power = PowerFormatting.watts(snapshot.preferredPowerWatts)
        let status = snapshot.displayStatusText
        return "电量 \(PowerFormatting.percent(snapshot.batteryLevel)) · \(status) · \(power)"
    }
}
