import Testing
@testable import NeXTsoundWorkbench

struct HSBComponentsTests {
    /// The stripes' red has a hue of about 16 degrees, a gray has neither hue nor saturation, and the pure colors
    /// fall on their thirds of the hue circle, with a pink just short of the circle's end.
    @Test func aColorSplitsIntoHueSaturationAndBrightness() {
        let red = HSBComponents(FrontPanelPalette.stripeRed)
        #expect(abs(red.hue - 16.4 / 360) < 0.001)
        #expect(abs(red.saturation - 0.889) < 0.001)
        #expect(abs(red.brightness - 0.776) < 0.001)
        let gray = HSBComponents(0x808080)
        #expect(gray.hue == 0 && gray.saturation == 0)
        #expect(abs(HSBComponents(0x00FF00).hue - 1 / 3) < 0.001)
        #expect(abs(HSBComponents(0x0000FF).hue - 2 / 3) < 0.001)
        #expect(abs(HSBComponents(0xFF0080).hue - 329.9 / 360) < 0.001)
    }
}
