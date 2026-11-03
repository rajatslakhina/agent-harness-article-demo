import Foundation

/// One module in the app, with the paths it owns and the modules it depends on.
public struct Module: Hashable, Sendable, Identifiable {
    public let id: String
    public let owner: String
    /// Repo-relative path prefixes this module owns, e.g. `"Modules/Checkout/"`.
    public let pathPrefixes: [String]
    public let dependencies: [String]

    public init(id: String, owner: String, pathPrefixes: [String], dependencies: [String] = []) {
        self.id = id
        self.owner = owner
        self.pathPrefixes = pathPrefixes
        self.dependencies = dependencies
    }
}

/// The ownership graph: which module owns a path, and which modules are
/// affected when it changes (the module itself plus everything that depends on it).
public struct ModuleGraph: Sendable {
    public let modules: [Module]
    private let byID: [String: Module]
    private let dependents: [String: Set<String>]

    public init(modules: [Module]) {
        self.modules = modules
        var byID: [String: Module] = [:]
        for module in modules { byID[module.id] = module }
        self.byID = byID
        var dependents: [String: Set<String>] = [:]
        for module in modules {
            for dependency in module.dependencies {
                dependents[dependency, default: []].insert(module.id)
            }
        }
        self.dependents = dependents
    }

    public func module(_ id: String) -> Module? { byID[id] }

    /// Dependency names that don't match any module. A non-empty result means
    /// the graph itself is wrong, and plans built from it can't be trusted.
    public func unknownDependencies() -> [String] {
        let names = modules.flatMap(\.dependencies).filter { byID[$0] == nil }
        return Array(Set(names)).sorted()
    }

    /// The module that owns `path`. When prefixes overlap, the longest one wins,
    /// so `Modules/AI/PromptKit/` beats `Modules/AI/`.
    public func owner(of path: String) -> Module? {
        var best: (module: Module, length: Int)?
        for module in modules {
            for prefix in module.pathPrefixes where path.hasPrefix(prefix) {
                if prefix.count > (best?.length ?? -1) {
                    best = (module, prefix.count)
                }
            }
        }
        return best?.module
    }

    /// `ids` plus every module that transitively depends on any of them.
    /// Safe on cyclic graphs: each module is visited once.
    public func affectedClosure(of ids: Set<String>) -> Set<String> {
        var seen = Set<String>()
        var queue = Array(ids)
        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            guard seen.insert(current).inserted else { continue }
            for dependent in dependents[current] ?? [] where !seen.contains(dependent) {
                queue.append(dependent)
            }
        }
        return seen
    }
}
