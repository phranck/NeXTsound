import AppKit
import SwiftUI

/// The About window's content: the app's icon over the front panel's header, the version with its build in a
/// readout, and the copyright as a caption, on the panels' metal.
///
/// The readout takes the display color that the front panel's keys choose. The metal reaches under the hidden title
/// bar, and a drag anywhere on it moves the window, as on the front panel.
public struct AboutPanel: View {
    private let info: AboutInfo
    private let icon: NSImage
    @AppStorage(PhosphorTheme.storageKey) private var theme = PhosphorTheme.blue

    public var body: some View {
        WholePointFrame {
            VStack(spacing: AboutPanelLayout.rowSpacing) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: AboutPanelLayout.iconSize, height: AboutPanelLayout.iconSize)
                    .accessibilityHidden(true)
                FrontPanelHeader()
                PanelReadout(text: info.versionLine, layout: DotMatrixLinesLayout(cells: info.versionLine.count))
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: info.versionLine))
                if let copyright = info.copyright {
                    ControlCaption(caption: Text(verbatim: copyright))
                }
            }
            .padding(AboutPanelLayout.padding)
            .frame(width: AboutPanelLayout.width)
            .fixedSize()
        }
        .background {
            PanelMetal()
        }
        .environment(\.phosphorTheme, theme)
        .panelWindowContent()
        .windowMinimizeBehavior(.disabled)
    }

    /// - Parameters:
    ///   - info: The version and the copyright to show, the app bundle's own unless a render passes others.
    ///   - icon: The icon to show, the app's own unless a render passes another.
    public init(info: AboutInfo = .app, icon: NSImage = NSApplication.shared.applicationIconImage) {
        _ = FrontPanelFonts.registration
        self.info = info
        self.icon = Self.sizedForPanel(icon)
    }
}

private extension AboutPanel {
    /// A copy of `icon` at the size the panel shows it at. An app's icon comes at 32 points, and drawn at that size and
    /// scaled up to the panel's frame it blurs, while at the frame's size it draws from the representation that fills
    /// the frame.
    static func sizedForPanel(_ icon: NSImage) -> NSImage {
        guard let copy = icon.copy() as? NSImage else {
            return icon
        }
        copy.size = NSSize(width: AboutPanelLayout.iconSize, height: AboutPanelLayout.iconSize)
        return copy
    }
}
