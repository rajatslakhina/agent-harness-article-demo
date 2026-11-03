import XCTest
@testable import HarnessKit

final class ModuleGraphTests: XCTestCase {
    private let graph = ModuleGraph(modules: [
        Module(id: "Core", owner: "P", pathPrefixes: ["Core/"]),
        Module(id: "AI", owner: "A", pathPrefixes: ["AI/"], dependencies: ["Core"]),
        Module(id: "Prompts", owner: "A", pathPrefixes: ["AI/Prompts/"], dependencies: ["Core"]),
        Module(id: "Feature", owner: "F", pathPrefixes: ["Feature/"], dependencies: ["AI"]),
        Module(id: "App", owner: "P", pathPrefixes: ["App/"], dependencies: ["Feature"]),
    ])

    func testLongestPrefixWins() {
        XCTAssertEqual(graph.owner(of: "AI/Prompts/system.md")?.id, "Prompts")
        XCTAssertEqual(graph.owner(of: "AI/Router.swift")?.id, "AI")
    }

    func testUnownedPathHasNoOwner() {
        XCTAssertNil(graph.owner(of: "Scripts/release.sh"))
        XCTAssertNil(graph.owner(of: ""))
    }

    func testAffectedClosureIncludesTransitiveDependents() {
        XCTAssertEqual(graph.affectedClosure(of: ["AI"]), ["AI", "Feature", "App"])
        XCTAssertEqual(graph.affectedClosure(of: ["Core"]), ["Core", "AI", "Prompts", "Feature", "App"])
        XCTAssertEqual(graph.affectedClosure(of: ["App"]), ["App"])
        XCTAssertEqual(graph.affectedClosure(of: []), [])
    }

    func testClosureTerminatesOnCycles() {
        let cyclic = ModuleGraph(modules: [
            Module(id: "A", owner: "x", pathPrefixes: ["A/"], dependencies: ["B"]),
            Module(id: "B", owner: "x", pathPrefixes: ["B/"], dependencies: ["A"]),
        ])
        XCTAssertEqual(cyclic.affectedClosure(of: ["A"]), ["A", "B"])
    }

    func testUnknownDependenciesAreReported() {
        let broken = ModuleGraph(modules: [
            Module(id: "A", owner: "x", pathPrefixes: ["A/"], dependencies: ["Ghost", "Ghost"]),
        ])
        XCTAssertEqual(broken.unknownDependencies(), ["Ghost"])
        XCTAssertEqual(SampleShopApp.graph.unknownDependencies(), [])
    }
}

final class CheckTests: XCTestCase {
    func testInitClampsInputs() {
        let check = Check(id: "c", kind: .unit, scope: .global, seconds: -5, flakeRate: 1.5)
        XCTAssertEqual(check.seconds, 0)
        XCTAssertEqual(check.flakeRate, 1)
    }

    func testScopeApplies() {
        let scoped = Check(id: "c", kind: .unit, scope: .modules(["A", "B"]), seconds: 1)
        XCTAssertTrue(scoped.applies(to: ["B", "Z"]))
        XCTAssertFalse(scoped.applies(to: ["Z"]))
        XCTAssertFalse(scoped.applies(to: []))
        XCTAssertTrue(Check(id: "g", kind: .lint, scope: .global, seconds: 1).applies(to: []))
    }
}

final class PlannerTests: XCTestCase {
    private let planner = SampleShopApp.planner

    func testLeafChangeRunsOnlyItsChecksPlusGlobals() {
        let plan = planner.plan(changedPaths: ["Modules/Profile/Sources/Orders.swift"])
        XCTAssertFalse(plan.fellBackToFullSuite)
        XCTAssertEqual(plan.affectedModules, ["AppShell", "Profile"])
        XCTAssertEqual(plan.steps.map(\.id), ["lint", "unit-Profile", "launch-smoke"])
        XCTAssertEqual(plan.wallSeconds, 90)
        XCTAssertTrue(plan.agentCanSelfVerify)
    }

    func testStepsRunLocalFirstThenCheapestFirst() {
        let plan = planner.plan(changedPaths: ["Modules/Checkout/Sources/Cart.swift"])
        XCTAssertEqual(plan.steps.map(\.id),
                       ["lint", "unit-Checkout", "snapshot-Checkout", "launch-smoke", "ui-checkout-journey"])
    }

    func testUnownedPathForcesTheFullSuite() {
        let plan = planner.plan(changedPaths: ["Scripts/ci-cache.sh"])
        XCTAssertTrue(plan.fellBackToFullSuite)
        XCTAssertEqual(plan.unownedPaths, ["Scripts/ci-cache.sh"])
        XCTAssertEqual(plan.steps.count, SampleShopApp.checks.count)
        XCTAssertEqual(plan.wallSeconds, planner.fullSuite().wallSeconds)
    }

