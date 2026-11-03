import Foundation

public enum CheckKind: String, Sendable, CaseIterable {
    case lint, unit, snapshot, uiJourney, launch, eval, manual
}

/// Where a check runs. UI journeys and Simulator launches need macOS hardware,
/// which is the compute an agent on a laptop or in a Linux sandbox doesn't have.
public enum Runner: String, Sendable {
    case local, remoteMac
}

public enum CheckScope: Hashable, Sendable {
    /// Runs on every change.
    case global
    /// Runs when any of these modules is affected.
    case modules(Set<String>)
}

public struct Check: Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: CheckKind
    public let scope: CheckScope
    /// Median wall time in seconds.
    public let seconds: Int
    public let runner: Runner
    /// Share of runs on unchanged code that fail anyway (0...1).
    public let flakeRate: Double
    /// True when an agent can run it with one command and read a structured result.
    /// False means a person has to run or read it.
    public let agentCallable: Bool

    public init(id: String, kind: CheckKind, scope: CheckScope, seconds: Int,
                runner: Runner = .local, flakeRate: Double = 0, agentCallable: Bool = true) {
        self.id = id
        self.kind = kind
        self.scope = scope
        self.seconds = max(0, seconds)
        self.runner = runner
        self.flakeRate = min(max(flakeRate, 0), 1)
        self.agentCallable = agentCallable
    }

    public func applies(to affected: Set<String>) -> Bool {
        switch scope {
        case .global: return true
        case .modules(let ids): return !ids.isDisjoint(with: affected)
        }
    }
}
