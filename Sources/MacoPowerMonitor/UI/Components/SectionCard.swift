import SwiftUI

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(PowerMonitorTheme.tertiary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(PowerMonitorTheme.sectionBackground)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(PowerMonitorTheme.cardBorder))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
