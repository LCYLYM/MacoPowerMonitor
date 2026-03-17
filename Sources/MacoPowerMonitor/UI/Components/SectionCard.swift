import SwiftUI

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.4))

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(PowerMonitorTheme.sectionBackground)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(PowerMonitorTheme.cardBorder))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
