import AppKit
import AVFoundation
import NikoCore

/// Plays the cue for an event from whichever source the user picked:
/// built-in (synthesised in memory), macOS system sounds, their own files,
/// or a sound pack. If the chosen source has nothing for an event, the
/// built-in cue is used so a selected event is never silent by accident.
@MainActor
final class SoundPlayer: NSObject, SoundPlaying, AVAudioPlayerDelegate {
    private weak var model: AppModel?
    private var active: [AVAudioPlayer] = []
    private var synthesized: [String: Data] = [:]
    private var systemSound: NSSound?

    init(model: AppModel) {
        self.model = model
    }

    func play(_ event: SoundEvent) {
        guard let model else { return }
        play(event, source: model.settings.soundSource, volume: model.settings.soundVolume)
    }

    /// Plays regardless of the on/off switches (the preview buttons in Settings).
    func preview(_ event: SoundEvent) {
        guard let model else { return }
        play(event, source: model.settings.soundSource, volume: model.settings.soundVolume)
    }

    func play(_ event: SoundEvent, source: SoundSource, volume: Double) {
        guard let model else { return }
        switch source {
        case .builtIn(let set):
            playData(builtIn(event, set), volume: volume)
        case .system:
            let sound = NSSound(named: model.settings.systemSound(for: event))
            sound?.volume = Float(volume)
            systemSound = sound
            sound?.play()
        case .files:
            if let url = UserSoundFiles.file(for: event, paths: model.paths) {
                playFile(url, volume: volume, fallback: event)
            } else {
                playData(builtIn(event, .island), volume: volume)
            }
        case .pack(let id):
            if let pack = SoundPack.discover(paths: model.paths, home: model.home).first(where: { $0.id == id }),
               let url = pack.file(for: event) {
                playFile(url, volume: volume, fallback: event)
            } else {
                playData(builtIn(event, .island), volume: volume)
            }
        }
    }

    private func builtIn(_ event: SoundEvent, _ set: BuiltInSoundSet) -> Data {
        let key = set.rawValue + "/" + event.rawValue
        if let cached = synthesized[key] { return cached }
        let data = SoundSynth.wav(for: event, set: set)
        synthesized[key] = data
        return data
    }

    private func playData(_ data: Data, volume: Double) {
        guard let player = try? AVAudioPlayer(data: data) else { return }
        start(player, volume: volume)
    }

    private func playFile(_ url: URL, volume: Double, fallback event: SoundEvent) {
        if let player = try? AVAudioPlayer(contentsOf: url) {
            start(player, volume: volume)
        } else {
            playData(builtIn(event, .island), volume: volume)
        }
    }

    private func start(_ player: AVAudioPlayer, volume: Double) {
        player.volume = Float(volume)
        player.delegate = self
        active.append(player)   // keep it alive until it has finished
        player.play()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in
            self.active.removeAll { ObjectIdentifier($0) == id }
        }
    }
}
