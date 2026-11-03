import Foundation

public struct AuditItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let question: String
    /// The measured value, as a share (0...1) or a ratio.
    public let value: Double
    public let threshold: Double
    /// True when a higher value is better.
    public let higherIsBetter: Bool

    public var passed: Bool { higherIsBetter ? value >= threshold : value <= threshold }
}

public enum Bottleneck: String, Sendable, Equatable {
    /// Verification takes most of the loop: better prompts can't fix that.
    case harness
    /// Generation takes most of the loop: the prompt and the model are worth tuning.
    case prompt
}

/// Replays a set of changes through the planner and answers the question a lead
/// should ask before buying a better model: is the harness the bottleneck?
public struct HarnessAudit: Sendable {
    public let plans: [VerificationPlan]
    public let fullSuite: VerificationPlan
    public let items: [AuditItem]
    public let medianVerificationShare: Double
    public let bottleneck: Bottleneck

    public init(planner: VerificationPlanner, changes: [[String]], generationSeconds: Double) {
        let plans = changes.map { planner.plan(changedPaths: $0) }
        let full = planner.fullSuite()
        self.plans = plans
        self.fullSuite = full

        let count = Double(max(plans.count, 1))
        let mapped = Double(plans.filter { !$0.fellBackToFullSuite }.count) / count
        let deterministic = Double(plans.filter { $0.notEvidence.isEmpty }.count) / count
        let callable = Double(plans.filter { $0.humanOnly.isEmpty }.count) / count
        let medianWall = Self.median(plans.map { Double($0.wallSeconds) })
        let speedRatio = full.wallSeconds > 0 ? medianWall / Double(full.wallSeconds) : 0

        self.items = [
            AuditItem(id: "ownership",
                      question: "Does every changed path map to a module, so the harness knows what to check?",
                      value: mapped, threshold: 0.9, higherIsBetter: true),
            AuditItem(id: "determinism",
                      question: "Is every required check deterministic enough for a green run to count?",
                      value: deterministic, threshold: 0.9, higherIsBetter: true),
            AuditItem(id: "callable",
                      question: "Can the agent run every required check itself and read the result?",
                      value: callable, threshold: 0.9, higherIsBetter: true),
            AuditItem(id: "selection",
                      question: "Is the median change-aware plan at most half the full suite's wall time?",
                      value: speedRatio, threshold: 0.5, higherIsBetter: false),
        ]

        let shares = plans.map {
            LoopModel(generationSeconds: generationSeconds,
                      verificationSeconds: Double($0.wallSeconds),
                      iterations: 1).verificationShare
        }
        let medianShare = Self.median(shares)
        self.medianVerificationShare = medianShare
        self.bottleneck = medianShare > 0.5 ? .harness : .prompt
    }

    public var passedCount: Int { items.filter(\.passed).count }

    /// Share of changes where the agent can close the loop with no person involved.
    public var selfVerifyRate: Double {
        plans.isEmpty ? 0 : Double(plans.filter(\.agentCanSelfVerify).count) / Double(plans.count)
    }

    public var medianWallSeconds: Double { Self.median(plans.map { Double($0.wallSeconds) }) }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[mid] }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }
}
