import Foundation
import NeXTsoundWorkbench

// Polls `NXS_OPERATION_STATUS` on a loop so the owner can watch `inputPeak`/`outputPeak`/
// `isStreaming` live while audio plays, independent of CoreAudio and of this app's own UI.
// Connects directly by the board's fixed VID/PID (`BoardIdentity`), the same way
// `USBHostBoardTransport` already does; no IOHIDManager discovery needed for a single board.

let transport = USBHostBoardTransport()
print("Polling runtime status every 200 ms. Press Ctrl-C to stop.")

while true {
    do {
        let status = try await transport.requestRuntimeStatus()
        let line = String(
            format: "streaming=%@ input_peak=%.4f output_peak=%.4f underruns=%u overruns=%u max_us=%u muted=%@",
            status.isStreaming ? "yes" : "no",
            status.inputPeak,
            status.outputPeak,
            status.underrunCount,
            status.overrunCount,
            status.maxProcessingUs,
            status.hostIsMuted ? "yes" : "no"
        )
        print(line)
    } catch {
        print("error: \(error.localizedDescription)")
    }
    try await Task.sleep(for: .milliseconds(200))
}
