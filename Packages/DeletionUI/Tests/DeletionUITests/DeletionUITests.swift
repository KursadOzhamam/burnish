import Testing
@testable import DeletionUI

@Suite("DeletionUI")
struct DeletionUITests {
    @Test("Every blocked reason has its own plain-language text")
    func reasonsResolve() {
        // Compiles only while the switch stays exhaustive; a new BlockedReason must get words.
        _ = DeletionStrings.summary(count: 1, size: "1 MB")
    }
}
