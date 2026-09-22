// Checks an Ed25519 signature, the kind Sparkle puts in the appcast. Used by check-sparkle-key.sh.
//
// Usage: swift Scripts/verify-ed25519.swift <public key, base64> <signature, base64> <file>
// Exits 0 when the signature is valid, 1 when it isn't, 64 on bad arguments.

import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4,
    let publicKey = Data(base64Encoded: arguments[1].trimmingCharacters(in: .whitespacesAndNewlines)),
    let signature = Data(base64Encoded: arguments[2].trimmingCharacters(in: .whitespacesAndNewlines)),
    let data = FileManager.default.contents(atPath: arguments[3]),
    let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
else {
    FileHandle.standardError.write(Data("usage: verify-ed25519.swift <public key> <signature> <file>\n".utf8))
    exit(64)
}
exit(key.isValidSignature(signature, for: data) ? 0 : 1)
