import NeXTsoundCore
import SwiftUI

/// The front panel window's content.
///
/// Brushed metal holds the header, the multifunction display with the selected profile's live EQ curve, and the row
/// of controls that edits the profile. The row sets the panel's width, and the header and the display take it, so
/// they end where the controls end. The metal reaches under the hidden title bar, so the window's buttons sit on it.
public struct FrontPanelView: View {
    private let model: WorkbenchModel
    @State private var selectedBand = 0
    @State private var saveFeedback = FrontPanelSaveFeedback()
    @State private var isShowingFlashSheet = false
    @AppStorage(Self.phosphorThemeKey) private var theme = PhosphorTheme.blue
    @Environment(\.undoManager) private var undoManager

    public var body: some View {
        WholePointFrame {
            VStack(spacing: 0) {
                FrontPanelHeader()
                DisplayBay(settings: model.profile.settings, profileName: displayedProfileName, status: status, theme: theme)
                    .padding(FrontPanelLayout.bayMargin)
                FrontPanelControlRow(editor: editor, boardButtons: boardButtons, selectedBand: $selectedBand, theme: $theme)
            }
            .padding(FrontPanelLayout.panelPadding)
            .fixedSize()
        }
        .background {
            BrushedMetal()
        }
        .ignoresSafeArea()
        .focusedSceneValue(\.frontPanelBand, FrontPanelBand(editor: editor, index: selectedBand))
        .sheet(isPresented: $isShowingFlashSheet) {
            FlashFirmwareSheet(connectionState: model.boards.state)
        }
    }

    /// - Parameter model: The workbench's model, whose selected profile the panel shows and edits.
    public init(model: WorkbenchModel) {
        _ = FrontPanelFonts.registration
        self.model = model
    }
}

private extension FrontPanelView {
    /// The defaults key of the display color, which the panel keeps across launches.
    static let phosphorThemeKey = "frontPanelPhosphorTheme"

    var editor: FrontPanelEditor {
        FrontPanelEditor(model: model, undoManager: undoManager)
    }

    var boardButtons: FrontPanelBoardButtons {
        FrontPanelBoardButtons(
            saveLEDIsLit: saveFeedback.ledIsLit,
            save: { Task { await saveFeedback.save(with: model) } },
            flash: { isShowingFlashSheet = true }
        )
    }

    var status: FrontPanelStatus {
        FrontPanelStatus(
            board: model.boards.state,
            storage: model.boards.storage,
            runtime: model.boards.runtime,
            message: messageSources.message
        )
    }

    var messageSources: FrontPanelMessageSources {
        FrontPanelMessageSources(
            saveInProgress: model.isSavingToBoard ? model.boardStorageStatus : nil,
            saveSucceeded: saveFeedback.showsSuccess,
            error: model.errorMessage,
            board: model.boards.state,
            validationProblem: model.profile.validationProblem,
            storageStatus: model.storageStatus,
            storageFailed: model.storageError != nil
        )
    }

    /// A profile without a name shows as Untitled, as it does in the sidebar.
    var displayedProfileName: String {
        model.profile.name.isEmpty ? String(localized: "Untitled") : model.profile.name
    }
}

/// The multifunction display's housing: a dark frame around the glass.
///
/// The glass's corners run parallel to the frame's, so its radius is the frame's less the frame's width. The light
/// falls from above as in the mockup: the frame is shaded along its top and catches a faint line along its bottom,
/// the glass has a light edge at the top left and a dark one at the bottom right, and a highlight runs under the
/// frame.
private struct DisplayBay: View {
    let settings: DSPSettings
    let profileName: String
    let status: FrontPanelStatus
    let theme: PhosphorTheme

    var body: some View {
        FrontPanelDisplay(settings: settings, profileName: profileName, status: status, theme: theme)
            .padding(FrontPanelLayout.screenPadding)
            .vfdGlass(cornerRadius: FrontPanelLayout.bayRadius - FrontPanelLayout.frameWidth)
            .padding(FrontPanelLayout.frameWidth)
            .background(
                LinearGradient(
                    colors: [Color(hex: FrontPanelPalette.frameTop), Color(hex: FrontPanelPalette.frameBottom)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .shadow(.inner(color: .black.opacity(0.7), radius: 2.5, y: 2))
                .shadow(.inner(color: .white.opacity(0.04), radius: 0, y: -1)),
                in: RoundedRectangle(cornerRadius: FrontPanelLayout.bayRadius)
            )
            .frameHighlight(cornerRadius: FrontPanelLayout.bayRadius, opacity: 0.05)
    }
}

/// Rounds its content's size up to whole points and keeps the content at the top leading corner.
///
/// The dot grids give the panel half-point heights, and its hosting view measures it in whole points. The host would
/// center the panel and leave a strip above it unpainted, so the rounding moves the remainder inside the metal at
/// the bottom.
private struct WholePointFrame: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(proposal) ?? .zero
        return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
    }
}

/// The front panel's measurements, from the approved mockup.
enum FrontPanelLayout {
    static let panelPadding = EdgeInsets(top: 26, leading: 30, bottom: 22, trailing: 30)
    static let bayMargin = EdgeInsets(top: 2, leading: 36, bottom: 20, trailing: 36)
    static let screenPadding = EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
    static let bayRadius: CGFloat = 10
    /// The width of the dark frame around every display.
    static let frameWidth: CGFloat = 2
}
