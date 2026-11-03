import Foundation

/// One change in the sample week: a title and the paths it touches.
public struct SampleChange: Sendable, Hashable, Identifiable {
    public let title: String
    public let paths: [String]
    public var id: String { title }

    public init(_ title: String, _ paths: [String]) {
        self.title = title
        self.paths = paths
    }
}

/// A constructed, **synthetic** iOS shopping app: 11 modules, 18 checks and
/// 20 agent-authored changes. Timings and flake rates are invented to be
/// plausible, not measured from a real repo.
public enum SampleShopApp {
    public static let modules: [Module] = [
        Module(id: "DesignSystem", owner: "Platform", pathPrefixes: ["Modules/DesignSystem/"]),
        Module(id: "Networking", owner: "Platform", pathPrefixes: ["Modules/Networking/"]),
        Module(id: "Persistence", owner: "Platform", pathPrefixes: ["Modules/Persistence/"]),
        Module(id: "Analytics", owner: "Platform", pathPrefixes: ["Modules/Analytics/"]),
        Module(id: "PromptKit", owner: "AI", pathPrefixes: ["Modules/AI/PromptKit/", "Prompts/"],
               dependencies: ["Networking"]),
        Module(id: "OnDeviceModel", owner: "AI", pathPrefixes: ["Modules/AI/OnDeviceModel/"]),
        Module(id: "Catalog", owner: "Browse", pathPrefixes: ["Modules/Catalog/"],
               dependencies: ["DesignSystem", "Networking", "Persistence", "Analytics"]),
        Module(id: "Checkout", owner: "Payments", pathPrefixes: ["Modules/Checkout/"],
               dependencies: ["DesignSystem", "Networking", "Analytics"]),
        Module(id: "Profile", owner: "Accounts", pathPrefixes: ["Modules/Profile/"],
               dependencies: ["DesignSystem", "Networking", "Persistence"]),
        Module(id: "Assistant", owner: "AI", pathPrefixes: ["Modules/Assistant/"],
               dependencies: ["DesignSystem", "PromptKit", "OnDeviceModel", "Catalog"]),
        Module(id: "AppShell", owner: "Platform", pathPrefixes: ["App/"],
               dependencies: ["Catalog", "Checkout", "Profile", "Assistant"]),
    ]

    public static let checks: [Check] = [
        Check(id: "lint", kind: .lint, scope: .global, seconds: 25),
        Check(id: "unit-DesignSystem", kind: .unit, scope: .modules(["DesignSystem"]), seconds: 30),
        Check(id: "unit-Networking", kind: .unit, scope: .modules(["Networking"]), seconds: 45),
        Check(id: "unit-Persistence", kind: .unit, scope: .modules(["Persistence"]), seconds: 60),
        Check(id: "unit-Analytics", kind: .unit, scope: .modules(["Analytics"]), seconds: 20),
        Check(id: "unit-PromptKit", kind: .unit, scope: .modules(["PromptKit"]), seconds: 25),
        Check(id: "unit-OnDeviceModel", kind: .unit, scope: .modules(["OnDeviceModel"]), seconds: 40),
        Check(id: "unit-Catalog", kind: .unit, scope: .modules(["Catalog"]), seconds: 55),
        Check(id: "unit-Checkout", kind: .unit, scope: .modules(["Checkout"]), seconds: 70),
        Check(id: "unit-Profile", kind: .unit, scope: .modules(["Profile"]), seconds: 35),
        Check(id: "unit-Assistant", kind: .unit, scope: .modules(["Assistant"]), seconds: 50),
        Check(id: "snapshot-DesignSystem", kind: .snapshot, scope: .modules(["DesignSystem"]),
              seconds: 140, flakeRate: 0.01),
        Check(id: "snapshot-Checkout", kind: .snapshot, scope: .modules(["Checkout"]),
              seconds: 120, flakeRate: 0.06),
        Check(id: "ui-checkout-journey", kind: .uiJourney, scope: .modules(["Checkout"]),
              seconds: 420, runner: .remoteMac, flakeRate: 0.04),
        Check(id: "ui-browse-journey", kind: .uiJourney, scope: .modules(["Catalog", "Assistant"]),
              seconds: 360, runner: .remoteMac, flakeRate: 0.01),
        Check(id: "launch-smoke", kind: .launch, scope: .global, seconds: 90, runner: .remoteMac),
        Check(id: "eval-assistant", kind: .eval, scope: .modules(["PromptKit", "Assistant"]),
              seconds: 240, runner: .remoteMac),
        Check(id: "manual-voiceover", kind: .manual, scope: .modules(["DesignSystem"]),
              seconds: 600, agentCallable: false),
    ]

    /// Twenty changes an agent might open in a normal week.
    public static let changes: [SampleChange] = [
        SampleChange("Fix price rounding in cart", ["Modules/Checkout/Sources/Cart.swift"]),
        SampleChange("Add retry to image loader", ["Modules/Networking/Sources/ImageLoader.swift"]),
        SampleChange("Rename analytics event", ["Modules/Analytics/Sources/Events.swift"]),
        SampleChange("New empty state in search", ["Modules/Catalog/Sources/SearchView.swift"]),
        SampleChange("Tighten assistant system prompt", ["Prompts/assistant.md"]),
        SampleChange("Cache product thumbnails", ["Modules/Persistence/Sources/ThumbnailStore.swift"]),
        SampleChange("Profile avatar crop", ["Modules/Profile/Sources/AvatarEditor.swift"]),
        SampleChange("Button corner radius token", ["Modules/DesignSystem/Sources/Tokens.swift"]),
        SampleChange("Apple Pay sheet copy", ["Modules/Checkout/Sources/ApplePay.swift",
                                  "Resources/Localizable.xcstrings"]),
        SampleChange("On-device summary fallback", ["Modules/AI/OnDeviceModel/Sources/Summarizer.swift"]),
        SampleChange("Assistant suggests products", ["Modules/Assistant/Sources/Suggestions.swift",
                                         "Modules/Catalog/Sources/ProductQuery.swift"]),
        SampleChange("Deep link to order", ["App/Sources/DeepLinks.swift"]),
        SampleChange("Bump CI cache key", ["Scripts/ci-cache.sh"]),
        SampleChange("Promo code validation", ["Modules/Checkout/Sources/PromoCode.swift"]),
        SampleChange("Prompt tool schema field", ["Modules/AI/PromptKit/Sources/ToolSchema.swift"]),
        SampleChange("Wishlist sync conflict", ["Modules/Persistence/Sources/Sync.swift",
                                    "Modules/Profile/Sources/Wishlist.swift"]),
        SampleChange("Category filter chips", ["Modules/Catalog/Sources/Filters.swift"]),
        SampleChange("Request timeout tuning", ["Modules/Networking/Sources/Session.swift"]),
        SampleChange("Order history paging", ["Modules/Profile/Sources/Orders.swift"]),
        SampleChange("Feature flag for new tab", ["Project.swift", "App/Sources/Tabs.swift"]),
    ]

    /// Assumed seconds for one agent generation pass (read, edit, explain).
    public static let generationSeconds: Double = 180

    public static var graph: ModuleGraph { ModuleGraph(modules: modules) }
    public static var planner: VerificationPlanner { VerificationPlanner(graph: graph, checks: checks) }

    public static func audit(generationSeconds: Double = generationSeconds) -> HarnessAudit {
        HarnessAudit(planner: planner, changes: changes.map(\.paths), generationSeconds: generationSeconds)
    }
}
