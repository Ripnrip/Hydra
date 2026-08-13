import SwiftUI
import HydraCore

// MARK: - Dry Run Preview Data

/// Represents exactly what the hydration would create — every tag, link, and change.
/// This is the "diff before you commit" surface.
struct DryRunPreview: Identifiable {
    let id = UUID()

    // What will be created
    let newNotes: [PreviewNote]
    let updatedNotes: [PreviewNoteUpdate]
    let newTags: [PreviewTag]
    let newWikilinks: [PreviewWikilink]
    let newRelationships: [PreviewRelationship]
    let tagAssignments: [PreviewTagAssignment]
    let orphanRescues: [PreviewOrphanRescue]

    // Summary stats
    var totalChanges: Int {
        newNotes.count + updatedNotes.count + newTags.count +
        newWikilinks.count + newRelationships.count + orphanRescues.count
    }

    /// Sample preview from real SecondBrain data patterns
    static let sample = DryRunPreview(
        newNotes: [
            PreviewNote(
                path: "07-Sessions/2026-08-13--hydra-architecture--claude-code.md",
                title: "Hydra Architecture — Context Hydration Engine",
                kind: "session-summary",
                frontmatter: [
                    "type": "session-learning",
                    "agent": "claude-code",
                    "project": "hydra",
                    "date": "2026-08-13"
                ]
            ),
        ],
        updatedNotes: [
            PreviewNoteUpdate(
                path: "07-Sessions/2026-07-18--ai-ide-setup--claude-code.md",
                title: "AI-IDE Setup — Codebase Analysis",
                changes: [
                    "+ tag: project/hydra",
                    "+ wikilink: [[Hydra Architecture]]",
                    "+ relationship: derived-from → 2026-08-13--hydra-architecture",
                ]
            ),
        ],
        newTags: [
            PreviewTag(tag: "project/hydra", axis: "project", color: "#AE85FA", count: 3),
            PreviewTag(tag: "tool/swift", axis: "type", color: "#3B82F6", count: 5),
            PreviewTag(tag: "status/active", axis: "status", color: "#3EE08C", count: 2),
            PreviewTag(tag: "integration/claude", axis: "integration", color: "#BF7AF0", count: 8),
        ],
        newWikilinks: [
            PreviewWikilink(from: "AI-IDE Setup", to: "Hydra Architecture", type: "derived-from"),
            PreviewWikilink(from: "Hydra Architecture", to: "Second Brain Architecture", type: "references"),
            PreviewWikilink(from: "Hydra Architecture", to: "CLAUDE.md", type: "references"),
            PreviewWikilink(from: "Agent Workflow", to: "AI-IDE Setup", type: "relates-to"),
        ],
        newRelationships: [
            PreviewRelationship(
                from: "ai-ide-setup",
                to: "hydra-architecture",
                type: .derivedFrom,
                reason: "Same project lineage (agent infrastructure)"
            ),
            PreviewRelationship(
                from: "hydra-architecture",
                to: "second-brain",
                type: .implements,
                reason: "Implements the second-brain vault pattern"
            ),
            PreviewRelationship(
                from: "agent-workflow",
                to: "ai-ide-setup",
                type: .relatesTo,
                reason: "Shared tooling: Claude Code sessions"
            ),
            PreviewRelationship(
                from: "hydra-architecture",
                to: "andromeda",
                type: .references,
                reason: "Borrows Andromeda design system (purple accent)"
            ),
        ],
        tagAssignments: [
            PreviewTagAssignment(note: "AI-IDE Setup", tags: ["project/hydra", "tool/swift", "integration/claude"]),
            PreviewTagAssignment(note: "Hydra Architecture", tags: ["project/hydra", "tool/swift", "status/active"]),
            PreviewTagAssignment(note: "Agent Workflow", tags: ["project/hydra", "integration/claude"]),
        ],
        orphanRescues: [
            PreviewOrphanRescue(
                note: "2026-07-18--ai-ide-setup--claude-code.md",
                rescuedBy: "wikilink to [[Hydra Architecture]] + tag project/hydra",
                wasOrphan: true
            ),
        ]
    )
}

