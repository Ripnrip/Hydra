import SwiftUI
import HydraCore

// MARK: - Tag Chip (Hydra themed)

struct TagChip: View {
    let colorTag: ColorTag
    var isSelected: Bool = false

    private var themeColor: Color {
        switch colorTag.axis {
        case .project: .hydraAccent
        case .type: Color(red: 0.45, green: 0.75, blue: 0.95)
        case .status: .hydraLive
        case .integration: Color(red: 0.75, green: 0.55, blue: 0.95)
        case .severity: .hydraAlert
        }
    }

    var body: some View {
        HydraTagChip(label: "\(colorTag.axis.rawValue)/\(colorTag.value)", color: themeColor, isSelected: isSelected)
    }
}

// MARK: - Confidence Meter

struct ConfidenceMeter: View {
    let value: Double

    private var barColor: Color {
        if value >= 0.8 { .hydraLive }
        else if value >= 0.5 { .hydraPartial }
        else { .hydraAlert }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.hydraMuted.opacity(0.2))
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor)
                    .frame(width: geo.size.width * value)
                    .shadow(color: barColor.opacity(0.4), radius: 2)
            }
        }
        .frame(height: 6)
        .overlay(alignment: .trailing) {
            Text("\(Int(value * 100))%")
                .font(HydraTheme.mono(.caption2, weight: .semibold))
                .foregroundStyle(Color.hydraMuted)
                .padding(.trailing, 2)
        }
    }
}

// MARK: - Provenance Badge

struct ProvenanceBadge: View {
    let authority: Authority

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
        case .gitReceipt: .hydraLive
        case .controlPlaneLedger: .hydraAccent
        case .changelog: Color(red: 0.3, green: 0.8, blue: 0.85)
        case .observation: .hydraPartial
        case .wikiNote: .hydraMuted
        }
    }

    var body: some View {
        HydraTagChip(label: label, color: badgeColor)
    }
}

// MARK: - Lifecycle Badge

struct LifecycleBadge: View {
    let state: LifecycleState

    private var badgeColor: Color {
        switch state {
        case .draft: .hydraMuted
        case .accepted, .active: .hydraAccent
        case .completed: .hydraLive
        case .superseded: Color(red: 0.75, green: 0.55, blue: 0.95)
        case .abandoned: .hydraAlert
        case .archived: .hydraMuted.opacity(0.6)
        }
    }

    var body: some View {
        HydraTagChip(label: state.rawValue, color: badgeColor)
    }
}

// MARK: - Delivery State Pill

struct DeliveryStatePill: View {
    let state: DeliveryState

    private var pillColor: Color {
        switch state {
        case .submitted: .hydraMuted
        case .validated: Color(red: 0.3, green: 0.8, blue: 0.85)
        case .canonicalCommitted, .canonicalReachable: .hydraAccent
        case .projectionCommitted: Color(red: 0.6, green: 0.5, blue: 0.9)
        case .gitlinkPinned: Color(red: 0.75, green: 0.55, blue: 0.95)
        case .certified: .hydraLive
        case .blocked: .hydraAlert
        }
    }

    private var icon: String? {
        switch state {
        case .certified: "checkmark.circle.fill"
        case .blocked: "exclamationmark.circle.fill"
        default: nil
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9))
            }
            Text(state.rawValue)
                .font(HydraTheme.mono(.caption2, weight: .medium))
                .tracking(0.3)
        }
        .foregroundStyle(pillColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(pillColor.opacity(0.12)))
        .overlay(Capsule().strokeBorder(pillColor.opacity(0.3), lineWidth: 1))
    }
}
