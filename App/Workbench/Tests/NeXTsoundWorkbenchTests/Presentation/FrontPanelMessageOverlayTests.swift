import Testing
@testable import NeXTsoundWorkbench

struct FrontPanelMessageOverlayTests {
    @Test func anErrorShowsAtOnceAndStays() {
        var overlay = FrontPanelMessageOverlay()
        let error = FrontPanelMessage(text: "The board did not reply in time.", isError: true)
        #expect(overlay.receive(error) == nil)
        #expect(overlay.shown == error)
    }

    @Test func anotherMessageShowsOnceItSettledAndLeavesAfterAWhile() {
        var overlay = FrontPanelMessageOverlay()
        let saved = FrontPanelMessage(text: "Settings saved")
        #expect(overlay.receive(saved) == FrontPanelMessageOverlay.settleDelay)
        #expect(overlay.shown == nil)
        #expect(overlay.settle(saved) == FrontPanelMessageOverlay.showDuration)
        #expect(overlay.shown == saved)
        overlay.expire(saved)
        #expect(overlay.shown == nil)
    }

    @Test func theLastShownMessageDoesNotShowAgainUntilAnotherOneHas() {
        var overlay = FrontPanelMessageOverlay()
        let hint = FrontPanelMessage(text: "Edits play live", tone: .normal)
        let saving = FrontPanelMessage(text: "Saving profiles…", tone: .normal)
        _ = overlay.receive(hint)
        _ = overlay.settle(hint)
        overlay.expire(hint)
        #expect(overlay.receive(saving) == FrontPanelMessageOverlay.settleDelay)
        #expect(overlay.receive(hint) == nil)
        #expect(overlay.shown == nil)
        _ = overlay.receive(nil)
        #expect(overlay.receive(hint) == FrontPanelMessageOverlay.settleDelay)
    }

    @Test func aSaveInProgressStaysAndANewMessageReplacesIt() {
        var overlay = FrontPanelMessageOverlay()
        let saving = FrontPanelMessage(text: "Saving to the SoundBox…", isLasting: true)
        let saved = FrontPanelMessage(text: "Settings saved")
        _ = overlay.receive(saving)
        #expect(overlay.settle(saving) == nil)
        #expect(overlay.receive(saved) == FrontPanelMessageOverlay.settleDelay)
        #expect(overlay.shown == nil)
        overlay.expire(saving)
        #expect(overlay.shown == nil)
    }

    @Test func anExpiredMessageLeavesANewerOneShown() {
        var overlay = FrontPanelMessageOverlay()
        let first = FrontPanelMessage(text: "Settings saved")
        let error = FrontPanelMessage(text: "Save failed.", isError: true)
        _ = overlay.receive(first)
        _ = overlay.settle(first)
        _ = overlay.receive(error)
        overlay.expire(first)
        #expect(overlay.shown == error)
    }
}
