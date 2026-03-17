import SwiftUI

enum PowerMonitorTheme {
    static let accent = Color(red: 0.07, green: 0.53, blue: 1.00)
    static let green = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let red = Color(red: 1.00, green: 0.33, blue: 0.28)
    static let orange = Color(red: 1.00, green: 0.66, blue: 0.21)
    static let cyan = Color(red: 0.26, green: 0.78, blue: 0.94)
    static let secondary = Color.white.opacity(0.82)
    static let tertiary = Color.white.opacity(0.55)
    static let muted = Color.white.opacity(0.34)
    static let cardBorder = Color.white.opacity(0.08)
    static let cardBackground = Color.white.opacity(0.08)
    static let sectionBackground = Color.white.opacity(0.06)
    static let footerBackground = Color.white.opacity(0.04)
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.10, green: 0.12, blue: 0.18).opacity(0.88),
            Color(red: 0.06, green: 0.08, blue: 0.13).opacity(0.78),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}
