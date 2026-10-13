import Foundation
import Security

/// Reads this process's own code signature.
public enum CodeSigning {
    /// The team identifier this very binary is signed with, or nil for an ad-hoc or unsigned
    /// build. The helper and the app each ask for their own, so a requirement can be built
    /// without hard-coding a team anywhere.
    public static func ownTeamID() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

extension HelperRequirement {
    /// What the app requires of the helper it talks to: the helper's identifier, our team.
    public static func forHelper(teamID: String) -> String {
        "anchor apple generic and identifier \"\(HelperIdentity.machServiceName)\" and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}
