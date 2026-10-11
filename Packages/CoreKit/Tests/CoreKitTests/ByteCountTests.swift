import Testing
import Foundation
@testable import CoreKit

@Suite("ByteCount")
struct ByteCountTests {
    @Test("Negative input clamps to zero")
    func negativeClampsToZero() {
        #expect(ByteCount(-1).bytes == 0)
        #expect(ByteCount(.min).bytes == 0)
    }

    @Test("Addition saturates instead of trapping")
    func additionSaturates() {
        let big = ByteCount(.max)
        #expect((big + ByteCount(1)).bytes == Int64.max)
        #expect((big + big).bytes == Int64.max)
    }

    @Test("Subtraction never goes below zero")
    func subtractionFloorsAtZero() {
        #expect((ByteCount(10) - ByteCount(25)).bytes == 0)
        #expect((ByteCount(25) - ByteCount(10)).bytes == 15)
    }

    @Test("Summing a sequence")
    func summing() {
        let total = [ByteCount(1), ByteCount(2), ByteCount(3)].sum()
        #expect(total.bytes == 6)
        #expect([ByteCount]().sum() == .zero)
    }

    @Test("Fraction of a total is clamped and zero-safe")
    func fractionIsSafe() {
        #expect(ByteCount(50).fraction(of: ByteCount(100)) == 0.5)
        #expect(ByteCount(5).fraction(of: .zero) == 0)
        #expect(ByteCount(200).fraction(of: ByteCount(100)) == 1)
    }

    @Test("Convenience constructors use decimal units, matching Finder")
    func convenienceConstructors() {
        #expect(ByteCount.kilobytes(1).bytes == 1_000)
        #expect(ByteCount.megabytes(1).bytes == 1_000_000)
        #expect(ByteCount.gigabytes(2).bytes == 2_000_000_000)
    }

    @Test("Formatting produces a non-empty localized string")
    func formatting() {
        #expect(!ByteCount.gigabytes(14).formatted().isEmpty)
        #expect(!ByteCount.zero.formatted().isEmpty)
    }

    @Test("Ordering and equality")
    func ordering() {
        #expect(ByteCount(1) < ByteCount(2))
        #expect(ByteCount(2) == ByteCount(2))
        #expect([ByteCount(3), ByteCount(1), ByteCount(2)].max() == ByteCount(3))
    }
}
