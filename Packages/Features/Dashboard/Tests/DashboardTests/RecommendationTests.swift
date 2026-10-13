import Testing
import Foundation
import CoreKit
@testable import Dashboard

@Suite("Recommendations")
struct RecommendationTests {
    private func mb(_ value: Int64) -> ByteCount { ByteCount(value * 1_048_576) }

    @Test("With nothing measured there is nothing to suggest")
    func nothingMeasured() {
        #expect(RecommendationEngine.make(from: RecommendationFacts()).isEmpty)
    }

    @Test("A healthy Mac with small caches gets no suggestions")
    func healthy() {
        let facts = RecommendationFacts(
            cleanable: [("Caches", mb(20))], threatCount: 0, freeFraction: 0.4, freeBytes: mb(400_000), startupItemCount: 4
        )
        #expect(RecommendationEngine.make(from: facts).isEmpty)
    }

    @Test("A confirmed threat comes first, and points to Protection")
    func threatFirst() {
        let facts = RecommendationFacts(cleanable: [("Xcode", mb(14_000))], threatCount: 2)
        let recommendations = RecommendationEngine.make(from: facts)
        #expect(recommendations.first?.kind == .threats(count: 2))
        #expect(recommendations.first?.section == .protection)
    }

    @Test("Real cleanable space is suggested, biggest first, with its size")
    func cleanableBySize() {
        let facts = RecommendationFacts(cleanable: [("Logs", mb(300)), ("Xcode", mb(14_000)), ("Tiny", mb(5))])
        let kinds = RecommendationEngine.make(from: facts).map(\.kind)
        #expect(kinds == [.cleanable(name: "Xcode", size: mb(14_000)), .cleanable(name: "Logs", size: mb(300))])
    }

    @Test("Low free disk space is suggested, high free space is not")
    func lowDisk() {
        #expect(RecommendationEngine.make(from: RecommendationFacts(freeFraction: 0.05, freeBytes: mb(20_000))).count == 1)
        #expect(RecommendationEngine.make(from: RecommendationFacts(freeFraction: 0.30, freeBytes: mb(300_000))).isEmpty)
    }

    @Test("Many startup items are suggested only past ten")
    func startup() {
        #expect(RecommendationEngine.make(from: RecommendationFacts(startupItemCount: 10)).isEmpty)
        #expect(RecommendationEngine.make(from: RecommendationFacts(startupItemCount: 14)).count == 1)
    }

    @Test("The list is capped")
    func capped() {
        let facts = RecommendationFacts(
            cleanable: (1...8).map { ("c\($0)", mb(Int64($0) * 200)) }, threatCount: 1, freeFraction: 0.02, freeBytes: mb(10), startupItemCount: 30
        )
        #expect(RecommendationEngine.make(from: facts, limit: 4).count == 4)
    }
}
