import SwiftUI
import HydraCore

// MARK: - Tag Chip

/// Colored tag pill for display in lists, cards, and the tag editor.
/// Color comes from the ColorTag's axis + value mapping.
struct TagChip: View {
    let colorTag: ColorTag
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(nsColor: nsColor))
                .frame(width: 8, height: 8)
            Text("\(colorTag.axis.rawValue)/\(colorTag.value)")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: nsColor).opacity(0.1))
        )
        .overlay(
            Capsule()
                .strokeBorder(isSelected ? Color.accentColor : Color(nsColor: nsColor).opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
    }

    private var nsColor: NSColor {
        NSColor(
            calibratedRed: CGFloat(colorTag.color.r) / 255,
            green: CGFloat(colorTag.color.g) / 255,
            blue: CGFloat(colorTag.color.b) / 255,
            alpha: 1.0
        )
    }
}

// MARK: - Confidence Meter

/// Horizontal bar showing classification confidence (0.0 → 1.0).
/// Green ≥ 0.8, yellow ≥ 0.5, red < 0.5.
struct ConfidenceMeter: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.2))
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor)
                    .frame(width: geo.size.width * value)
            }
        }
        .frame(height: 8)
        .overlay(alignment: .trailing) {
            Text("\(Int(value * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.trailing, 2)
        }
    }

    private var barColor: Color {
        if value >= 0.8 { .green }
        else if value >= 0.5 { .yellow }
        else { .red }
    }
}

// MARK: - Provenance Badge

/// Small badge showing the authority source of an artifact's metadata.
/// Higher authority = more prominent styling.
struct ProvenanceBadge: View {
    let authority: Authority

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(badgeColor.opacity(0.15)))
        .foregroundStyle(badgeColor)
    }

    private var icon: String {
        switch authority {
        case .gitReceipt: "checkmark.seal.fill"
        case .controlPlaneLedger: "server.rack"
        case .changelog: "doc.text"
        case .observation: "eye"
        case .wikiNote: "book"
        }
    }

    private var label: String {
        switch authority {
        case .gitReceipt: "Git"
        case .controlPlaneLedger: "Ledger"
        case .changelog: "Changelog"
        case .observation: "Observation"
        case .wikiNote: "Wiki"
        }
    }

    private var badgeColor: Color {
        switch authority {
        case .gitReceipt: .green
        case .controlPlaneLedger: .blue
        case .changelog: .teal
        case .observation: .orange
        case .wikiNote: .gray
        }
    }
}

// MARK: - Lifecycle Badge

/// Colored badge for artifact lifecycle state.
struct LifecycleBadge: View {
    let state: LifecycleState

    var body: some View {
        Text(state.rawValue)
            .font(.caption)
            .fontWeight(.semibold)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(badgeColor.opacity(0.15)))
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch state {
        case .draft: .gray
        case .accepted: .blue
        case .active: .blue
        case .completed: .green
        case .superseded: .purple
        case .abandoned: .red
        case .archived: .secondary
        }
    }
}

// MARK: - Delivery State Pill

/// Pill showing the artifact's position in the 8-state delivery pipeline.
struct DeliveryStatePill: View {
    let state: DeliveryState

    var body: some View {
        HStack(spacing: 3) {
            if state == .certified {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if state == .blocked {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
            Text(state.rawValue)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(pillColor.opacity(0.12)))
        .foregroundStyle(pillColor)
    }

    private var pillColor: Color {
        switch state {
        case .submitted: .gray
        case .validated: .teal
        case .canonicalCommitted: .blue
        case .canonicalReachable: .blue
        case .projectionCommitted: .indigo
        case .gitlinkPinned: .purple
        case .certified: .green
        case .blocked: .red
        }
    }
}
