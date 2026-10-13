import CryptoKit
import Foundation

/// Explicit offline v1 -> v2 migration. Normal runtime accepts only v2 stores.
public enum CredentialMigration {
    private static let legacyAAD = "open-typeless-v1:"

    private static func key(_ bytes: Data, store: EncryptedFile) throws -> SymmetricKey {
        let table = try JSONDecoder().decode(KeyTable.self, from: bytes)
        guard table.version == 1, table.activeKeyId == store.keyId,
              let encoded = table.keys[table.activeKeyId],
              let data = Data(base64Encoded: encoded), data.count == 32,
              store.cipher == "AES-256-GCM" else { throw SecretError.invalidKeyTable }
        return SymmetricKey(data: data)
    }
    private static func open(_ blob: EncryptedBlob, id: String, key: SymmetricKey, aad: String) throws -> Data {
        guard let iv = Data(base64Encoded: blob.iv), let tag = Data(base64Encoded: blob.tag),
              let ciphertext = Data(base64Encoded: blob.ciphertext) else { throw SecretError.invalidStore }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(box, using: key, authenticating: Data((aad + id).utf8))
    }
    public static func convert(keyring: Data, legacy: Data) throws -> Data {
        let old = try JSONDecoder().decode(EncryptedFile.self, from: legacy)
        guard old.version == 1 else { throw SecretError.invalidStore }
        let secretKey = try key(keyring, store: old)
        var records: [String: EncryptedBlob] = [:]
        for (id, blob) in old.records {
            let plaintext = try open(blob, id: id, key: secretKey, aad: legacyAAD)
            let sealed = try AES.GCM.seal(plaintext, using: secretKey,
                                         authenticating: Data((SecretStore.aadPrefix + id).utf8))
            let converted = EncryptedBlob(iv: Data(sealed.nonce).base64EncodedString(), tag: sealed.tag.base64EncodedString(), ciphertext: sealed.ciphertext.base64EncodedString())
            guard try open(converted, id: id, key: secretKey, aad: SecretStore.aadPrefix) == plaintext else { throw SecretError.decryptFailed }
            records[id] = converted
        }
        let result = EncryptedFile(version: 2, cipher: old.cipher, keyId: old.keyId, records: records)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(result)
    }
    public static func verify(keyring: Data, store: Data) throws {
        let file = try JSONDecoder().decode(EncryptedFile.self, from: store)
        guard file.version == 2 else { throw SecretError.invalidStore }
        let secretKey = try key(keyring, store: file)
        for (id, blob) in file.records { _ = try open(blob, id: id, key: secretKey, aad: SecretStore.aadPrefix) }
    }
}
