import Testing
@testable import NeXTsoundWorkbench

struct DotMatrixWrapTests {
    @Test func aMessageWrapsBetweenWordsWithAHangingIndent() {
        let lines = DotMatrixWrap.lines(
            of: "The reported serial does not match the enumerated device.",
            width: 27,
            firstPrefix: "! ",
            laterPrefix: "  "
        )
        #expect(lines == ["! The reported serial does", "  not match the enumerated", "  device."])
    }

    @Test func aWordLongerThanALineTakesALineOfItsOwn() {
        let lines = DotMatrixWrap.lines(of: "a 0123456789abcdef", width: 10, firstPrefix: "> ", laterPrefix: "  ")
        #expect(lines == ["> a", "  0123456789abcdef"])
    }
}
