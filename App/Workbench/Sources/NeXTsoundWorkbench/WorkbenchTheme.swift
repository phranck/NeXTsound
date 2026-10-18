import SwiftUI

enum WorkbenchTheme {
    static let amber = Color(red: 0.929, green: 0.675, blue: 0.333)
    static let ink = Color(red: 0.090, green: 0.114, blue: 0.129)
    static let screenText = Color(red: 0.906, green: 0.886, blue: 0.847)
    static let grid = Color(red: 0.235, green: 0.267, blue: 0.286)
}

extension WorkbenchTheme {
    static func chassis(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.157, green: 0.157, blue: 0.149)
            : Color(red: 0.906, green: 0.886, blue: 0.847)
    }
}
