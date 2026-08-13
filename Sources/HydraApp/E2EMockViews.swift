import SwiftUI
import HydraCore

// MARK: - E2E Flow State

/// Tracks the hydration pipeline state for snapshot-driven UI testing.
/// Each step produces a distinct visual state that can be snapshotted.
enum HydrationFlowStep: String, CaseIterable {
    case idle
    case scanning
    case scanned
    case classifying
    case classified
    case reviewing
    case writing
    case complete
}

@MainActor
final class HydrationFlowState: ObservableObject {
    @Published var step: HydrationFlowStep = .idle
    @Published var sourcePath: String = "~/.claude/plans"
    @Published var vaultPath: String = "~/Developer/MyVault"
    @Published var discoveredCount: Int = 0
    @Published var classifiedCount: Int = 0
    @Published var tagsGenerated: Int = 0
    @Published var relationshipsFound: Int = 0
    @Published var writtenCount: Int = 0
    @Published var discoveredItems: [DiscoveredItem] = []
    @Published var classifiedItems: [ClassifiedItem] = []

    struct DiscoveredItem: Identifiable, Hashable {
        let id = UUID()
        let path: String
        let title: String
        let size: String
    }

    struct ClassifiedItem: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let kind: String
        let tags: [String]
        let confidence: Double
        let provenance: String
    }

    func populateSampleData() {
        discoveredItems = [
            .init(path: "tidy-moseying-whisper.md", title: "AI-IDE Setup — Codebase Analysis", size: "4.2 KB"),
            .init(path: "tidy-moseying-whisper-agent.md", title: "Agent Workflow — Session Plan", size: "6.8 KB"),
        ]
        discoveredCount = discoveredItems.count

        classifiedItems = [
            .init(title: "AI-IDE Setup — Codebase Analysis",
                  kind: "session-summary",
                  tags: ["project/ai-ide-setup", "type/discovery", "integration/claude"],
                  confidence: 0.92,
                  provenance: "git"),
            .init(title: "Agent Workflow — Session Plan",
                  kind: "plan",
                  tags: ["project/agent-workflow", "type/plan", "status/active"],
                  confidence: 0.87,
                  provenance: "git"),
        ]
        classifiedCount = classifiedItems.count
        tagsGenerated = 6
        relationshipsFound = 4
    }

    func advance() {
        switch step {
        case .idle: step = .scanning
        case .scanning:
            step = .scanned
            populateSampleData()
        case .scanned: step = .classifying
        case .classifying: step = .classified
        case .classified: step = .reviewing
        case .reviewing: step = .writing
        case .writing:
            step = .complete
            writtenCount = classifiedCount
        case .complete: step = .idle
        }
    }
}

// MARK: - E2E Flow View

/// The full hydration flow UI — designed so each step can be snapshotted.
struct E2EHydrationFlowView: View {
    @StateObject private var state = HydrationFlowState()
    var fixedStep: HydrationFlowStep?

    init(fixedStep: HydrationFlowStep? = nil) {
        self.fixedStep = fixedStep
    }

    var body: some View {
        let currentStep = fixedStep ?? state.step

        if fixedStep == nil {
            interactiveBody(currentStep: currentStep)
        } else {
            staticBody(currentStep: currentStep)
        }
    }

    @ViewBuilder
    private func interactiveBody(currentStep: HydrationFlowStep) -> some View {
        VStack(spacing: 0) {
            flowHeader(currentStep: currentStep)
            stepContent(currentStep: currentStep)
            flowFooter(currentStep: currentStep)
        }
        .background(Color.hydraVoid)
        .frame(width: 900, height: 600)
    }

    @ViewBuilder
    private func staticBody(currentStep: HydrationFlowStep) -> some View {
        VStack(spacing: 0) {
            flowHeader(currentStep: currentStep)
            stepContent(currentStep: currentStep)
        }
        .background(Color.hydraVoid)
        .frame(width: 900, height: 600)
    }

    // MARK: Header (pipeline progress)

