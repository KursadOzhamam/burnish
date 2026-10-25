import Foundation
import CryptoKit
import Protection

// Usage (from the repository root):
//   BlocklistBuilder keygen
//   BlocklistBuilder build [--lists <directory>] [--out <directory>]
//
// `build` signs the local lists in Tools/BlocklistBuilder/Lists and writes blocklist.json and
// blocklist.sig into the Protection package. Each list is plain text: one SHA-1 or SHA-256 per
// line, an optional name after a space, '#' for comments. Nothing is fetched from the network.
// The signing key (base64, from `keygen`) is read from $BURNISH_BLOCKLIST_KEY or
// ~/.config/burnish/blocklist-signing.key.

let configDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/burnish")
let args = Array(CommandLine.arguments.dropFirst())

/// A SHA-1 (40) or SHA-256 (64) digest in lowercase hex.
func isDigest(_ text: String) -> Bool {
    (text.count == 40 || text.count == 64) && text.allSatisfy { $0.isHexDigit && !$0.isUppercase }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// A secret from an environment variable, or else from a file in ~/.config/burnish.
func secret(env: String, file: String) -> String? {
    if let value = ProcessInfo.processInfo.environment[env], !value.isEmpty { return value }
    let url = configDirectory.appendingPathComponent(file)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

switch args.first {
case "keygen":
    let key = Curve25519.Signing.PrivateKey()
    print("PRIVATE (keep secret; save to ~/.config/burnish/blocklist-signing.key):")
    print(key.rawRepresentation.base64EncodedString())
    print("PUBLIC  (goes into BlocklistConfiguration.publicKeyBase64):")
    print(key.publicKey.rawRepresentation.base64EncodedString())

case "build":
    guard let keyText = secret(env: "BURNISH_BLOCKLIST_KEY", file: "blocklist-signing.key"),
          let raw = Data(base64Encoded: keyText),
          let signingKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        fail("No signing key. Run `BlocklistBuilder keygen` and save the PRIVATE line to ~/.config/burnish/blocklist-signing.key.")
    }
    func option(_ name: String) -> String? { args.firstIndex(of: name).map { args[$0 + 1] } }
    let out = URL(fileURLWithPath: option("--out") ?? "Packages/Features/Protection/Sources/Protection/Resources")
    let listsFolder = URL(fileURLWithPath: option("--lists") ?? "Tools/BlocklistBuilder/Lists")

    var byHash: [String: String] = [:]
    let listFiles = ((try? FileManager.default.contentsOfDirectory(at: listsFolder, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.pathExtension == "txt" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    for file in listFiles {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
        var kept = 0, rejected = 0
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            let hash = parts[0].lowercased()
            guard isDigest(hash) else { rejected += 1; continue }
            if byHash[hash] == nil { byHash[hash] = parts.count > 1 ? parts[1] : "macOS malware"; kept += 1 }
        }
        print("  \(file.lastPathComponent): \(kept) hashes" + (rejected > 0 ? ", \(rejected) malformed lines skipped" : ""))
    }
    guard !byHash.isEmpty else { fail("No hashes found in \(listsFolder.path); the existing list was left as it was.") }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    let version = Int(formatter.string(from: Date())) ?? 1
    let entries = byHash.sorted { $0.key < $1.key }.map { Blocklist.Entry(hash: $0.key, name: $0.value) }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let payload = try encoder.encode(Blocklist.Manifest(version: version, entries: entries))
    let signature = try signingKey.signature(for: payload)

    // Read back through the app's own loader, so what is written is exactly what the app accepts.
    let check = try Blocklist.load(payload: payload, signature: signature, publicKey: signingKey.publicKey)
    guard check.count == entries.count else { fail("Read-back mismatch: \(check.count) of \(entries.count) entries.") }

    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try payload.write(to: out.appendingPathComponent("blocklist.json"), options: .atomic)
    try signature.write(to: out.appendingPathComponent("blocklist.sig"), options: .atomic)

    let sha1Count = entries.filter { $0.hash.count == 40 }.count
    print("Wrote \(entries.count) hashes (\(sha1Count) SHA-1, \(entries.count - sha1Count) SHA-256), version \(version), to \(out.path)")
    if BlocklistConfiguration.publicKey?.rawRepresentation != signingKey.publicKey.rawRepresentation {
        print("NOTE: BlocklistConfiguration.publicKeyBase64 does not match this signing key; the app will ignore the list.")
        print("      Set it to: \(signingKey.publicKey.rawRepresentation.base64EncodedString())")
    }

default:
    print("usage: BlocklistBuilder keygen | build [--lists <directory>] [--out <directory>]")
    exit(1)
}
