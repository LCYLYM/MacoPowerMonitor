import Foundation

enum PowerFormatting {
    static func timeString(minutes: Int?, fallback: String = "--:--") -> String {
        guard let minutes else {
            return fallback
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours):" + String(format: "%02d", remainingMinutes)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(Int(interval / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    static func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func relativeUpdateTime(from date: Date) -> String {
        let seconds = max(Int(Date().timeIntervalSince(date)), 0)

        switch seconds {
        case 0..<10:
            return "刚刚更新"
        case 10..<60:
            return "\(seconds) 秒前更新"
        default:
            return "\(seconds / 60) 分钟前更新"
        }
    }

    static func watts(_ value: Double?) -> String {
        guard let value else {
            return "-- W"
        }

        return String(format: "%.1f W", value)
    }

    static func amps(fromMilliamps milliamps: Int?) -> String {
        guard let milliamps else {
            return "-- A"
        }

        return String(format: "%.2f A", Double(milliamps) / 1_000.0)
    }

    static func volts(fromMillivolts millivolts: Int?) -> String {
        guard let millivolts else {
            return "-- V"
        }

        return String(format: "%.2f V", Double(millivolts) / 1_000.0)
    }

    static func temperature(_ value: Double?) -> String {
        guard let value else {
            return "-- °C"
        }

        return String(format: "%.1f °C", value)
    }

    static func milliampHours(_ value: Int?) -> String {
        guard let value else {
            return "-- mAh"
        }

        return "\(value) mAh"
    }

    static func percent(_ ratio: Double) -> String {
        let clamped = min(max(ratio, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    static func plainPercent(_ value: Double?) -> String {
        guard let value else {
            return "--%"
        }

        return "\(Int(value.rounded()))%"
    }

    static func signedPercent(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return sign + "\(Int(value.rounded()))%"
    }

    static func signedCapacity(_ value: Int?) -> String {
        guard let value else {
            return "--"
        }

        let sign = value > 0 ? "+" : ""
        return "\(sign)\(value) mAh"
    }

    static func health(_ ratio: Double?) -> String {
        guard let ratio else {
            return "--"
        }

        return percent(ratio)
    }
}