struct PreviewNote: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let title: String
    let kind: String
    let frontmatter: [String: String]
}

struct PreviewNoteUpdate: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let title: String
    let changes: [String]
}

struct PreviewTag: Identifiable, Hashable {
    let id = UUID()
    let tag: String
    let axis: String
    let color: String
    let count: Int
}

struct PreviewWikilink: Identifiable, Hashable {
    let id = UUID()
    let from: String
    let to: String
    let type: String
}

struct PreviewRelationship: Identifiable, Hashable {
    let id = UUID()
    let from: String
    let to: String
    let type: RelationshipType
    let reason: String
}

struct PreviewTagAssignment: Identifiable, Hashable {
    let id = UUID()
    let note: String
    let tags: [String]
}

struct PreviewOrphanRescue: Identifiable, Hashable {
    let id = UUID()
    let note: String
    let rescuedBy: String
    let wasOrphan: Bool
}

// MARK: - Dry Run Preview View

/// Shows exactly what WILL happen — every tag, link, note, relationship — before any write.
/// This is the "review before commit" surface senpai asked for.
struct DryRunPreviewView: View {
    let preview: DryRunPreview
    @State private var selectedSection: PreviewSection = .summary

    enum PreviewSection: String, CaseIterable {
        case summary = "Summary"
        case newNotes = "New Notes"
        case tagAssignments = "Tag Assignments"
        case newTags = "New Tags"
        case wikilinks = "Wikilinks"
        case relationships = "Relationships"
        case orphanRescues = "Orphan Rescues"
        case updates = "Note Updates"
    }

    init(preview: DryRunPreview = .sample) {
        self.preview = preview
    }

    var body: some View {
        HStack(spacing: 0) {
            // Section sidebar
            VStack(spacing: 2) {
                ForEach(PreviewSection.allCases, id: \.self) { section in
                    sectionButton(section)
                }
                Spacer()
            }
            .frame(width: 180)
            .background(Color.hydraPanel)
            .overlay(
                Rectangle().frame(width: 1).background(Color.hydraLine),
                alignment: .trailing
            )

            // Content
            ScrollView {
                sectionContent
                    .padding(24)
            }
            .background(Color.hydraVoid)
        }
        .background(Color.hydraVoid)
    }

    // MARK: Section Button

    @ViewBuilder
    private func sectionButton(_ section: PreviewSection) -> some View {
        let count = sectionCount(section)
        HStack(spacing: 8) {
            Text(section.rawValue)
                .font(HydraTheme.mono(.callout, weight: selectedSection == section ? .semibold : .regular))
                .foregroundStyle(selectedSection == section ? Color.hydraInk : Color.hydraMuted)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(HydraTheme.mono(.caption2, weight: .bold))
                    .foregroundStyle(selectedSection == section ? Color.hydraAccent : Color.hydraMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(selectedSection == section ? Color.hydraAccent.opacity(0.2) : Color.hydraMuted.opacity(0.1))
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(selectedSection == section ? Color.hydraSelection : Color.clear)
        .onTapGesture { selectedSection = section }
    }

    private func sectionCount(_ section: PreviewSection) -> Int {
        switch section {
        case .summary: 0
        case .newNotes: preview.newNotes.count
        case .tagAssignments: preview.tagAssignments.count
        case .newTags: preview.newTags.count
        case .wikilinks: preview.newWikilinks.count
        case .relationships: preview.newRelationships.count
        case .orphanRescues: preview.orphanRescues.count
        case .updates: preview.updatedNotes.count
        }
    }

    // MARK: Section Content

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .summary: summarySection
        case .newNotes: newNotesSection
        case .tagAssignments: tagAssignmentsSection
        case .newTags: newTagsSection
        case .wikilinks: wikilinksSection
        case .relationships: relationshipsSection
        case .orphanRescues: orphanRescuesSection
        case .updates: updatesSection
        }
    }

    // MARK: Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Dry Run Preview")
                .font(HydraTheme.display(.largeTitle))
                .foregroundStyle(Color.hydraInk)
            Text("Exactly what will be created, updated, and linked — nothing written yet.")
                .font(HydraTheme.mono(.subheadline))
                .foregroundStyle(Color.hydraMuted)

