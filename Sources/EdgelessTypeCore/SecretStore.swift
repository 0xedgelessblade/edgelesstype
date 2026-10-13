import CryptoKit
import Foundation
import Security

public enum SecretError: Error, Equatable {
    case refusingSyncedFolder
    case missingKeyTable
    case invalidKeyTable
    case invalidStore
    case missingRecord
    case decryptFailed
    case emptySecret
    case notATerminal
}

public struct SecretLocations: Equatable {
    public var keyringDirectory: URL
    public var keyringFile: URL
    public var storeFile: URL

    public init(keyringDirectory: URL, keyringFile: URL, storeFile: URL) {
        self.keyringDirectory = keyringDirectory
        self.keyringFile = keyringFile
        self.storeFile = storeFile
    }

    public static func production(projectRoot: URL) -> SecretLocations {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/codex-secrets", isDirectory: true)
        return SecretLocations(
            keyringDirectory: directory,
            keyringFile: directory.appendingPathComponent("edgelesstype-keyring.json"),
            storeFile: projectRoot.appendingPathComponent("private/credentials.encrypted.json")
        )
    }
}

public struct SecretStore {
    public let locations: SecretLocations
    public let recordName: String
    public static let aadPrefix = "edgelesstype-v2:"

    public init(locations: SecretLocations, recordName: String = "xai") {
        self.locations = locations
        self.recordName = recordName
    }

    public func verify() throws -> Bool {
        try refuseSyncedKeyring()
        guard FileManager.default.fileExists(atPath: locations.keyringFile.path),
              FileManager.default.fileExists(atPath: locations.storeFile.path) else {
            return false
        }
        _ = try readSecret()
        return true
    }

    public func save(secret: Data) throws {
        try refuseSyncedKeyring()
        guard !secret.isEmpty else { throw SecretError.emptySecret }
        let fm = FileManager.default
        try fm.createDirectory(at: locations.keyringDirectory, withIntermediateDirectories: true)
        try chmod(locations.keyringDirectory, 0o700)
        try fm.createDirectory(at: locations.storeFile.deletingLastPathComponent(), withIntermediateDirectories: true)

        let keyring = try loadOrCreateKeyring()
        let key = try decodeKey(keyring)
        let recordId = keyring.records[recordName] ?? "record_\(randomHex(8))"
        var updated = keyring
        updated.records[recordName] = recordId
        let blob = try encrypt(secret, key: key, recordId: recordId)
        var store = fm.fileExists(atPath: locations.storeFile.path)
            ? try loadStore() : EncryptedFile(version: 2, cipher: "AES-256-GCM", keyId: keyring.activeKeyId, records: [:])
        guard store.keyId == keyring.activeKeyId else { throw SecretError.invalidStore }
        store.cipher = "AES-256-GCM"
        store.version = 2
        store.records[recordId] = blob
        try writeJSON(updated, to: locations.keyringFile)
        try chmod(locations.keyringFile, 0o600)
        try writeJSON(store, to: locations.storeFile)
        try chmod(locations.storeFile, 0o600)
    }

    public func readSecret() throws -> Data {
        try refuseSyncedKeyring()
        let keyring = try loadKeyring()
        let store = try loadStore()
        guard store.version == 2, store.cipher == "AES-256-GCM", store.keyId == keyring.activeKeyId else {
            throw SecretError.invalidStore
        }
        guard let recordId = keyring.records[recordName], let blob = store.records[recordId] else {
            throw SecretError.missingRecord
        }
        return try decrypt(blob, key: try decodeKey(keyring), recordId: recordId)
    }

    public func delete() throws {
        try refuseSyncedKeyring()
        guard FileManager.default.fileExists(atPath: locations.storeFile.path) else { return }
        var store = try loadStore()
        let keyring = try loadKeyring()
        guard let recordId = keyring.records[recordName] else { return }
        store.records.removeValue(forKey: recordId)
        try writeJSON(store, to: locations.storeFile)
        try chmod(locations.storeFile, 0o600)
    }

