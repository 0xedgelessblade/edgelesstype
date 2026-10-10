import Foundation

public enum SoundCue: String, CaseIterable { case start, stop }

public enum SoundPreset: String, Codable, CaseIterable {
    case standard, soft, low

    public var title: String {
        switch self {
        case .standard: return "精修提示音（預設）"
        case .soft: return "柔和雙音（B）"
        case .low: return "低沉短音（C）"
        }
    }
    public func resource(for cue: SoundCue) -> String {
        self == .standard ? cue.rawValue : "\(rawValue)-\(cue.rawValue)"
    }
}

public struct SoundSettings: Codable, Equatable {
    public var preset: SoundPreset
    public init(preset: SoundPreset = .standard) { self.preset = preset }
}

public struct SoundSettingsStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> SoundSettings {
        guard FileManager.default.fileExists(atPath: url.path) else { return SoundSettings() }
        return try JSONDecoder().decode(SoundSettings.self, from: Data(contentsOf: url))
    }
    public func save(_ settings: SoundSettings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: url, options: .atomic)
    }
}
