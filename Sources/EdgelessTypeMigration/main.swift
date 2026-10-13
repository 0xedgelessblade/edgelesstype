import Foundation
import Darwin
import EdgelessTypeCore

umask(0o077)
let args = Array(CommandLine.arguments.dropFirst())
do {
    if args.count == 4 && args[0] == "convert" {
        let key = try Data(contentsOf: URL(fileURLWithPath: args[1]))
        let source = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        let destination = URL(fileURLWithPath: args[3])
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw SecretError.invalidStore }
        let result = try CredentialMigration.convert(keyring: key, legacy: source)
        try CredentialMigration.verify(keyring: key, store: result)
        try result.write(to: destination, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        print("Credential conversion and in-memory equality verification passed.")
    } else if args.count == 3 && args[0] == "verify" {
        try CredentialMigration.verify(keyring: Data(contentsOf: URL(fileURLWithPath: args[1])), store: Data(contentsOf: URL(fileURLWithPath: args[2])))
        print("Credential verification passed.")
    } else { throw SecretError.invalidStore }
} catch {
    FileHandle.standardError.write(Data("Credential migration failed; no secret contents were printed.\n".utf8))
    exit(1)
}
