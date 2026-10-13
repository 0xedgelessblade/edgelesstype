import AppKit
import EdgelessTypeCore

/// One owner for recording cues and cancellable start/stop previews.
final class SoundPlayer {
    private let store: SoundSettingsStore
    private let bundle: Bundle
    private var cue: NSSound?
    private var generation = UUID()
    private var previewTail: DispatchWorkItem?
    private(set) var preset: SoundPreset

    init(store: SoundSettingsStore, bundle: Bundle = .main) {
        self.store = store; self.bundle = bundle
        preset = (try? store.load().preset) ?? .standard
    }
    func select(_ value: SoundPreset) throws {
        try store.save(SoundSettings(preset: value))
        cancelPreview(); preset = value
    }
    func cancelPreview() {
        generation = UUID()
        previewTail?.cancel(); previewTail = nil
        cue?.stop()
    }
    func cueURL(_ phase: SoundCue, preset override: SoundPreset? = nil) -> URL? {
        let selected = override ?? preset
        return bundle.url(forResource: selected.resource(for: phase), withExtension: "wav")
            ?? bundle.url(forResource: SoundPreset.standard.resource(for: phase), withExtension: "wav")
    }
    private func sound(_ phase: SoundCue, preset: SoundPreset) -> NSSound? {
        cueURL(phase, preset: preset).flatMap { NSSound(contentsOf: $0, byReference: true) }
    }
    @discardableResult func play(_ phase: SoundCue, preset override: SoundPreset? = nil) -> TimeInterval {
        cancelPreview()
        cue = sound(phase, preset: override ?? preset)
        guard cue?.play() == true else { return 0 }
        return cue?.duration ?? 0
    }
    @discardableResult func preview() -> Bool {
        cancelPreview()
        guard let start = sound(.start, preset: preset), let stop = sound(.stop, preset: preset) else { return false }
        cue = start; start.play()
        let token = generation
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.cue = stop; stop.play(); self.previewTail = nil
        }
        previewTail = item
        DispatchQueue.main.asyncAfter(deadline: .now() + start.duration + 0.65, execute: item)
        return true
    }
}
