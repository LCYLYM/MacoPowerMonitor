import SwiftUI

enum PowerMonitorTheme {
    static let accent = Color(red: 0.07, green: 0.53, blue: 1.00)
    static let green = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let red = Color(red: 1.00, green: 0.33, blue: 0.28)
    static let cardBorder = Color.white.opacity(0.06)
    static let cardBackground = Color(red: 0.06, green: 0.11, blue: 0.22).opacity(0.98)
    static let sectionBackground = Color(red: 0.07, green: 0.10, blue: 0.19).opacity(0.98)
    static let footerBackground = Color.white.opacity(0.04)
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.08, blue: 0.16),
            Color(red: 0.03, green: 0.06, blue: 0.12),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}
