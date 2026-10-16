import AVFoundation
import CoreAudio

/// What the mouth should look like at one instant.
struct Mouth {
    /// 0 = closed, 1 = fully open.
    var open: Float = 0
    /// 0 = round ("oh"), 1 = wide and flat ("ee", "s", "f").
    var wide: Float = 0
    static let closed = Mouth()
}

/// Loudness and "hissiness" of a rendered clip, sampled every 10ms.
struct LipSyncTrack {
    static let step: Double = 0.01
    let open: [Float]
    let wide: [Float]

    func mouth(at time: Double) -> Mouth {
        guard time >= 0, !open.isEmpty else { return .closed }
        let pos = time / Self.step
        let i = Int(pos)
        guard i < open.count - 1 else { return .closed }
        let f = Float(pos - Double(i))
        return Mouth(open: open[i] + (open[i + 1] - open[i]) * f,
                     wide: wide[i] + (wide[i + 1] - wide[i]) * f)
    }

    init?(audioFile url: URL) {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let samples = buffer.floatChannelData?[0] else { return nil }
        let count = Int(buffer.frameLength)
        let window = max(1, Int(file.processingFormat.sampleRate * Self.step))

        var rms: [Float] = []
        var zcr: [Float] = []
        var start = 0
        while start < count {
            let end = min(count, start + window)
            var sum: Float = 0
            var crossings = 0
            for j in start..<end {
                sum += samples[j] * samples[j]
                if j > start, (samples[j] >= 0) != (samples[j - 1] >= 0) { crossings += 1 }
            }
            rms.append((sum / Float(end - start)).squareRoot())
            zcr.append(Float(crossings) / Float(end - start))
            start = end
        }

        // Normalise loudness to this clip so quiet and loud voices both animate fully.
        let peak = max(rms.sorted()[Int(Double(rms.count - 1) * 0.95)], 1e-4)
        var open = rms.map { level -> Float in
            let n = min(1, level / peak)
            return n < 0.08 ? 0 : min(1, ((n - 0.08) / 0.92).squareRoot())
        }
        // Open instantly, close over ~40ms so syllables read as distinct movements.
        for i in 1..<max(1, open.count) where open[i] < open[i - 1] {
            open[i] = max(open[i], open[i - 1] - 0.25)
        }
        // Many zero crossings = hissy consonants / "ee" sounds.
        let wide = zcr.map { min(1, max(0, ($0 - 0.06) / 0.2)) }

        self.open = open
        self.wide = wide
    }
}

enum OutputLatency {
    /// Delay between the player's position and sound leaving the speakers, in seconds.
    static func current() -> Double {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
        else { return 0 }

        func uint(_ selector: AudioObjectPropertySelector) -> UInt32 {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : 0
        }
        var rate: Float64 = 0
        size = UInt32(MemoryLayout<Float64>.size)
        address.mSelector = kAudioDevicePropertyNominalSampleRate
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr, rate > 0 else { return 0 }

        let frames = uint(kAudioDevicePropertyLatency) + uint(kAudioDevicePropertySafetyOffset)
            + uint(kAudioDevicePropertyBufferFrameSize)
        return Double(frames) / rate
    }
}
