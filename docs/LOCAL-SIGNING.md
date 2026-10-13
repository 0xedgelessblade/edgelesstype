# Stable signing for a private local app

Public CI builds remain ad-hoc signed and contain no signing secrets. Do not run the public build as the daily permission-granted app.

The local updater requires `LOCAL-SIGNING.json` in the private runtime, with `identitySHA1` (the fingerprint of an existing Keychain code-signing identity) and `bundleIdentifier` set to `edgelessblade.opentypeless.local`. The local bundle ID is distinct from the public build and old test copies. The profile contains no private key but must not be published or synchronized into the public checkout.

Use a user-selected existing certificate, or, only with explicit permission, create a dedicated local code-signing certificate. Keep its private key in the user's Keychain, never in Git or the runtime folder. Do not export existing private keys, silently regenerate the signer, grant broad key access, add TLS trust, disable Gatekeeper, or change the TCC database. Keychain or system permission prompts belong to the user. A local certificate is not Developer ID or notarization and is not suitable as public distribution assurance.

The updater signs the local app with the exact identity fingerprint, verifies the signature, rejects a bare `cdhash` requirement and requires each subsequent update to satisfy the previous designated requirement. A failed update restores executable, metadata, public assets and signature bytes without re-signing the rollback ad hoc. Missing/changed signers stop the update before continuing; restore the original signer or plan an explicit identity migration instead of silently falling back.

One final user approval of Accessibility/Input Monitoring and microphone access may be needed during migration. This does not guarantee that macOS will never ask again after certificate replacement, permission revocation or system policy changes. Test two different locally signed builds against the same requirement, then separately confirm real Fn and paste behavior after the user grants access.

Apple references: [Code Signing Tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html) and [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).
