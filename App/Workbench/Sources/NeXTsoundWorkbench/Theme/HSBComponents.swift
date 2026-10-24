/// A 24-bit sRGB value's hue, saturation and brightness, each from 0 to 1, as `Color(hue:saturation:brightness:)`
/// takes them.
struct HSBComponents {
    let hue: Double
    let saturation: Double
    let brightness: Double

    init(_ hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        let brightest = max(red, green, blue)
        let range = brightest - min(red, green, blue)
        brightness = brightest
        saturation = brightest > 0 ? range / brightest : 0
        guard range > 0 else {
            hue = 0
            return
        }
        let sector: Double = switch brightest {
        case red: (green - blue) / range
        case green: (blue - red) / range + 2
        default: (red - green) / range + 4
        }
        hue = (sector / 6 + 1).truncatingRemainder(dividingBy: 1)
    }
}