    func testOneUnownedFileInAnOtherwiseSmallChangeStillFallsBack() {
        let plan = planner.plan(changedPaths: ["Modules/Checkout/Sources/ApplePay.swift",
                                               "Resources/Localizable.xcstrings"])
        XCTAssertTrue(plan.fellBackToFullSuite)
        XCTAssertEqual(plan.affectedModules.count, SampleShopApp.modules.count)
    }

    func testFlakyRequiredChecksAreNotEvidence() {
        // Networking → Checkout, so a networking change inherits Checkout's flaky checks.
        let plan = planner.plan(changedPaths: ["Modules/Networking/Sources/Session.swift"])
        XCTAssertEqual(Set(plan.notEvidence.map(\.id)), ["snapshot-Checkout", "ui-checkout-journey"])
        XCTAssertFalse(plan.agentCanSelfVerify)
    }

    func testHumanOnlyCheckBlocksSelfVerification() {
        let plan = planner.plan(changedPaths: ["Modules/DesignSystem/Sources/Tokens.swift"])
        XCTAssertEqual(plan.humanOnly.map(\.id), ["manual-voiceover"])
        XCTAssertEqual(plan.humanSeconds, 600)
        XCTAssertEqual(plan.localSeconds, 525, "human-only time stays out of the agent's lane")
        XCTAssertFalse(plan.agentCanSelfVerify)
    }

    func testDuplicatePathsAreDeduplicated() {
        let plan = planner.plan(changedPaths: ["App/Sources/A.swift", "App/Sources/A.swift"])
        XCTAssertEqual(plan.changedPaths, ["App/Sources/A.swift"])
    }

    func testEmptyChangeRunsOnlyGlobalChecks() {
        let plan = planner.plan(changedPaths: [])
        XCTAssertEqual(plan.steps.map(\.id), ["lint", "launch-smoke"])
        XCTAssertTrue(plan.affectedModules.isEmpty)
    }

    func testFullSuiteNumbers() {
        let full = planner.fullSuite()
        XCTAssertEqual(full.localSeconds, 715, "the 600s manual VoiceOver pass is not agent wait time")
        XCTAssertEqual(full.humanSeconds, 600)
        XCTAssertEqual(full.remoteMakespanSeconds, 600)
        XCTAssertEqual(full.wallSeconds, 715)
    }

    func testMakespanSpreadsJobsAcrossMachines() {
        XCTAssertEqual(VerificationPlanner.makespan([], machines: 2), 0)
        XCTAssertEqual(VerificationPlanner.makespan([420, 360, 240, 90], machines: 2), 600)
        XCTAssertEqual(VerificationPlanner.makespan([420, 360, 240, 90], machines: 1), 1_110)
        XCTAssertEqual(VerificationPlanner.makespan([420, 360, 240, 90], machines: 8), 420)
        XCTAssertEqual(VerificationPlanner.makespan([5], machines: 0), 5)
    }

    func testMoreRemoteMachinesShortenRemoteLane() {
        let one = VerificationPlanner(graph: SampleShopApp.graph, checks: SampleShopApp.checks,
                                      policy: PlannerPolicy(remoteMachines: 1)).fullSuite()
        let four = VerificationPlanner(graph: SampleShopApp.graph, checks: SampleShopApp.checks,
                                       policy: PlannerPolicy(remoteMachines: 4)).fullSuite()
        XCTAssertEqual(one.remoteMakespanSeconds, 1_110)
        XCTAssertEqual(four.remoteMakespanSeconds, 420)
    }
}

final class LoopModelTests: XCTestCase {
    func testShareAndAmdahlCeiling() {
        let loop = LoopModel(generationSeconds: 180, verificationSeconds: 1_315, iterations: 2)
        XCTAssertEqual(loop.loopSeconds, 2_990, accuracy: 0.001)
        XCTAssertEqual(loop.verificationShare, 1_315.0 / 1_495.0, accuracy: 1e-9)
        XCTAssertEqual(loop.promptCeiling, 1_495.0 / 1_315.0, accuracy: 1e-9)
        XCTAssertGreaterThan(loop.speedup(verificationFactor: 2), loop.speedup(generationFactor: 2))
    }

    func testDegenerateInputs() {
        let empty = LoopModel(generationSeconds: -1, verificationSeconds: 0, iterations: 0)
        XCTAssertEqual(empty.iterations, 1)
        XCTAssertEqual(empty.verificationShare, 0)
        XCTAssertEqual(empty.speedup(generationFactor: 2), 1)
        XCTAssertEqual(empty.promptCeiling, .infinity)
        let loop = LoopModel(generationSeconds: 100, verificationSeconds: 100, iterations: 1)
        XCTAssertEqual(loop.speedup(generationFactor: 0), 1, "a zero factor is ignored, not a crash")
    }
}

