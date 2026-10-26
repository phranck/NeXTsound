import CoreAudio
import Testing
@testable import NeXTsoundWorkbench

struct CoreAudioSpectrumSourceTests {
    /// macOS gives a USB audio device a UID that holds its serial and a model UID that ends in its vendor and product
    /// ID, so the SoundBox with the verified serial is found among other USB devices and other SoundBoxes. The UIDs are
    /// the ones macOS gave the bench specimen on 2026-10-26.
    @Test func theSoundBoxIsFoundByItsSerialAndUSBIdentity() {
        let uid = "AppleUSBAudioEngine:Layered:NeXT SoundBox mini:D4CDD489AFE28CC5:1"
        let modelUID = "NeXT SoundBox mini:CAFE:4014"
        #expect(SoundBoxAudio.matches(uid: uid, modelUID: modelUID, serial: "D4CDD489AFE28CC5"))
        #expect(!SoundBoxAudio.matches(uid: uid, modelUID: modelUID, serial: "0123456789ABCDEF"))
        #expect(!SoundBoxAudio.matches(uid: uid, modelUID: "Anker PowerConf C200:291A:3369", serial: "D4CDD489AFE28CC5"))
        #expect(!SoundBoxAudio.matches(uid: uid, modelUID: modelUID, serial: ""))
    }

    /// The first two channels become interleaved left and right samples for the DSP, whether they come interleaved in
    /// one buffer or in a buffer each, a single channel feeds both sides, and further channels are left out.
    @Test func theFirstTwoChannelsBecomeInterleavedStereo() {
        #expect(Self.stereo(of: [([1, 2, 3, 4], 2)]) == [1, 2, 3, 4])
        #expect(Self.stereo(of: [([1, 3], 1), ([2, 4], 1)]) == [1, 2, 3, 4])
        #expect(Self.stereo(of: [([1, 3], 1)]) == [1, 1, 3, 3])
        #expect(Self.stereo(of: [([1, 2, 9, 3, 4, 9], 3)]) == [1, 2, 3, 4])
        #expect(Self.stereo(of: []).isEmpty)
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
    /// Interleaves the first two channels of buffers with their channel counts, as the capture interleaves the tap's.
    static func stereo(of buffers: [(samples: [Float], channels: Int)]) -> [Float] {
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
        var stereo: [Float] = []
        SoundBoxAudio.interleaveStereo(list, into: &stereo)
        return stereo
    }
}
