import Testing
import Foundation
import CoreKit
import SystemMonitor
@testable import Dashboard

@Suite("Health score")
struct HealthScoreTests {
    private func snapshot(
        freeGB: Int64 = 500,
        totalGB: Int64 = 1_000,
        pressure: Double = 0.3
    ) -> SystemSnapshot {
        SystemSnapshot(
            machine: MachineInfo(model: "Test", osVersion: "macOS 27", processorCoreCount: 8),
            disk: DiskUsage(
                total: .gigabytes(totalGB),
                free: .gigabytes(freeGB),
                purgeable: .zero
            ),
            memory: MemoryUsage(
                total: .gigabytes(16),
                used: .gigabytes(8),
                compressed: .zero,
                swapUsed: .zero,
                pressure: pressure
            ),
            cpu: CPULoad(total: 0.1, perCore: [0.1]),
            battery: nil,
            network: NetworkThroughput(download: .zero, upload: .zero)
        )
    }

    @Test("Factor weights sum to exactly 100")
    func weightsSumTo100() {
        #expect(HealthScore.Factor.allCases.reduce(0) { $0 + $1.weight } == 100)
    }

    @Test("A healthy machine scores 100 — §10.4 forbids a built-in deduction")
    func healthyMachineScoresFull() {
        let score = HealthScore.evaluate(
            snapshot: snapshot(freeGB: 500, pressure: 0.2),
            inputs: .init(threatCount: 0, pendingUpdateCount: 0, startupItemCount: 4)
        )
        #expect(score.value == 100)
        #expect(score.weakest.isEmpty)
    }

    @Test("An unscanned machine is not penalised for what has not been measured")
    func unmeasuredFactorsAwardFullPoints() {
        let score = HealthScore.evaluate(snapshot: snapshot(), inputs: .unmeasured)
        #expect(score.value == 100)

        for component in score.components where component.measurement == "—" {
            #expect(component.earned == component.available)
        }
    }

    @Test("The score is the sum of its components, so the explanation shows real arithmetic")
    func scoreEqualsSumOfComponents() {
        let score = HealthScore.evaluate(
            snapshot: snapshot(freeGB: 50, pressure: 0.8),
            inputs: .init(threatCount: 1, pendingUpdateCount: 3, startupItemCount: 18)
        )
        #expect(score.value == score.components.reduce(0) { $0 + $1.earned })
    }

    @Test("Score stays within 0...100 under the worst inputs")
    func scoreIsBounded() {
        let worst = HealthScore.evaluate(
            snapshot: snapshot(freeGB: 0, pressure: 1.0),
            inputs: .init(threatCount: 99, pendingUpdateCount: 99, startupItemCount: 500)
        )
        #expect(worst.value >= 0)
        #expect(worst.value <= 100)
        #expect(worst.value == 0)
    }

    @Test("Free space earns full marks at 20% and above, and no bonus beyond it")
    func freeSpaceSaturatesAt20Percent() {
        let atThreshold = HealthScore.evaluate(
            snapshot: snapshot(freeGB: 200, pressure: 0.1), inputs: .unmeasured
        )
        let wayAbove = HealthScore.evaluate(
            snapshot: snapshot(freeGB: 900, pressure: 0.1), inputs: .unmeasured
        )
        #expect(atThreshold.value == 100)
        #expect(wayAbove.value == atThreshold.value)
    }

    @Test("A full disk costs the whole free-space weight")
    func fullDiskCostsFullWeight() {
        let score = HealthScore.evaluate(
            snapshot: snapshot(freeGB: 0, pressure: 0.1),
            inputs: .init(threatCount: 0, pendingUpdateCount: 0, startupItemCount: 0)
        )
        #expect(score.value == 100 - HealthScore.Factor.freeSpace.weight)
    }

    @Test("One threat costs the entire threat weight — no partial credit")
    func anyThreatCostsFullWeight() {
        let one = HealthScore.evaluate(snapshot: snapshot(), inputs: .init(threatCount: 1))
        let many = HealthScore.evaluate(snapshot: snapshot(), inputs: .init(threatCount: 12))
        #expect(one.value == many.value)
        #expect(one.value == 100 - HealthScore.Factor.threats.weight)
    }

    @Test("Up to ten startup items is normal and costs nothing")
    func startupItemsHaveAGracefulThreshold() {
        let normal = HealthScore.evaluate(snapshot: snapshot(), inputs: .init(startupItemCount: 10))
        let heavy = HealthScore.evaluate(snapshot: snapshot(), inputs: .init(startupItemCount: 15))
        #expect(normal.value == 100)
        #expect(heavy.value == 95)
    }

    @Test("Weakest factors are ordered by points lost, worst first")
    func weakestIsOrderedByLoss() {
        let score = HealthScore.evaluate(
            snapshot: snapshot(freeGB: 0, pressure: 0.1),
            inputs: .init(threatCount: 0, pendingUpdateCount: 1, startupItemCount: 0)
        )
        #expect(score.weakest.first?.factor == .freeSpace)
        #expect(score.weakest.count == 2)
    }

    @Test("Component values are clamped to their own weight")
    func componentsAreClamped() {
        let over = HealthScore.Component(factor: .threats, earned: 999, measurement: "x")
        let under = HealthScore.Component(factor: .threats, earned: -5, measurement: "x")
        #expect(over.earned == HealthScore.Factor.threats.weight)
        #expect(under.earned == 0)
    }
}
