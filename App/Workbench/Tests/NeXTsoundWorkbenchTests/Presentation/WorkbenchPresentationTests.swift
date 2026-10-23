import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

struct BoardConnectionStatePresentationTests {
    @Test func onlyAVerifiedBoardHasCapabilities() {
        let capabilities = fixtureCapabilities()
        #expect(BoardConnectionState.verified(capabilities).verifiedCapabilities == capabilities)
        #expect(BoardConnectionState.disconnected.verifiedCapabilities == nil)
        #expect(BoardConnectionState.detected.verifiedCapabilities == nil)
        #expect(BoardConnectionState.mismatched("Wrong firmware").verifiedCapabilities == nil)
    }
}
