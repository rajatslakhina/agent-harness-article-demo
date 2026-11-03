import Foundation

public struct PlannerPolicy: Sendable, Equatable {
    /// A check that fails this often on unchanged code can't count as evidence:
    /// a green run from it doesn't tell the agent anything.
    public var maxFlakeRateForEvidence: Double
    /// Parallel remote macOS machines available for this change.
    public var remoteMachines: Int

    public init(maxFlakeRateForEvidence: Double = 0.02, remoteMachines: Int = 2) {
        self.maxFlakeRateForEvidence = maxFlakeRateForEvidence
        self.remoteMachines = max(1, remoteMachines)
    }
}

/// What has to pass before an agent may call a change verified.
public struct VerificationPlan: Sendable, Equatable {
    public let changedPaths: [String]
    public let affectedModules: [String]
    /// Changed paths no module owns. Any of these forces the full suite,
    /// because the harness can't say what they affect.
    public let unownedPaths: [String]
    public let fellBackToFullSuite: Bool
    /// Checks to run, listed local lane first, each lane cheapest first.
    /// The two lanes run at the same time.
    public let steps: [Check]
    /// Required checks that are too flaky to count as evidence.
    public let notEvidence: [Check]
    /// Required checks only a person can run or read.
    public let humanOnly: [Check]
    /// Agent-callable local checks, run one after another.
    public let localSeconds: Int
    /// Longest remote machine's load after spreading remote checks over the pool.
    public let remoteMakespanSeconds: Int
    /// Time a person spends on human-only checks. Not part of the agent's wait:
    /// the agent can't run these, so the loop stops there instead.
    public let humanSeconds: Int

    /// What the agent waits for. Local and remote lanes run at the same time.
    public var wallSeconds: Int { max(localSeconds, remoteMakespanSeconds) }

    /// True when every required check is deterministic enough and agent-callable,
    /// so an agent can close the loop without a person.
    public var agentCanSelfVerify: Bool { notEvidence.isEmpty && humanOnly.isEmpty }
}

public struct VerificationPlanner: Sendable {
    public let graph: ModuleGraph
    public let checks: [Check]
    public let policy: PlannerPolicy

    public init(graph: ModuleGraph, checks: [Check], policy: PlannerPolicy = PlannerPolicy()) {
        self.graph = graph
        self.checks = checks
        self.policy = policy
    }

    public func plan(changedPaths: [String]) -> VerificationPlan {
        let paths = Array(Set(changedPaths)).sorted()
        var owned = Set<String>()
        var unowned: [String] = []
        for path in paths {
            if let module = graph.owner(of: path) {
                owned.insert(module.id)
            } else {
                unowned.append(path)
            }
        }

        let fallBack = !unowned.isEmpty
        let affected: Set<String> = fallBack
            ? Set(graph.modules.map(\.id))
            : graph.affectedClosure(of: owned)
        let required = fallBack ? checks : checks.filter { $0.applies(to: affected) }
        return makePlan(paths: paths, affected: affected, unowned: unowned,
                        fellBack: fallBack, required: required)
    }

    /// The baseline most teams start from: every check on every change.
    public func fullSuite() -> VerificationPlan {
        makePlan(paths: [], affected: Set(graph.modules.map(\.id)), unowned: [],
                 fellBack: true, required: checks)
    }

    private func makePlan(paths: [String], affected: Set<String>, unowned: [String],
                          fellBack: Bool, required: [Check]) -> VerificationPlan {
        let ordered = required.sorted { lhs, rhs in
            if lhs.runner != rhs.runner { return lhs.runner == .local }
            if lhs.seconds != rhs.seconds { return lhs.seconds < rhs.seconds }
            return lhs.id < rhs.id
        }
        let callable = ordered.filter(\.agentCallable)
        let local = callable.filter { $0.runner == .local }.reduce(0) { $0 + $1.seconds }
        let remote = callable.filter { $0.runner == .remoteMac }.map(\.seconds)
        let human = ordered.filter { !$0.agentCallable }.reduce(0) { $0 + $1.seconds }
        return VerificationPlan(
            changedPaths: paths,
            affectedModules: affected.sorted(),
            unownedPaths: unowned,
            fellBackToFullSuite: fellBack,
            steps: ordered,
            notEvidence: ordered.filter { $0.flakeRate > policy.maxFlakeRateForEvidence },
            humanOnly: ordered.filter { !$0.agentCallable },
            localSeconds: local,
            remoteMakespanSeconds: Self.makespan(remote, machines: policy.remoteMachines),
            humanSeconds: human
        )
    }

    /// Longest-processing-time-first: each job goes to the least-loaded machine.
    /// Never worse than 4/3 of optimal, which is plenty for a planning estimate.
    static func makespan(_ jobs: [Int], machines: Int) -> Int {
        guard !jobs.isEmpty else { return 0 }
        var loads = Array(repeating: 0, count: max(1, machines))
        for job in jobs.sorted(by: >) {
            guard let index = loads.indices.min(by: { loads[$0] < loads[$1] }) else { continue }
            loads[index] += job
        }
        return loads.max() ?? 0
    }
}