    public func syncedJSONKeys() throws -> Set<String> {
        let store = try loadStore()
        let keys: Set<String> = ["version", "cipher", "keyId", "records", "iv", "tag", "ciphertext"]
        for blob in store.records.values {
            _ = blob
        }
        return keys
    }

    private func refuseSyncedKeyring() throws {
        let path = locations.keyringFile.path
        if path.contains("CloudStorage") || path.contains("GoogleDrive") || path.contains("其他電腦") {
            throw SecretError.refusingSyncedFolder
        }
    }

    private func loadOrCreateKeyring() throws -> KeyTable {
        if FileManager.default.fileExists(atPath: locations.keyringFile.path) {
            return try loadKeyring()
        }
        let keyId = "key_\(randomHex(8))"
        let table = KeyTable(
            version: 1,
            activeKeyId: keyId,
            keys: [keyId: randomBytes(32).base64EncodedString()],
            records: [recordName: "record_\(randomHex(8))"]
        )
        try writeJSON(table, to: locations.keyringFile)
        try chmod(locations.keyringFile, 0o600)
        return table
    }

    private func loadKeyring() throws -> KeyTable {
        guard let data = FileManager.default.contents(atPath: locations.keyringFile.path) else {
            throw SecretError.missingKeyTable
        }
        let table = try JSONDecoder().decode(KeyTable.self, from: data)
        guard table.version == 1, table.keys[table.activeKeyId] != nil else {
            throw SecretError.invalidKeyTable
        }
        return table
    }

    private func loadStore() throws -> EncryptedFile {
        guard let data = FileManager.default.contents(atPath: locations.storeFile.path) else {
            throw SecretError.invalidStore
        }
        return try JSONDecoder().decode(EncryptedFile.self, from: data)
    }

    private func decodeKey(_ table: KeyTable) throws -> SymmetricKey {
        guard let encoded = table.keys[table.activeKeyId], let data = Data(base64Encoded: encoded), data.count == 32 else {
            throw SecretError.invalidKeyTable
        }
        return SymmetricKey(data: data)
    }

    private func encrypt(_ secret: Data, key: SymmetricKey, recordId: String) throws -> EncryptedBlob {
        let nonce = try AES.GCM.Nonce(data: randomBytes(12))
        let aad = Data("\(Self.aadPrefix)\(recordId)".utf8)
        let sealed = try AES.GCM.seal(secret, using: key, nonce: nonce, authenticating: aad)
        return EncryptedBlob(
            iv: Data(nonce).base64EncodedString(),
            tag: sealed.tag.base64EncodedString(),
            ciphertext: sealed.ciphertext.base64EncodedString()
        )
    }

    private func decrypt(_ blob: EncryptedBlob, key: SymmetricKey, recordId: String) throws -> Data {
        guard let iv = Data(base64Encoded: blob.iv),
              let tag = Data(base64Encoded: blob.tag),
              let ciphertext = Data(base64Encoded: blob.ciphertext) else {
            throw SecretError.decryptFailed
        }
        let nonce = try AES.GCM.Nonce(data: iv)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let aad = Data("\(Self.aadPrefix)\(recordId)".utf8)
        do {
            return try AES.GCM.open(box, using: key, authenticating: aad)
        } catch {
            throw SecretError.decryptFailed
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        let temp = url.appendingPathExtension("tmp-\(ProcessInfo.processInfo.processIdentifier)")
        try data.write(to: temp, options: [.atomic])
        try chmod(temp, 0o600)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: url)
        }
        try chmod(url, 0o600)
    }

    private func chmod(_ url: URL, _ mode: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    private func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return data
    }

    private func randomHex(_ count: Int) -> String {
        randomBytes(count).map { String(format: "%02x", $0) }.joined()
    }
}

struct KeyTable: Codable {
    var version: Int
    var activeKeyId: String
    var keys: [String: String]
    var records: [String: String]
}

struct EncryptedFile: Codable {
    var version: Int
    var cipher: String
    var keyId: String
    var records: [String: EncryptedBlob]
}

struct EncryptedBlob: Codable {
    var iv: String
    var tag: String
    var ciphertext: String
}
