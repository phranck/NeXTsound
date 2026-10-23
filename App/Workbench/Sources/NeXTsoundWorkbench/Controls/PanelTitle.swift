import SwiftUI

/// A panel's title in capitals over a faint rule, one line high.
struct PanelTitle: View {
    let title: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FrontPanelType.font)
                .tracking(FrontPanelType.titleTracking)
                .textCase(.uppercase)
                .foregroundStyle(FrontPanelPalette.title)
                .lineLimit(1)
                .fixedSize()
                .frame(height: FrontPanelType.lineHeight)
            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(height: 1)
        }
        .accessibilityAddTraits(.isHeader)
    }
}
