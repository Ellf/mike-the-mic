import AVFoundation
import Foundation

/// Speaks text with macOS `say`, one sentence group at a time, and exposes a
/// live mouth level from the audio meter so the face can lip-sync.
@MainActor
final class Speaker: NSObject, AVAudioPlayerDelegate {
    static let shared = Speaker()

    nonisolated static let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("TalkingFace", isDirectory: true)

    private var job: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var track: LipSyncTrack?
    private var latency: Double = 0
    private var finished: CheckedContinuation<Void, Never>?

    static func clearTempFiles() {
        let fm = FileManager.default
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        for file in (try? fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)) ?? []
        where ["aiff", "txt"].contains(file.pathExtension) {
            try? fm.removeItem(at: file)
        }
    }

    func speak(_ raw: String) {
        guard !Prefs.muted else { return }
        let chunks = SpeechText.chunks(SpeechText.clean(raw))
        guard !chunks.isEmpty else { return }
        stop()
        let voice = Prefs.voice
        job = Task { [weak self] in
            // Render the next chunk while the current one plays.
            var next: Task<Clip?, Never>? = Self.render(chunks[0], voice: voice)
            for i in chunks.indices {
                guard let clip = await next?.value else { break }
                next = i + 1 < chunks.count ? Self.render(chunks[i + 1], voice: voice) : nil
                if Task.isCancelled { break }
                await self?.play(clip)
                try? FileManager.default.removeItem(at: clip.url)
                if Task.isCancelled { break }
            }
            if !Task.isCancelled { self?.job = nil }
        }
    }

    func stop() {
        job?.cancel()
        job = nil
        player?.stop()
        player = nil
        resumePlayback()
    }

    /// Mouth shape for what's coming out of the speakers right now.
    func mouth() -> Mouth {
        guard let player, player.isPlaying, let track else { return .closed }
        return track.mouth(at: player.currentTime - latency + Prefs.lipSyncOffset)
    }

    private func play(_ clip: Clip) async {
        guard let p = try? AVAudioPlayer(contentsOf: clip.url) else { return }
        p.delegate = self
        player = p
        track = clip.track
        latency = OutputLatency.current()
        await withCheckedContinuation { c in
            finished = c
            if !p.play() { resumePlayback() }
        }
        if player === p { player = nil }
    }

    private func resumePlayback() {
        finished?.resume()
        finished = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.resumePlayback() }
    }

    struct Clip {
        let url: URL
        let track: LipSyncTrack?
    }

    nonisolated private static func render(_ text: String, voice: String?) -> Task<Clip?, Never> {
        Task.detached {
            let id = UUID().uuidString
            let input = tempDir.appendingPathComponent("\(id).txt")
            let output = tempDir.appendingPathComponent("\(id).aiff")
            do {
                try text.write(to: input, atomically: true, encoding: .utf8)
                defer { try? FileManager.default.removeItem(at: input) }
                let say = Process()
                say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                var args = ["-o", output.path, "-f", input.path]
                if let voice { args += ["-v", voice] }
                say.arguments = args
                try say.run()
                say.waitUntilExit()
                guard say.terminationStatus == 0 else { return nil }
                return Clip(url: output, track: LipSyncTrack(audioFile: output))
            } catch {
                NSLog("TalkingFace: say failed: \(error)")
                return nil
            }
        }
    }
}
