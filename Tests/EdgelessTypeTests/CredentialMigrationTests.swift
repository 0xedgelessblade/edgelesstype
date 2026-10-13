import XCTest
import CryptoKit
@testable import EdgelessTypeCore

final class CredentialMigrationTests: XCTestCase {
    private func fixture() throws -> (Data, Data) {
        let bytes = Data(repeating: 7, count: 32), key = SymmetricKey(data: bytes)
        let table = KeyTable(version: 1, activeKeyId: "fixture-key", keys: ["fixture-key": bytes.base64EncodedString()], records: ["openai": "record-a", "xai": "record-b"])
        var records: [String: EncryptedBlob] = [:]
        for id in ["record-a", "record-b"] {
            let sealed = try AES.GCM.seal(Data(("synthetic-" + id).utf8), using: key, authenticating: Data(("open-typeless-v1:" + id).utf8))
            records[id] = EncryptedBlob(iv: Data(sealed.nonce).base64EncodedString(), tag: sealed.tag.base64EncodedString(), ciphertext: sealed.ciphertext.base64EncodedString())
        }
        return (try JSONEncoder().encode(table), try JSONEncoder().encode(EncryptedFile(version: 1, cipher: "AES-256-GCM", keyId: "fixture-key", records: records)))
    }
    func testV2MigrationPreservesAllProviderSecretsAndRecordIDs() throws {
        let (key, old) = try fixture()
        let migrated = try CredentialMigration.convert(keyring: key, legacy: old)
        try CredentialMigration.verify(keyring: key, store: migrated)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let locations = SecretLocations(keyringDirectory: root, keyringFile: root.appendingPathComponent("ring.json"), storeFile: root.appendingPathComponent("store.json"))
        try key.write(to: locations.keyringFile); try migrated.write(to: locations.storeFile)
        XCTAssertEqual(try SecretStore(locations: locations, recordName: "openai").readSecret(), Data("synthetic-record-a".utf8))
        XCTAssertEqual(try SecretStore(locations: locations, recordName: "xai").readSecret(), Data("synthetic-record-b".utf8))
        XCTAssertFalse(String(decoding: migrated, as: UTF8.self).contains("synthetic"))
    }
    func testMigrationRejectsMismatchedKeysCorruptionAndRepeatedConversion() throws {
        let (key, old) = try fixture()
        let bad = KeyTable(version: 1, activeKeyId: "different", keys: [:], records: [:])
        XCTAssertThrowsError(try CredentialMigration.convert(keyring: JSONEncoder().encode(bad), legacy: old))
        var store = try JSONDecoder().decode(EncryptedFile.self, from: old)
        store.records["record-a"]?.tag = Data(repeating: 0, count: 16).base64EncodedString()
        XCTAssertThrowsError(try CredentialMigration.convert(keyring: key, legacy: JSONEncoder().encode(store)))
        let new = try CredentialMigration.convert(keyring: key, legacy: old)
        XCTAssertThrowsError(try CredentialMigration.convert(keyring: key, legacy: new))
        XCTAssertThrowsError(try CredentialMigration.verify(keyring: key, store: old))
    }
}
