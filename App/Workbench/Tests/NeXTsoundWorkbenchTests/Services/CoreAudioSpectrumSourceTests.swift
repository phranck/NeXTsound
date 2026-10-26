import CoreAudio
import Testing
@testable import NeXTsoundWorkbench

struct CoreAudioSpectrumSourceTests {
    /// macOS gives a USB audio device a UID that holds its serial and a model UID that ends in its vendor and product
    /// ID, so the SoundBox with the verified serial is found among other USB devices and other SoundBoxes. The UIDs
    /// follow the form macOS gave another USB audio device on the bench.
    @Test func theSoundBoxIsFoundByItsSerialAndUSBIdentity() {
        let uid = "AppleUSBAudioEngine:LAYERED.work:NeXTsound:D4CDD489AFE28CC5:1"
        let modelUID = "NeXTsound:CAFE:4014"
        #expect(SoundBoxAudio.matches(uid: uid, modelUID: modelUID, serial: "D4CDD489AFE28CC5"))
        #expect(!SoundBoxAudio.matches(uid: uid, modelUID: modelUID, serial: "0123456789ABCDEF"))
        #expect(!SoundBoxAudio.matches(uid: uid, modelUID: "Anker PowerConf C200:291A:3369", serial: "D4CDD489AFE28CC5"))
        #expect(!SoundBoxAudio.matches(uid: uid, modelUID: modelUID, serial: ""))
    }

    /// Every channel of every buffer adds its share to each frame's mono sample, whether the stereo comes interleaved
    /// in one buffer or in one buffer per channel.
    @Test func everyChannelAddsItsShareToTheMonoSample() {
        #expect(Self.mono(of: [([1, 0, 1, 0], 2)]) == [0.5, 0.5])
        #expect(Self.mono(of: [([1, 1], 1), ([0, -1], 1)]) == [0.5, 0])
        #expect(Self.mono(of: []).isEmpty)
    }

    /// The capture reads 32-bit floating-point linear PCM and nothing else.
    @Test func onlyFloatingPointSamplesAreRead() {
        var format = AudioStreamBasicDescription()
        format.mFormatID = kAudioFormatLinearPCM
        format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
        format.mBitsPerChannel = 32
        #expect(SoundBoxAudio.readsSamples(of: format))
        format.mBitsPerChannel = 16
        #expect(!SoundBoxAudio.readsSamples(of: format))
        format.mBitsPerChannel = 32
        format.mFormatFlags = kAudioFormatFlagIsSignedInteger
        #expect(!SoundBoxAudio.readsSamples(of: format))
    }
}

private extension CoreAudioSpectrumSourceTests {
    /// Mixes buffers of interleaved samples with their channel counts down to mono, as the capture mixes the tap's.
    static func mono(of buffers: [(samples: [Float], channels: Int)]) -> [Float] {
        let list = AudioBufferList.allocate(maximumBuffers: max(buffers.count, 1))
        list.count = buffers.count
        let storage = buffers.map { buffer in
            let pointer = UnsafeMutableBufferPointer<Float>.allocate(capacity: buffer.samples.count)
            _ = pointer.initialize(from: buffer.samples)
            return pointer
        }
        defer {
            storage.forEach { $0.deallocate() }
            free(list.unsafeMutablePointer)
        }
        for (index, buffer) in buffers.enumerated() {
            list[index] = AudioBuffer(storage[index], numberOfChannels: buffer.channels)
        }
        var mono: [Float] = []
        SoundBoxAudio.mixDown(list, into: &mono)
        return mono
    }
}
