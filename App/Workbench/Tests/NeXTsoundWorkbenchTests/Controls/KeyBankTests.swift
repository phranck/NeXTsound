import SwiftUI
import Testing
@testable import NeXTsoundWorkbench

struct KeyBankNavigationTests {
    @Test func theArrowKeysMoveOneKeyAndWrapAroundAtTheEnds() {
        #expect(KeyBankNavigation.index(after: 0, step: 1, count: 5) == 1)
        #expect(KeyBankNavigation.index(after: 4, step: 1, count: 5) == 0)
        #expect(KeyBankNavigation.index(after: 0, step: -1, count: 5) == 4)
        #expect(KeyBankNavigation.steps[.rightArrow] == 1)
        #expect(KeyBankNavigation.steps[.downArrow] == 1)
        #expect(KeyBankNavigation.steps[.leftArrow] == -1)
        #expect(KeyBankNavigation.steps[.upArrow] == -1)
    }
}

@MainActor
struct MomentaryKeyBankTests {
    /// Two six-letter captions under neighboring keys keep their glyphs at least three points apart, because a key is
    /// wider than a six-letter word. A caption's glyphs are the pixels it changes against a render of the bank
    /// without captions, so the keys and their frame drop out.
    @Test func neighboringCaptionsStandClearOfEachOther() throws {
        let bare = try RenderedPixels(Self.bank(captions: ["", ""]))
        let left = try RenderedPixels(Self.bank(captions: ["DELETE", ""])).changes(against: bare)
        let right = try RenderedPixels(Self.bank(captions: ["", "IMPORT"])).changes(against: bare)
        try #require(!left.isEmpty)
        try #require(!right.isEmpty)
        let distance = Self.closestDistance(between: left, and: right)
        #expect(distance >= Self.minimumDistance, "The captions' glyphs are \(distance) device pixels apart.")
    }
}

private extension MomentaryKeyBankTests {
    /// Three points in device pixels at scale 2. Under keys as wide as the kit's, the two words keep one point apart.
    static let minimumDistance = 6.0

    static func bank(captions: [String]) -> MomentaryKeyBank {
        MomentaryKeyBank(keys: captions.enumerated().map { index, caption in
            MomentaryKey(id: "key \(index)", caption: caption, name: Text(verbatim: caption)) {}
        })
    }

    /// The smallest distance in device pixels between a pixel of one set and a pixel of the other.
    static func closestDistance(between first: [PixelPosition], and second: [PixelPosition]) -> Double {
        var closest = Double.infinity
        for one in first {
            for other in second {
                let columns = Double(one.column - other.column)
                let rows = Double(one.row - other.row)
                closest = min(closest, (columns * columns + rows * rows).squareRoot())
            }
        }
        return closest
    }
}

@MainActor
struct KeyColorTests {
    /// A radio key keeps the kit's gray, and a momentary or push-on/push-off key takes the stripes' yellow, so only
    /// the push keys' renders hold yellow pixels.
    @Test func radioKeysStayGrayAndPushKeysTakeTheStripesYellow() throws {
        let radio = try RenderedPixels(KeyBank(
            "Radio",
            selection: .constant(0),
            keys: [KeyBankKey(value: 0, caption: Text(verbatim: "Key"), name: Text(verbatim: "Key"))]
        ))
        let momentary =
            try RenderedPixels(MomentaryKeyBank(keys: [MomentaryKey(id: "key", caption: "Key", name: Text(verbatim: "Key")) {}]))
        let latching = try RenderedPixels(LatchingKey(caption: "Key", isOn: .constant(false)))
        #expect(radio.yellowPixelCount == 0)
        #expect(momentary.yellowPixelCount > Self.minimumYellowPixels)
        #expect(latching.yellowPixelCount > Self.minimumYellowPixels)
    }
}

private extension KeyColorTests {
    /// About a quarter of a key's face at scale 2, which a yellow key passes many times over.
    static let minimumYellowPixels = 2000
}

/// A pixel's place in a render, counted from the top leading corner.
private struct PixelPosition {
    let column: Int
    let row: Int
}

private extension RenderedPixels {
    /// How far a channel may differ between two renders of the same view before the pixel counts as changed.
    static let changeThreshold = 24
    /// How far red stands above blue in a pixel of the push keys' yellow at the least. The captions' warm gray stays
    /// below 20.
    static let yellowMargin = 60

    /// The pixels in which red stands well above blue, which the push keys' yellow does and the gray keys, the
    /// captions and the LEDs do not.
    var yellowPixelCount: Int {
        var count = 0
        for row in 0 ..< height {
            for column in 0 ..< width {
                let pixel = pixel(column: column, row: row)
                if pixel.red - pixel.blue > Self.yellowMargin {
                    count += 1
                }
            }
        }
        return count
    }

    /// The pixels that differ from the same pixel of another render of the same size.
    func changes(against other: RenderedPixels) -> [PixelPosition] {
        var positions: [PixelPosition] = []
        for row in 0 ..< height {
            for column in 0 ..< width {
                let mine = pixel(column: column, row: row)
                let theirs = other.pixel(column: column, row: row)
                let difference = max(abs(mine.red - theirs.red), abs(mine.green - theirs.green), abs(mine.blue - theirs.blue))
                if difference > Self.changeThreshold {
                    positions.append(PixelPosition(column: column, row: row))
                }
            }
        }
        return positions
    }
}