    @ViewBuilder
    private func flowHeader(currentStep: HydrationFlowStep) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(HydrationFlowStep.allCases.enumerated()), id: \.element) { idx, step in
                HStack(spacing: 6) {
                    Circle()
                        .fill(stepCircleColor(step, current: currentStep))
                        .frame(width: 10, height: 10)
                    Text(step.rawValue)
                        .font(HydraTheme.mono(.caption2, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(stepTextColor(step, current: currentStep))
                }
                .padding(.horizontal, 8)

                if idx < HydrationFlowStep.allCases.count - 1 {
                    Rectangle()
                        .fill(stepLineColor(step, current: currentStep))
                        .frame(height: 1)
                        .frame(maxWidth: 30)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.hydraPanel)
    }

    // MARK: Step Content

    @ViewBuilder
    private func stepContent(currentStep: HydrationFlowStep) -> some View {
        switch currentStep {
        case .idle: idleView
        case .scanning: scanningView
        case .scanned: scannedView
        case .classifying: classifyingView
        case .classified: classifiedView
        case .reviewing: reviewingView
        case .writing: writingView
        case .complete: completeView
        }
    }

    // MARK: Step Views

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "drop.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.hydraAccent.opacity(0.4))
            Text("Ready to Hydrate")
                .font(HydraTheme.display(.title))
                .foregroundStyle(Color.hydraInk)
            Text("Source: \(state.sourcePath)\nVault: \(state.vaultPath)")
                .font(HydraTheme.mono(.subheadline))
                .foregroundStyle(Color.hydraMuted)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(Color.hydraAccent)
            Text("Scanning source...")
                .font(HydraTheme.mono(.headline))
                .foregroundStyle(Color.hydraInk)
            Text(state.sourcePath)
                .font(HydraTheme.mono(.callout))
                .foregroundStyle(Color.hydraMuted)
            Spacer()
        }
    }

    private var scannedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HydraStatCard(title: "Discovered", value: "\(state.discoveredCount)", icon: "doc.text.fill")
                HydraStatCard(title: "Total Size", value: "11 KB", icon: "internaldrive", accentColor: .hydraPartial)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            HydraPanel(title: "Source Files", icon: "folder.fill") {
                VStack(spacing: 8) {
                    ForEach(state.discoveredItems) { item in
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(Color.hydraAccent)
                                .font(.system(size: 12))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(HydraTheme.mono(.callout))
                                    .foregroundStyle(Color.hydraInk)
                                Text(item.path)
                                    .font(HydraTheme.mono(.caption2))
                                    .foregroundStyle(Color.hydraMuted)
                            }
                            Spacer()
                            Text(item.size)
                                .font(HydraTheme.mono(.caption2))
                                .foregroundStyle(Color.hydraMuted)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var classifyingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(Color.hydraAccent)
            Text("Classifying + tagging...")
                .font(HydraTheme.mono(.headline))
                .foregroundStyle(Color.hydraInk)
            Text("Running tag engine, relationship linker, provenance resolver")
                .font(HydraTheme.mono(.subheadline))
                .foregroundStyle(Color.hydraMuted)
            Spacer()
        }
    }

    private var classifiedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                HydraStatCard(title: "Classified", value: "\(state.classifiedCount)", icon: "tag.fill")
                HydraStatCard(title: "Tags", value: "\(state.tagsGenerated)", icon: "number.circle.fill", accentColor: .hydraLive)
                HydraStatCard(title: "Relations", value: "\(state.relationshipsFound)", icon: "link.circle.fill", accentColor: .hydraPartial)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            HydraPanel(title: "Classification Results", icon: "sparkles") {
                VStack(spacing: 12) {
                    ForEach(state.classifiedItems) { item in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(HydraTheme.mono(.callout, weight: .medium))
                                    .foregroundStyle(Color.hydraInk)
                                HStack(spacing: 6) {
                                    HydraTagChip(label: item.kind, color: .hydraAccent)
                                    ForEach(item.tags.prefix(3), id: \.self) { tag in
                                        HydraTagChip(label: tag, color: tagColor(tag))
                                    }
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                HydraTagChip(label: item.provenance, color: .hydraLive)
                                Text("\(Int(item.confidence * 100))%")
                                    .font(HydraTheme.mono(.caption2, weight: .bold))
                                    .foregroundStyle(item.confidence > 0.8 ? Color.hydraLive : Color.hydraPartial)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var reviewingView: some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.hydraLive.opacity(0.6))
                Text("Review Complete")
                    .font(HydraTheme.display(.title))
                    .foregroundStyle(Color.hydraInk)
                Text("\(state.classifiedCount) items ready to write\n\(state.tagsGenerated) tags · \(state.relationshipsFound) relationships")
                    .font(HydraTheme.mono(.subheadline))
                    .foregroundStyle(Color.hydraMuted)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
    }

    private var writingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(Color.hydraLive)
            Text("Writing to vault...")
                .font(HydraTheme.mono(.headline))
                .foregroundStyle(Color.hydraInk)
            Text("\(state.vaultPath)/wiki/recaps/sessions/")
                .font(HydraTheme.mono(.callout))
                .foregroundStyle(Color.hydraMuted)
            Spacer()
        }
    }

    private var completeView: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.hydraLive)
                    .shadow(color: Color.hydraLive.opacity(0.4), radius: 10)
                Text("Hydration Complete")
                    .font(HydraTheme.display(.title))
                    .foregroundStyle(Color.hydraInk)
                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("\(state.writtenCount)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.hydraAccent)
                        Text("WRITTEN")
                            .font(HydraTheme.mono(.caption2, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(Color.hydraMuted)
                    }
                    VStack(spacing: 4) {
                        Text("\(state.tagsGenerated)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.hydraLive)
                        Text("TAGS")
                            .font(HydraTheme.mono(.caption2, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(Color.hydraMuted)
                    }
                    VStack(spacing: 4) {
                        Text("\(state.relationshipsFound)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.hydraPartial)
                        Text("LINKS")
                            .font(HydraTheme.mono(.caption2, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(Color.hydraMuted)
                    }
                }
                .padding(.top, 8)
            }
            Spacer()
        }
    }

    // MARK: Footer

    @ViewBuilder
    private func flowFooter(currentStep: HydrationFlowStep) -> some View {
        HStack {
            Text("DRY RUN")
                .font(HydraTheme.mono(.caption2, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Color.hydraPartial)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.hydraPartial.opacity(0.12)))

            Spacer()

            if currentStep != .idle && currentStep != .complete {
                Text(currentStep.rawValue.uppercased() + "...")
                    .font(HydraTheme.mono(.caption2))
                    .foregroundStyle(Color.hydraMuted)
            }

            if currentStep == .idle || currentStep == .scanned || currentStep == .classified || currentStep == .complete {
                HydraButton(
                    currentStep == .idle ? "Start" :
                    currentStep == .scanned ? "Classify" :
                    currentStep == .classified ? "Review" :
                    "Done",
                    icon: currentStep == .complete ? "checkmark" : "arrow.right"
                ) {
                    state.advance()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.hydraPanel)
    }

    // MARK: Helpers

    private func stepCircleColor(_ step: HydrationFlowStep, current: HydrationFlowStep) -> Color {
        let order = HydrationFlowStep.allCases
        let stepIdx = order.firstIndex(of: step) ?? 0
        let currentIdx = order.firstIndex(of: current) ?? 0
        if stepIdx < currentIdx { return .hydraLive }
        if stepIdx == currentIdx { return .hydraAccent }
        return .hydraMuted.opacity(0.3)
    }

    private func stepTextColor(_ step: HydrationFlowStep, current: HydrationFlowStep) -> Color {
        let order = HydrationFlowStep.allCases
        let stepIdx = order.firstIndex(of: step) ?? 0
        let currentIdx = order.firstIndex(of: current) ?? 0
        if stepIdx <= currentIdx { return .hydraInk }
        return .hydraMuted
    }

    private func stepLineColor(_ step: HydrationFlowStep, current: HydrationFlowStep) -> Color {
        let order = HydrationFlowStep.allCases
        let stepIdx = order.firstIndex(of: step) ?? 0
        let currentIdx = order.firstIndex(of: current) ?? 0
        if stepIdx < currentIdx { return .hydraLive.opacity(0.5) }
        return .hydraLine
    }

    private func tagColor(_ tag: String) -> Color {
        if tag.contains("project") { return .hydraAccent }
        if tag.contains("type") { return Color(red: 0.45, green: 0.75, blue: 0.95) }
        if tag.contains("status") { return .hydraLive }
        if tag.contains("integration") { return Color(red: 0.75, green: 0.55, blue: 0.95) }
        return .hydraMuted
    }
}
