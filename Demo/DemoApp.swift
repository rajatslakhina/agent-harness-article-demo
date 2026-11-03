import SwiftUI
import HarnessKit

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Launch arguments drive the CI screenshots:
/// `-tab changes|loop|audit`, `-change 0...19` (opens that change's plan).
struct RootView: View {
    @State private var tab: String = UserDefaults.standard.string(forKey: "tab") ?? "changes"

    var body: some View {
        TabView(selection: $tab) {
            ChangesView()
                .tabItem { Label("Changes", systemImage: "arrow.triangle.branch") }
                .tag("changes")
            LoopView()
                .tabItem { Label("Agent loop", systemImage: "timer") }
                .tag("loop")
            AuditView()
                .tabItem { Label("Audit", systemImage: "checklist") }
                .tag("audit")
        }
    }
}

// MARK: - Changes

struct ChangesView: View {
    private let changes = SampleShopApp.changes
    private let planner = SampleShopApp.planner
    @State private var path: [Int] = {
        let index = UserDefaults.standard.integer(forKey: "change")
        let requested = UserDefaults.standard.object(forKey: "change") != nil
        return requested && SampleShopApp.changes.indices.contains(index) ? [index] : []
    }()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    let full = planner.fullSuite()
                    HStack {
                        Metric(value: minutes(full.wallSeconds), label: "full suite")
                        Metric(value: "\(changes.count)", label: "agent changes")
                    }
                } footer: {
                    Text("Synthetic 11-module shop app. Each change maps to its owning modules, then to every module that depends on them, then to the checks scoped to those modules.")
                }
                Section("This week's changes") {
                    ForEach(Array(changes.enumerated()), id: \.offset) { index, change in
                        NavigationLink(value: index) {
                            ChangeRow(change: change, plan: planner.plan(changedPaths: change.paths))
                        }
                    }
                }
            }
            .navigationTitle("Change → checks")
            .navigationDestination(for: Int.self) { index in
                if changes.indices.contains(index) {
                    PlanDetailView(change: changes[index], plan: planner.plan(changedPaths: changes[index].paths))
                }
            }
        }
    }
}

struct ChangeRow: View {
    let change: SampleChange
    let plan: VerificationPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(change.title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(minutes(plan.wallSeconds)).font(.caption.monospacedDigit())
            }
            HStack(spacing: 6) {
                if plan.fellBackToFullSuite { Badge(text: "unowned path", color: .red) }
                if !plan.notEvidence.isEmpty { Badge(text: "flaky", color: .orange) }
                if !plan.humanOnly.isEmpty { Badge(text: "needs a person", color: .purple) }
                if plan.agentCanSelfVerify { Badge(text: "agent can verify", color: .green) }
            }
        }
        .padding(.vertical, 2)
    }
}

struct PlanDetailView: View {
    let change: SampleChange
    let plan: VerificationPlan

