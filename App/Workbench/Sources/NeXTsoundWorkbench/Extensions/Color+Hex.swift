import SwiftUI

extension Color {
    /// A color from a 24-bit sRGB value, written as `0xRRGGBB`.
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// Two 24-bit sRGB values mixed channel by channel, `secondShare` of the second and the rest of the first.
    init(mixing first: UInt32, _ second: UInt32, secondShare: Double = 0.5) {
        func channel(_ shift: UInt32) -> Double {
            let firstValue = Double((first >> shift) & 0xFF)
            let secondValue = Double((second >> shift) & 0xFF)
            return (firstValue * (1 - secondShare) + secondValue * secondShare) / 255
        }
        self.init(red: channel(16), green: channel(8), blue: channel(0))
    }
}