final class AuditTests: XCTestCase {
    func testSampleAuditFindsTheHarnessIsTheBottleneck() {
        let audit = SampleShopApp.audit()
        XCTAssertEqual(audit.plans.count, 20)
        XCTAssertEqual(audit.medianWallSeconds, 360)
        XCTAssertEqual(audit.medianVerificationShare, 360.0 / 540.0, accuracy: 1e-9)
        XCTAssertEqual(audit.bottleneck, .harness)
        XCTAssertEqual(audit.selfVerifyRate, 0.55, accuracy: 1e-9)

        let byID = Dictionary(uniqueKeysWithValues: audit.items.map { ($0.id, $0) })
        XCTAssertEqual(byID["ownership"]?.value ?? -1, 0.85, accuracy: 1e-9)
        XCTAssertEqual(byID["determinism"]?.value ?? -1, 0.55, accuracy: 1e-9)
        XCTAssertEqual(byID["callable"]?.value ?? -1, 0.80, accuracy: 1e-9)
        XCTAssertEqual(byID["selection"]?.value ?? -1, 360.0 / 715.0, accuracy: 1e-9)
        XCTAssertEqual(audit.passedCount, 0, "selection misses its 50% target by a hair")
    }

    func testSecondMacHalvesTheMedianAndAThirdBuysNothing() {
        func median(machines: Int) -> Double {
            let planner = VerificationPlanner(graph: SampleShopApp.graph, checks: SampleShopApp.checks,
                                              policy: PlannerPolicy(remoteMachines: machines))
            return HarnessAudit(planner: planner, changes: SampleShopApp.changes.map(\.paths),
                                generationSeconds: SampleShopApp.generationSeconds).medianWallSeconds
        }
        XCTAssertEqual(median(machines: 1), 690)
        XCTAssertEqual(median(machines: 2), 360)
        XCTAssertEqual(median(machines: 3), 360, "one 6-minute UI journey sets the floor")
    }

    func testFullSuiteLoopNumbers() {
        let full = SampleShopApp.planner.fullSuite()
        let loop = LoopModel(generationSeconds: SampleShopApp.generationSeconds,
                             verificationSeconds: Double(full.wallSeconds), iterations: 1)
        XCTAssertEqual(loop.verificationShare, 715.0 / 895.0, accuracy: 1e-9)   // ≈ 80%
        XCTAssertEqual(loop.promptCeiling, 895.0 / 715.0, accuracy: 1e-9)       // ≈ 1.25×
        XCTAssertEqual(loop.speedup(generationFactor: 2), 895.0 / 805.0, accuracy: 1e-9)   // ≈ 1.11×
        XCTAssertEqual(loop.speedup(verificationFactor: 2), 895.0 / 537.5, accuracy: 1e-9) // ≈ 1.67×
    }

    func testFixingTwoFlakyCheckoutChecksUnblocksFiveChanges() {
        let fixed = SampleShopApp.checks.map { check -> Check in
            guard check.id == "snapshot-Checkout" || check.id == "ui-checkout-journey" else { return check }
            return Check(id: check.id, kind: check.kind, scope: check.scope, seconds: check.seconds,
                         runner: check.runner, flakeRate: 0, agentCallable: check.agentCallable)
        }
        let planner = VerificationPlanner(graph: SampleShopApp.graph, checks: fixed)
        let audit = HarnessAudit(planner: planner, changes: SampleShopApp.changes.map(\.paths),
                                 generationSeconds: SampleShopApp.generationSeconds)
        XCTAssertEqual(audit.selfVerifyRate, 0.80, accuracy: 1e-9) // 11 → 16 of 20
    }

    func testFastGenerationAgainstQuickChecksIsAPromptBottleneck() {
        let planner = VerificationPlanner(
            graph: ModuleGraph(modules: [Module(id: "A", owner: "x", pathPrefixes: ["A/"])]),
            checks: [Check(id: "u", kind: .unit, scope: .modules(["A"]), seconds: 30)])
        let audit = HarnessAudit(planner: planner, changes: [["A/x.swift"]], generationSeconds: 300)
        XCTAssertEqual(audit.bottleneck, .prompt)
        XCTAssertEqual(audit.selfVerifyRate, 1)
    }

    func testEmptyAuditDoesNotCrash() {
        let audit = HarnessAudit(planner: SampleShopApp.planner, changes: [], generationSeconds: 180)
        XCTAssertEqual(audit.medianWallSeconds, 0)
        XCTAssertEqual(audit.selfVerifyRate, 0)
        XCTAssertEqual(audit.bottleneck, .prompt)
    }

    func testMedian() {
        XCTAssertEqual(HarnessAudit.median([]), 0)
        XCTAssertEqual(HarnessAudit.median([3, 1, 2]), 2)
        XCTAssertEqual(HarnessAudit.median([4, 1, 3, 2]), 2.5)
    }
}
