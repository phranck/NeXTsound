import CoreAudio
import Foundation
import NeXTsoundCore

/// Measures the audio macOS sends to the SoundBox through a Core Audio tap on its output device.
///
/// The tap is private to the app and leaves the audio playing. A private aggregate device holds it, as Apple's
/// "Capturing system audio with Core Audio taps" describes. Starting and stopping run on a queue of their own, so the
/// main thread never waits for Core Audio, and the aggregate device's IO block runs on a second queue, which alone owns
/// the analyzer. On one queue, a stop could wait for an IO cycle that itself waits for that queue, because Core Audio
/// dispatches every IO block synchronously. The first start asks for permission to record system audio, which the
/// app's `NSAudioCaptureUsageDescription` explains.
struct CoreAudioSpectrumSource: SpectrumSource {
    func levels(serial: String) async throws -> AsyncStream<SpectrumLevels> {
        let controlQueue = DispatchQueue(label: "work.layered.NeXTsound.spectrum.control")
        let ioQueue = DispatchQueue(label: "work.layered.NeXTsound.spectrum.io", qos: .userInteractive)
        let (stream, continuation) = AsyncStream.makeStream(of: SpectrumLevels.self, bufferingPolicy: .bufferingNewest(1))
        let capture = try await withCheckedThrowingContinuation { (started: CheckedContinuation<SpectrumCapture, any Error>) in
            controlQueue.async {
                started.resume(with: Result {
                    try SpectrumCapture.start(serial: serial, ioQueue: ioQueue) { levels in
                        continuation.yield(levels)
                    }
                })
            }
        }
        continuation.onTermination = { _ in
            controlQueue.async {
                capture.stop()
            }
        }
        return stream
    }
}

/// How the app finds the SoundBox among the audio devices macOS lists, and reads the samples its tap delivers.
enum SoundBoxAudio {
    /// Whether the Core Audio device with `uid` and `modelUID` is the SoundBox with USB serial `serial`. macOS gives a
    /// USB audio device a model UID that ends in its vendor and product ID in hexadecimal, and a UID that holds its
    /// serial between colons.
    static func matches(uid: String, modelUID: String, serial: String) -> Bool {
        let identity = String(format: ":%04X:%04X", BoardIdentity.vendorID, BoardIdentity.productID)
        return !serial.isEmpty && modelUID.uppercased().hasSuffix(identity) && uid.contains(":\(serial):")
    }

    /// Whether the capture reads samples of `format`, which takes 32-bit floating-point linear PCM.
    static func readsSamples(of format: AudioStreamBasicDescription) -> Bool {
        format.mFormatID == kAudioFormatLinearPCM && format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32
    }

    /// Averages every channel of every buffer in `buffers` into one sample per frame, as the SoundBox's DSP averages
    /// its stereo input, whether the channels come interleaved in one buffer or in a buffer each. `mono` keeps its
    /// storage, so the mixdown allocates nothing once its first buffer has passed.
    static func mixDown(_ buffers: UnsafeMutableAudioBufferListPointer, into mono: inout [Float]) {
        mono.removeAll(keepingCapacity: true)
        let channelCount = buffers.reduce(0) { total, buffer in total + Int(buffer.mNumberChannels) }
        guard
            channelCount > 0,
            let first = buffers.first(where: { $0.mNumberChannels > 0 })
        else {
            return
        }
        let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * Int(first.mNumberChannels))
        mono.append(contentsOf: repeatElement(0, count: frames))
        for buffer in buffers {
            let channels = Int(buffer.mNumberChannels)
            guard
                channels > 0,
                let data = buffer.mData
            else {
                continue
            }
            let samples = data.assumingMemoryBound(to: Float.self)
            let bufferFrames = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
            for frame in 0 ..< bufferFrames {
                for channel in 0 ..< channels {
                    mono[frame] += samples[frame * channels + channel]
                }
            }
        }
        let share = 1 / Float(channelCount)
        for index in mono.indices {
            mono[index] *= share
        }
    }
}

/// A running tap on the SoundBox's output: the tap, the aggregate device that holds it, and the IO block that feeds the
/// analyzer.
///
/// `start` and `stop` run on the source's control queue and the IO block on its IO queue, which alone touches the
/// analyzer and the mono buffer. That split is what lets the capture pass between the two queues.
private final class SpectrumCapture: @unchecked Sendable {
    private let tap: AudioHardwareTap
    private let aggregate: AudioHardwareAggregateDevice
    private let analyzer: SpectrumAnalyzer
    private let onLevels: @Sendable (SpectrumLevels) -> Void
    private var mono: [Float] = []
    private var procID: AudioDeviceIOProcID?

    private init(
        tap: AudioHardwareTap,
        aggregate: AudioHardwareAggregateDevice,
        analyzer: SpectrumAnalyzer,
        onLevels: @escaping @Sendable (SpectrumLevels) -> Void
    ) {
        self.tap = tap
        self.aggregate = aggregate
        self.analyzer = analyzer
        self.onLevels = onLevels
    }
}