            HStack(spacing: 12) {
                HydraStatCard(title: "New Notes", value: "\(preview.newNotes.count)", icon: "doc.badge.plus", accentColor: .hydraAccent)
                HydraStatCard(title: "Tags Added", value: "\(preview.tagAssignments.reduce(0) { $0 + $1.tags.count })", icon: "tag.fill", accentColor: .hydraLive)
                HydraStatCard(title: "Wikilinks", value: "\(preview.newWikilinks.count)", icon: "link.fill", accentColor: .hydraPartial)
                HydraStatCard(title: "Orphans Rescued", value: "\(preview.orphanRescues.count)", icon: "bubble.left.and.bubble.right.fill", accentColor: Color(red: 0.75, green: 0.55, blue: 0.95))
            }

            HydraPanel(title: "New Tags", icon: "tag.circle.fill") {
                FlowingTagList(tags: preview.newTags)
            }

            HydraPanel(title: "Relationships Detected", icon: "link.circle.fill") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(preview.newRelationships) { rel in
                        HStack(spacing: 8) {
                            HydraTagChip(label: rel.from, color: .hydraAccent)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.hydraMuted)
                            HydraTagChip(label: rel.type.rawValue, color: relColor(rel.type))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.hydraMuted)
                            HydraTagChip(label: rel.to, color: .hydraAccent)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // MARK: New Notes

