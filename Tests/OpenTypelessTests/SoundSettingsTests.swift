import XCTest
@testable import OpenTypelessCore

final class SoundSettingsTests: XCTestCase {
    func testSoundDefaultsToCurrentAndPersistsAcrossReloads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Config/sounds.json")
        let store = SoundSettingsStore(url: url)
        XCTAssertEqual(try store.load().preset, .standard)
        for preset in SoundPreset.allCases {
            try store.save(SoundSettings(preset: preset))
            XCTAssertEqual(try SoundSettingsStore(url: url).load().preset, preset)
        }
    }
    func testInvalidSoundPreferenceIsNotSilentlyRewritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("sounds.json")
        let invalid = Data("{\"preset\":\"unknown\"}".utf8)
        try invalid.write(to: url)
        XCTAssertThrowsError(try SoundSettingsStore(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), invalid)
    }
    func testExactlyThreePresetsHaveSixSeparateResources() {
        XCTAssertEqual(SoundPreset.allCases.count, 3)
        let names = SoundPreset.allCases.flatMap { preset in SoundCue.allCases.map { preset.resource(for: $0) } }
        XCTAssertEqual(Set(names), Set(["start", "stop", "soft-start", "soft-stop", "low-start", "low-stop"]))
    }
}