extension SpectrumCapture {
    /// The name the tap and the aggregate device carry, so a leftover of an interrupted run can be told apart.
    static let objectName = "NeXTsound Spectrum"
    /// The reason the display shows when Core Audio returns no object and no error for a tap or an aggregate device.
    static var unspecifiedFailureReason: String {
        AudioHardwareError(kAudioHardwareUnspecifiedError).localizedDescription
    }

    /// Taps the output of the SoundBox with USB serial `serial` and starts the IO block on `ioQueue`, which hands every
    /// update of the bands' levels to `onLevels`. A start that fails part of the way destroys what it created.
    ///
    /// - Throws: `SpectrumError` with the reason the display shows.
    static func start(
        serial: String,
        ioQueue: DispatchQueue,
        onLevels: @escaping @Sendable (SpectrumLevels) -> Void
    ) throws -> SpectrumCapture {
        let system = AudioHardwareSystem.shared
        let deviceUID = try soundBoxOutputUID(serial: serial)
        guard let tap = try coreAudio({ try system.makeProcessTap(description: tapDescription(deviceUID: deviceUID)) }) else {
            throw SpectrumError.captureFailed(unspecifiedFailureReason)
        }
        let aggregate: AudioHardwareAggregateDevice
        let analyzer: SpectrumAnalyzer
        do {
            let format = try coreAudio { try tap.format }
            guard SoundBoxAudio.readsSamples(of: format) else {
                throw SpectrumError.unsupportedAudioFormat
            }
            analyzer = try SpectrumAnalyzer(sampleRate: format.mSampleRate)
            guard let made = try coreAudio({ try system.makeAggregateDevice(description: aggregateDescription()) }) else {
                throw SpectrumError.captureFailed(unspecifiedFailureReason)
            }
            aggregate = made
        } catch {
            try? system.destroyProcessTap(tap)
            throw error
        }
        let capture = SpectrumCapture(tap: tap, aggregate: aggregate, analyzer: analyzer, onLevels: onLevels)
        do {
            try coreAudio { try aggregate.setSubtaps([tap]) }
            try capture.run(on: ioQueue)
        } catch {
            capture.stop()
            throw error
        }
        return capture
    }

    /// Stops the IO block and destroys the aggregate device and the tap.
    func stop() {
        let system = AudioHardwareSystem.shared
        if let procID {
            try? aggregate.stop(IOProcID: procID)
            AudioDeviceDestroyIOProcID(aggregate.id, procID)
            self.procID = nil
        }
        try? system.destroyAggregateDevice(aggregate)
        try? system.destroyProcessTap(tap)
    }
}

private extension SpectrumCapture {
    /// The UID of the SoundBox's output device with USB serial `serial`. A device that does not answer for its UIDs or
    /// its streams is passed over, so one odd device does not hide the SoundBox.
    static func soundBoxOutputUID(serial: String) throws -> String {
        let devices = try coreAudio { try AudioHardwareSystem.shared.devices }
        for device in devices {
            guard
                let uid = try? device.uid,
                let modelUID = try? device.modelUID,
                SoundBoxAudio.matches(uid: uid, modelUID: modelUID, serial: serial),
                let streams = try? device.streams,
                streams.contains(where: { (try? $0.direction) == .output })
            else {
                continue
            }
            return uid
        }
        throw SpectrumError.soundBoxAudioNotFound
    }

    /// A private tap of every process's audio on the device's first output stream, which leaves that audio playing.
    static func tapDescription(deviceUID: String) -> CATapDescription {
        let description = CATapDescription(excludingProcesses: [], deviceUID: deviceUID, stream: 0)
        description.name = objectName
        description.isPrivate = true
        description.muteBehavior = .unmuted
        return description
    }

    /// A private aggregate device, which the system drops when the app quits, with a UID of its own for every capture.
    static func aggregateDescription() -> [String: Any] {
        [
            kAudioAggregateDeviceNameKey: objectName,
            kAudioAggregateDeviceUIDKey: "work.layered.NeXTsound.spectrum.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: 1,
        ]
    }

    /// Runs a Core Audio call and turns its error into the reason the display shows.
    static func coreAudio<Value>(_ call: () throws -> Value) throws -> Value {
        do {
            return try call()
        } catch let error as SpectrumError {
            throw error
        } catch {
            throw SpectrumError.captureFailed(error.localizedDescription)
        }
    }

    /// Creates the IO block on `ioQueue` and starts the aggregate device.
    func run(on ioQueue: DispatchQueue) throws {
        var created: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&created, aggregate.id, ioQueue) { [weak self] _, input, _, _, _ in
            self?.receive(input)
        }
        guard
            status == noErr,
            let created
        else {
            throw SpectrumError.captureFailed(AudioHardwareError(status).localizedDescription)
        }
        procID = created
        try Self.coreAudio { try aggregate.start(IOProcID: created) }
    }

    /// Mixes one IO cycle's input down to mono and hands the analyzer's update, when it completes one, onward.
    func receive(_ input: UnsafePointer<AudioBufferList>) {
        SoundBoxAudio.mixDown(UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)), into: &mono)
        if let levels = analyzer.append(mono) {
            onLevels(levels)
        }
    }
}