    var body: some View {
        List {
            Section {
                HStack {
                    Metric(value: minutes(plan.wallSeconds), label: "wall time")
                    Metric(value: "\(plan.steps.count)", label: "checks")
                    Metric(value: "\(plan.affectedModules.count)", label: "modules")
                }
                Text(plan.agentCanSelfVerify ? "The agent can close this loop on its own." : "The agent can't call this verified on its own.")
                    .font(.caption)
                    .foregroundStyle(plan.agentCanSelfVerify ? Color.green : Color.orange)
            }
            Section("Changed paths") {
                ForEach(plan.changedPaths, id: \.self) { path in
                    HStack {
                        Text(path).font(.caption.monospaced())
                        Spacer()
                        if plan.unownedPaths.contains(path) { Badge(text: "no owner", color: .red) }
                    }
                }
            }
            if plan.fellBackToFullSuite {
                Section {
                    Text("A path no module owns forces the full suite: the harness can't tell what it affects.")
                        .font(.caption)
                }
            }
            Section("Plan (local in sequence, remote in parallel)") {
                ForEach(plan.steps) { check in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.id).font(.caption.monospaced())
                            Text(check.runner == .remoteMac ? "remote Mac" : "local")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if plan.notEvidence.contains(check) { Badge(text: "not evidence", color: .orange) }
                        if plan.humanOnly.contains(check) { Badge(text: "person", color: .purple) }
                        Text("\(check.seconds)s").font(.caption.monospacedDigit())
                    }
                }
            }
        }
        .navigationTitle(change.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Loop

struct LoopView: View {
    @State private var generation: Double = SampleShopApp.generationSeconds
    @State private var useChangeAware = false
    private let audit = SampleShopApp.audit()

    private var model: LoopModel {
        let verification = useChangeAware ? audit.medianWallSeconds : Double(audit.fullSuite.wallSeconds)
        return LoopModel(generationSeconds: generation, verificationSeconds: verification, iterations: 1)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Verification", selection: $useChangeAware) {
                        Text("Full suite").tag(false)
                        Text("Change-aware").tag(true)
                    }
                    .pickerStyle(.segmented)
                    VStack(alignment: .leading) {
                        Text("Agent generation pass: \(Int(generation))s").font(.subheadline)
                        Slider(value: $generation, in: 30...600, step: 30)
                    }
                }
                Section("One iteration") {
                    ShareBar(share: model.verificationShare)
                    HStack {
                        Metric(value: pct(model.verificationShare), label: "spent verifying")
                        Metric(value: minutes(Int(model.loopSeconds)), label: "per iteration")
                    }
                }
                Section {
                    HStack {
                        Metric(value: times(model.speedup(generationFactor: 2)), label: "2× faster model")
                        Metric(value: times(model.speedup(verificationFactor: 2)), label: "2× faster checks")
                    }
                    Metric(value: times(model.promptCeiling), label: "ceiling for a perfect prompt (generation → 0)")
                } header: {
                    Text("Where to spend")
                } footer: {
                    Text("Amdahl's law for the agent loop. Change-aware uses the median plan across the 20 sample changes.")
                }
            }
            .navigationTitle("Agent loop")
        }
    }
}

struct ShareBar: View {
    let share: Double
    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Rectangle().fill(Color.blue).frame(width: proxy.size.width * (1 - share))
                Rectangle().fill(Color.orange)
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
        .accessibilityLabel("Generation \(pct(1 - share)), verification \(pct(share))")
    }
}

// MARK: - Audit

struct AuditView: View {
    private let audit = SampleShopApp.audit()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Metric(value: audit.bottleneck == .harness ? "Harness" : "Prompt", label: "bottleneck")
                        Metric(value: pct(audit.selfVerifyRate), label: "changes the agent can verify")
                    }
                    Text("\(audit.passedCount) of \(audit.items.count) audit questions pass").font(.caption)
                } footer: {
                    Text("Median verification share is \(pct(audit.medianVerificationShare)) with a \(Int(SampleShopApp.generationSeconds))s generation pass. Above 50%, a better prompt is the wrong investment.")
                }
                Section("Is the harness the bottleneck?") {
                    ForEach(audit.items) { item in
                        HStack(alignment: .top) {
                            Image(systemName: item.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(item.passed ? Color.green : Color.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.question).font(.subheadline)
                                Text("\(pct1(item.value)) (target \(item.higherIsBetter ? "≥" : "≤") \(pct(item.threshold)))")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Harness audit")
        }
    }
}

// MARK: - Shared

struct Metric: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}

func pct(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
}

func pct1(_ value: Double) -> String {
    String(format: "%.1f%%", value * 100)
}

func minutes(_ seconds: Int) -> String {
    let safe = max(0, seconds)
    return safe < 60 ? "\(safe)s" : String(format: "%d:%02d", safe / 60, safe % 60)
}

func times(_ value: Double) -> String {
    value.isFinite ? String(format: "%.2f×", value) : "∞"
}
