import NeXTsoundCore
import SwiftUI

struct EqualizerPlot: View {
    let settings: DSPSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EQ preview")
                .font(.headline)
            Canvas { context, size in
                let geometry = ResponsePlotGeometry(size: size)
                drawGrid(context: context, geometry: geometry)
                drawResponse(context: context, geometry: geometry)
            }
            .frame(height: 230)
            .background(WorkbenchTheme.ink, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("Analytical high-pass and equalizer response")
            Text("Filters only. Display ±\(Int(ResponsePlotGeometry.displayLimitDb)) dB. Not an acoustic measurement.")
                .foregroundStyle(.secondary)
        }
    }
}

private extension EqualizerPlot {
    func drawGrid(context: GraphicsContext, geometry: ResponsePlotGeometry) {
        var grid = Path()
        for gain: Double in [-12, 0, 12] {
            let point = geometry.point(frequencyHz: 20, decibels: gain)
            grid.move(to: point)
            grid.addLine(to: CGPoint(x: geometry.plot.maxX, y: point.y))
            context.draw(
                Text(gain.formatted(.number.sign(strategy: .always(includingZero: false))))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(WorkbenchTheme.screenText),
                at: CGPoint(x: geometry.plot.minX - 8, y: point.y),
                anchor: .trailing
            )
        }
        for frequency: Double in [20, 200, 2000, 20000] {
            let point = geometry.point(frequencyHz: frequency, decibels: ResponsePlotGeometry.displayLimitDb)
            grid.move(to: point)
            grid.addLine(to: CGPoint(x: point.x, y: geometry.plot.maxY))
            context.draw(
                Text(frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(WorkbenchTheme.screenText),
                at: CGPoint(x: point.x, y: geometry.plot.maxY + 18)
            )
        }
        context.stroke(grid, with: .color(WorkbenchTheme.grid), lineWidth: 1)
    }

    func drawResponse(context: GraphicsContext, geometry: ResponsePlotGeometry) {
        guard let points = try? ResponseCurve.samples(settings: settings) else {
            context.draw(Text("Response unavailable").foregroundStyle(WorkbenchTheme.screenText), at: geometry.plot.center)
            return
        }
        var curve = Path()
        for (index, sample) in points.enumerated() {
            let point = geometry.point(frequencyHz: sample.frequencyHz, decibels: sample.decibels)
            if index == 0 {
                curve.move(to: point)
            } else {
                curve.addLine(to: point)
            }
        }
        context.stroke(curve, with: .color(WorkbenchTheme.amber), lineWidth: 2)
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
