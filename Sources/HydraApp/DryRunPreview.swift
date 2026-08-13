import SwiftUI
import HydraCore
import HydraVault

// MARK: - Dry Run Preview

/// Shows exactly what the hydration pipeline WOULD do — per artifact.
/// This is the "git diff for your vault" view. Tags, links, paths, frontmatter —
/// all visible before anything is written.
struct DryRunPreviewView: View {
    let artifacts: [SourceArtifact]
    let vaultPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary header
            HStack(spacing: 12) {
                HydraStatCard(title: "Artifacts", value: "\(artifacts.count)", icon: "doc.text.fill", accentColor: .hydraAccent)
                HydraStatCard(title: "New Tags", value: "\(newTags.count)", icon: "tag.fill", accentColor: .hydraLive)
                HydraStatCard(title: "New Links", value: "\(totalLinks)", icon: "link.fill", accentColor: .hydraPartial)
                HydraStatCard(title: "New Notes", value: "\(newNotes)", icon: "plus.circle.fill", accentColor: .hydraAccent)
            }

            // Per-artifact preview
            ForEach(artifacts) { artifact in
                DryRunArtifactRow(artifact: artifact, vaultPath: vaultPath)
            }
        }
        .padding(24)
    }

    private var newTags: Set<String> {
        Set(artifacts.flatMap { $0.tags })
    }

    private var totalLinks: Int {
        artifacts.reduce(0) { $0 + $1.relationships.count + $1.wikilinks.count }
    }

    private var newNotes: Int {
        artifacts.count  // all would be new notes (no dedup yet)
    }
}

// MARK: - Dry Run Artifact Row

struct DryRunArtifactRow: View {
    let artifact: SourceArtifact
    let vaultPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title + kind + lifecycle
            HStack(spacing: 8) {
                Image(systemName: kindIcon)
                    .foregroundStyle(Color.hydraAccent)
                    .font(.system(size: 14))
                Text(artifact.title)
                    .font(HydraTheme.mono(.callout, weight: .semibold))
                    .foregroundStyle(Color.hydraInk)
                Spacer()
                Text(artifact.lifecycleState.rawValue.uppercased())
                    .font(HydraTheme.mono(.caption2, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(lifecycleColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(lifecycleColor.opacity(0.12), in: Capsule())
            }

            // Target path
            HStack(spacing: 4) {
                Image(systemName: "arrow.right.square.fill")
                    .foregroundStyle(Color.hydraMuted)
                    .font(.system(size: 10))
                Text("will write to:")
                    .font(HydraTheme.mono(.caption2))
                    .foregroundStyle(Color.hydraMuted)
                Text(targetPath)
                    .font(HydraTheme.mono(.caption2, weight: .medium))
                    .foregroundStyle(Color.hydraAccent)
            }

            // Tags that would be applied
            if !artifact.tags.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TAGS")
                        .font(.system(size: 8, design: .monospaced).weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(Color.hydraMuted)
                    FlowLayout(spacing: 4) {
                        ForEach(artifact.tags.sorted(), id: \.self) { tag in
                            DryRunTagChip(tag: tag)
                        }
                    }
                }
            }

            // Wikilinks that would be created
            if !artifact.wikilinks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WIKILINKS")
                        .font(.system(size: 8, design: .monospaced).weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(Color.hydraMuted)
                    ForEach(artifact.wikilinks.prefix(5), id: \.self) { link in
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .foregroundStyle(Color.hydraAccent.opacity(0.6))
                                .font(.system(size: 9))
                            Text("[[\(link)]]")
                                .font(HydraTheme.mono(.caption2))
                                .foregroundStyle(Color.hydraInk.opacity(0.8))
                        }
                    }
                    if artifact.wikilinks.count > 5 {
                        Text("+ \(artifact.wikilinks.count - 5) more")
                            .font(HydraTheme.mono(.caption2))
                            .foregroundStyle(Color.hydraMuted)
                    }
                }
            }

            // Provenance
            HStack(spacing: 4) {
                Image(systemName: provenanceIcon)
                    .foregroundStyle(Color.hydraMuted)
                    .font(.system(size: 9))
                Text("source: \(artifact.provenance.authority.rawValue) · confidence: \(Int(artifact.confidence * 100))%")
                    .font(HydraTheme.mono(.caption2))
                    .foregroundStyle(Color.hydraMuted)
            }
        }
        .padding(14)
        .background(Color.hydraPanel.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var targetPath: String {
        "\(artifact.kind.vaultSubpath)/\(artifact.title.replacingOccurrences(of: " ", with: "-")).md"
    }

    private var kindIcon: String {
        switch artifact.kind {
        case .plan:     "doc.text.magnifyingglass"
        case .session:  "bubble.left.and.bubble.right.fill"
        case .decision: "checkmark.seal.fill"
        case .changelog: "list.bullet.rectangle.fill"
        case .note:     "doc.fill"
        default:        "doc.fill"
        }
    }

    private var lifecycleColor: Color {
        switch artifact.lifecycleState {
        case .completed: Color.hydraLive
        case .active:    Color.hydraAccent
        case .draft:     Color.hydraMuted
        default:         Color.hydraMuted
        }
    }

    private var provenanceIcon: String {
        switch artifact.provenance.authority {
        case .gitReceipt:         "checkmark.seal.fill"
        case .controlPlaneLedger: "server.rack"
        case .changelog:          "doc.text"
        case .observation:        "eye"
        case .wikiNote:           "book"
        }
    }
}

// MARK: - Dry Run Tag Chip

struct DryRunTagChip: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.system(size: 8, design: .monospaced).weight(.medium))
            .foregroundStyle(Color.hydraAccent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.hydraAccent.opacity(0.1), in: Capsule())
    }
}

// MARK: - Flow Layout (simple wrapping)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var width: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth + size.width > maxWidth && lineWidth > 0 {
                width = max(width, lineWidth)
                height += lineHeight + spacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
        }
        width = max(width, lineWidth)
        height += lineHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth && x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
