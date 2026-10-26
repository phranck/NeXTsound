import Foundation
import NeXTsoundDSP
import NeXTsoundProtocol

public struct EQResponse: Sendable {
    private let configuration: nxs_dsp_configuration_t

    public init(settings: DSPSettings) throws {
        configuration = try settings.dspConfiguration()
    }
}

public extension EQResponse {
    func decibels(at frequencyHz: Double) throws -> Double {
        var prepared = configuration
        let magnitude = nxs_dsp_eq_magnitude(&prepared, frequencyHz)
        guard magnitude.isFinite else {
            throw WireError(result: NXS_RESULT_INVALID_PARAMETERS)
        }
        return 20 * log10(max(magnitude, Double.leastNormalMagnitude))
    }
}