    private var newNotesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("New Notes", "\(preview.newNotes.count) notes will be created")
            ForEach(preview.newNotes) { note in
                HydraPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(Color.hydraAccent)
                            Text(note.title)
                                .font(HydraTheme.mono(.headline))
                                .foregroundStyle(Color.hydraInk)
                            Spacer()
                            HydraTagChip(label: note.kind, color: .hydraAccent)
                        }
                        Text(note.path)
                            .font(HydraTheme.mono(.caption))
                            .foregroundStyle(Color.hydraMuted)
                        Divider().background(Color.hydraLine)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FRONTMATTER")
                                .font(HydraTheme.mono(.caption2, weight: .semibold))
                                .tracking(1.5)
                                .foregroundStyle(Color.hydraMuted)
                            ForEach(Array(note.frontmatter.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                                HStack(spacing: 8) {
                                    Text(key)
                                        .font(HydraTheme.mono(.caption))
                                        .foregroundStyle(Color.hydraAccent)
                                    Text(value)
                                        .font(HydraTheme.mono(.caption))
                                        .foregroundStyle(Color.hydraInk)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Tag Assignments

    private var tagAssignmentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Tag Assignments", "Which notes get which tags")
            ForEach(preview.tagAssignments) { assignment in
                HydraPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(assignment.note)
                            .font(HydraTheme.mono(.headline))
                            .foregroundStyle(Color.hydraInk)
                        FlowingTags(tags: assignment.tags)
                    }
                }
            }
        }
    }

    // MARK: New Tags

    private var newTagsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("New Tags", "\(preview.newTags.count) tags not yet in vault")
            ForEach(preview.newTags) { tag in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: tag.color))
                        .frame(width: 12, height: 12)
                    Text(tag.tag)
                        .font(HydraTheme.mono(.callout))
                        .foregroundStyle(Color.hydraInk)
                    Spacer()
                    HydraTagChip(label: tag.axis, color: Color(hex: tag.color))
                    Text("\(tag.count) notes")
                        .font(HydraTheme.mono(.caption2))
                        .foregroundStyle(Color.hydraMuted)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 16)
                .background(Color.hydraCard)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.hydraLine, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: Wikilinks

    private var wikilinksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Wikilinks", "\(preview.newWikilinks.count) connections will be added")
            ForEach(preview.newWikilinks) { link in
                HStack(spacing: 10) {
                    Text(link.from)
                        .font(HydraTheme.mono(.callout))
                        .foregroundStyle(Color.hydraInk)
                    HydraTagChip(label: link.type, color: .hydraAccent)
                    Text("[[\(link.to)]]")
                        .font(HydraTheme.mono(.callout))
                        .foregroundStyle(Color.hydraAccent)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.hydraCard)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.hydraLine, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: Relationships

    private var relationshipsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Relationships", "\(preview.newRelationships.count) typed connections inferred")
            ForEach(preview.newRelationships) { rel in
                HydraPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            HydraTagChip(label: rel.from, color: .hydraAccent)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.hydraMuted)
                            HydraTagChip(label: rel.type.rawValue, color: relColor(rel.type))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.hydraMuted)
                            HydraTagChip(label: rel.to, color: .hydraAccent)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.hydraMuted)
                            Text(rel.reason)
                                .font(HydraTheme.mono(.caption))
                                .foregroundStyle(Color.hydraMuted)
                        }
                    }
                }
            }
        }
    }

    // MARK: Orphan Rescues

    private var orphanRescuesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Orphan Rescues", "\(preview.orphanRescues.count) orphaned notes will gain connections")
            ForEach(preview.orphanRescues) { rescue in
                HydraPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .foregroundStyle(Color.hydraLive)
                            Text(rescue.note)
                                .font(HydraTheme.mono(.callout))
                                .foregroundStyle(Color.hydraInk)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.hydraLive)
                            Text(rescue.rescuedBy)
                                .font(HydraTheme.mono(.caption))
                                .foregroundStyle(Color.hydraMuted)
                        }
                    }
                }
            }
        }
    }

    // MARK: Updates

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Note Updates", "\(preview.updatedNotes.count) existing notes will be modified")
            ForEach(preview.updatedNotes) { update in
                HydraPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(update.title)
                            .font(HydraTheme.mono(.headline))
                            .foregroundStyle(Color.hydraInk)
                        Text(update.path)
                            .font(HydraTheme.mono(.caption2))
                            .foregroundStyle(Color.hydraMuted)
                        Divider().background(Color.hydraLine)
                        ForEach(update.changes, id: \.self) { change in
                            Text(change)
                                .font(HydraTheme.mono(.caption, weight: .medium))
                                .foregroundStyle(change.hasPrefix("+") ? Color.hydraLive : Color.hydraAlert)
                        }
                    }
                }
            }
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(HydraTheme.display(.title))
                .foregroundStyle(Color.hydraInk)
            Text(subtitle)
                .font(HydraTheme.mono(.subheadline))
                .foregroundStyle(Color.hydraMuted)
        }
    }

    private func relColor(_ type: RelationshipType) -> Color {
        switch type {
        case .implements: .hydraLive
        case .dependsOn: .hydraAlert
        case .supersedes: Color(red: 0.75, green: 0.55, blue: 0.95)
        case .references: .hydraAccent
        case .childOf: .hydraMuted
        case .derivedFrom: Color(red: 0.45, green: 0.75, blue: 0.95)
        case .relatesTo: .hydraPartial
        case .blocks: .hydraAlert
        }
    }
}

// MARK: - Flowing Tag Layout

struct FlowingTags: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HydraTagChip(label: tag, color: tagColor(tag))
            }
        }
    }

    private func tagColor(_ tag: String) -> Color {
        if tag.contains("project") { return .hydraAccent }
        if tag.contains("tool") { return Color(red: 0.45, green: 0.75, blue: 0.95) }
        if tag.contains("status") { return .hydraLive }
        if tag.contains("integration") { return Color(red: 0.75, green: 0.55, blue: 0.95) }
        return .hydraMuted
    }
}

struct FlowingTagList: View {
    let tags: [PreviewTag]

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(tags) { tag in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: tag.color))
                        .frame(width: 6, height: 6)
                    Text(tag.tag)
                        .font(HydraTheme.mono(.caption2, weight: .medium))
                }
                .foregroundStyle(Color(hex: tag.color))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(hex: tag.color).opacity(0.1)))
                .overlay(Capsule().strokeBorder(Color(hex: tag.color).opacity(0.3), lineWidth: 1))
            }
        }
    }
}

// MARK: - Simple Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: r = (int >> 16) & 0xFF; g = (int >> 8) & 0xFF; b = int & 0xFF
        default: r = 0; g = 0; b = 0
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
