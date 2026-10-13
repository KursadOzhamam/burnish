import Foundation
import CryptoKit
import Licensing

// Usage:
//   LicenseTool keygen
//   LicenseTool sign <private-key-base64> <email> <licence-id> <updates-until-YYYY-MM-DD> [device-limit]
let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "keygen":
    let key = Curve25519.Signing.PrivateKey()
    print("PRIVATE (keep secret, back up twice): \(key.rawRepresentation.base64EncodedString())")
    print("PUBLIC  (goes into the app):          \(key.publicKey.rawRepresentation.base64EncodedString())")
case "sign" where args.count >= 5:
    guard let raw = Data(base64Encoded: args[1]), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        FileHandle.standardError.write(Data("invalid private key\n".utf8)); exit(1)
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let until = formatter.date(from: args[4]) else {
        FileHandle.standardError.write(Data("date must be YYYY-MM-DD\n".utf8)); exit(1)
    }
    let payload = LicensePayload(
        licenseID: args[3], email: args[2], product: "burnish", updatesUntil: until,
        deviceLimit: args.count > 5 ? Int(args[5]) ?? 1 : 1, issuedAt: Date()
    )
    print(try LicenseFile.sign(payload, with: key))
default:
    print("usage: LicenseTool keygen | sign <private-key> <email> <licence-id> <updates-until> [device-limit]")
    exit(2)
}
