import Foundation
import CryptoKit
import Protection

// Usage (from the repository root):
//   BlocklistBuilder keygen
//   BlocklistBuilder build [--fetch] [--lists <directory>] [--out <directory>]
//   BlocklistBuilder fetch                       (same as build --fetch)
//
// `build` signs the local lists in Tools/BlocklistBuilder/Lists (SHA-1 or SHA-256, one per line).
// `fetch` also asks MalwareBazaar (abuse.ch, data under CC0) for macOS samples and writes the signed list
// into the Protection package. Only SHA-256 hashes and family names are stored; no sample is ever
// downloaded. It reads:
//   - the abuse.ch Auth-Key from $ABUSE_CH_AUTH_KEY or ~/.config/burnish/abuse-ch.key
//   - the signing key (base64, from `keygen`) from $BURNISH_BLOCKLIST_KEY or
//     ~/.config/burnish/blocklist-signing.key

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

// MARK: MalwareBazaar

/// One sample as MalwareBazaar describes it. Only the fields the list needs.
struct Sample: Decodable {
    let sha256Hash: String
    let signature: String?
    let fileType: String?
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case sha256Hash = "sha256_hash", signature, fileType = "file_type", tags
    }
}

struct Response: Decodable {
    let queryStatus: String
    let data: [Sample]?

    enum CodingKeys: String, CodingKey {
        case queryStatus = "query_status", data
    }
}

/// Queries that together cover macOS malware: Mach-O and disk-image samples, and the tags analysts
/// use for macOS families. Overlap is expected and removed by hash.
let queries: [[String: String]] = [
    ["query": "get_file_type", "file_type": "macho"],
    ["query": "get_file_type", "file_type": "dmg"]
] + ["macOS", "macos", "AMOS", "AtomicStealer", "Poseidon", "Banshee", "Cuckoo", "MacStealer", "RustBucket", "XLoader"]
    .map { ["query": "get_taginfo", "tag": $0] }

/// File types that cannot run on a Mac. A tag such as AMOS also labels the Windows loaders that
/// deliver it; their hashes would never match a file on a Mac, so they only make the list longer.
let windowsOnlyTypes: Set<String> = ["exe", "dll", "msi", "apk", "elf", "lnk", "ps1", "bat", "vbs"]

func fetch(_ parameters: [String: String], authKey: String) async throws -> [Sample] {
    var request = URLRequest(url: URL(string: "https://mb-api.abuse.ch/api/v1/")!)
    request.httpMethod = "POST"
    request.setValue(authKey, forHTTPHeaderField: "Auth-Key")
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var fields = parameters
    fields["limit"] = "1000"
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&=+")
    request.httpBody = Data(fields.map { key, value in
        "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
    }.joined(separator: "&").utf8)

    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
        fail("MalwareBazaar refused the Auth-Key (HTTP \(http.statusCode)).")
    }
    let decoded = try JSONDecoder().decode(Response.self, from: data)
    switch decoded.queryStatus {
    case "ok": return decoded.data ?? []
    case "no_results", "tag_not_found", "illegal_file_type", "unknown_file_type": return []
    default: throw NSError(domain: "MalwareBazaar", code: 1, userInfo: [NSLocalizedDescriptionKey: decoded.queryStatus])
    }
}

// MARK: Commands

switch args.first {
case "keygen":
    let key = Curve25519.Signing.PrivateKey()
    print("PRIVATE (keep secret; save to ~/.config/burnish/blocklist-signing.key):")
    print(key.rawRepresentation.base64EncodedString())
    print("PUBLIC  (goes into BlocklistConfiguration.publicKeyBase64):")
    print(key.publicKey.rawRepresentation.base64EncodedString())

case "build", "fetch":
    // `build` signs the local lists; `fetch` (or `build --fetch`) adds MalwareBazaar to them.
    let includeRemote = args.first == "fetch" || args.contains("--fetch")
    guard let keyText = secret(env: "BURNISH_BLOCKLIST_KEY", file: "blocklist-signing.key"),
          let raw = Data(base64Encoded: keyText),
          let signingKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        fail("No signing key. Run `BlocklistBuilder keygen` and save the PRIVATE line to ~/.config/burnish/blocklist-signing.key.")
    }
    func option(_ name: String) -> String? { args.firstIndex(of: name).map { args[$0 + 1] } }
    let out = URL(fileURLWithPath: option("--out") ?? "Packages/Features/Protection/Sources/Protection/Resources")
    let listsFolder = URL(fileURLWithPath: option("--lists") ?? "Tools/BlocklistBuilder/Lists")

    var byHash: [String: String] = [:]

    // Local lists: one hash per line (SHA-1 or SHA-256), an optional name after a space, '#' comments.
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

    if includeRemote {
        guard let authKey = secret(env: "ABUSE_CH_AUTH_KEY", file: "abuse-ch.key") else {
            fail("No abuse.ch Auth-Key. Create one at https://auth.abuse.ch and save it to ~/.config/burnish/abuse-ch.key.")
        }
        for parameters in queries {
            let label = parameters["tag"] ?? parameters["file_type"] ?? "?"
            do {
                let samples = try await fetch(parameters, authKey: authKey)
                var kept = 0
                for sample in samples {
                    let hash = sample.sha256Hash.lowercased()
                    guard isDigest(hash) else { continue }
                    if let type = sample.fileType?.lowercased(), windowsOnlyTypes.contains(type) { continue }
                    let name = sample.signature ?? sample.tags?.first ?? "macOS malware"
                    if byHash[hash] == nil { byHash[hash] = name; kept += 1 }
                }
                print("  MalwareBazaar \(label): \(samples.count) samples, \(kept) new")
            } catch {
                print("  MalwareBazaar \(label): skipped (\(error.localizedDescription))")
            }
        }
    }
    guard !byHash.isEmpty else { fail("No hashes found; the existing list was left as it was.") }

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
    let families = Dictionary(grouping: entries, by: \.name).mapValues(\.count).sorted { $0.value > $1.value }
    print("Wrote \(entries.count) hashes (\(sha1Count) SHA-1, \(entries.count - sha1Count) SHA-256), version \(version), to \(out.path)")
    print("Largest families: " + families.prefix(8).map { "\($0.key) \($0.value)" }.joined(separator: ", "))
    if BlocklistConfiguration.publicKey?.rawRepresentation != signingKey.publicKey.rawRepresentation {
        print("NOTE: BlocklistConfiguration.publicKeyBase64 does not match this signing key; the app will ignore the list.")
        print("      Set it to: \(signingKey.publicKey.rawRepresentation.base64EncodedString())")
    }

default:
    print("usage: BlocklistBuilder keygen | build [--fetch] [--lists <directory>] [--out <directory>] | fetch")
    exit(1)
}
