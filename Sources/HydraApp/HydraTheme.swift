import SwiftUI

// MARK: - Hydra Design System
// Adapted from Andromeda's obsidian-space aesthetic.
// Senpai directive: replace teal with light purple. Everything else follows Andromeda.

extension Color {
    /// Primary accent — light purple (replaces Andromeda teal)
    static let hydraAccent = Color(red: 0.68, green: 0.52, blue: 0.98)  // #AE85FA
    /// Hover / glow — brighter purple
    static let hydraGlow = Color(red: 0.82, green: 0.72, blue: 1.0)    // #D1B8FF
    /// Healthy / live status — green
    static let hydraLive = Color(red: 0.24, green: 0.87, blue: 0.55)   // #3EE08C
    /// Degraded / alert — warm coral
    static let hydraAlert = Color(red: 1.0, green: 0.62, blue: 0.58)   // #FF9D94
    /// Warning / partial — amber
    static let hydraPartial = Color(red: 0.90, green: 0.75, blue: 0.34) // #E6C057
    /// Primary text (ink) — near-white with cool tint
    static let hydraInk = Color(red: 0.91, green: 0.88, blue: 0.97)    // #E8E0F8
    /// Muted / secondary text
    static let hydraMuted = Color(red: 0.50, green: 0.46, blue: 0.60)  // #80769A
    /// Void background — deep obsidian with purple tint
    static let hydraVoid = Color(red: 0.05, green: 0.03, blue: 0.08)   // #0D0814
    /// Panel surface — one step above void
    static let hydraPanel = Color(red: 0.09, green: 0.06, blue: 0.13)  // #170F21
    /// Card surface — two steps above void
    static let hydraCard = Color(red: 0.12, green: 0.08, blue: 0.17)   // #1F142B
    /// Popover / floating surface
    static let hydraPopover = Color(red: 0.10, green: 0.07, blue: 0.15) // #1A1126

    // Accent-tinted utility colors
    static let hydraLine = Color.hydraAccent.opacity(0.15)
    static let hydraSelection = Color.hydraAccent.opacity(0.14)
    static let hydraHover = Color.hydraAccent.opacity(0.07)
}

// MARK: - Theme

enum HydraTheme {
    // Corner radius (matches Andromeda: 14pt)
    static let cornerRadius: CGFloat = 14
    static let smallCornerRadius: CGFloat = 8

    // Fonts
    static func mono(_ style: Font.TextStyle = .callout, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }

    static func display(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .serif)
    }

    // Background view modifier — forces dark obsidian ground
    static func background<V: View>(_ view: V) -> some View {
        view.background(Color.hydraVoid)
    }
}

// MARK: - Panel Container

/// A card-style panel with the Hydra dark aesthetic.
struct HydraPanel<Content: View>: View {
    var title: String?
    var icon: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .foregroundStyle(Color.hydraAccent)
                            .font(.system(size: 14))
                    }
                    Text(title)
                        .font(HydraTheme.mono(.headline, weight: .semibold))
                        .foregroundStyle(Color.hydraInk)
                        .tracking(0.5)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }
            content
                .padding(title != nil ? .horizontal : [], 16)
                .padding(title != nil ? .bottom : [], 16)
        }
        .background(Color.hydraPanel)
        .overlay(
            RoundedRectangle(cornerRadius: HydraTheme.cornerRadius)
                .strokeBorder(Color.hydraLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: HydraTheme.cornerRadius))
    }
}

// MARK: - Glow Button

/// Primary action button with purple glow.
struct HydraButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Color.hydraVoid)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: HydraTheme.smallCornerRadius)
                        .fill(Color.hydraAccent)
                    RoundedRectangle(cornerRadius: HydraTheme.smallCornerRadius)
                        .fill(Color.hydraGlow.opacity(0.3))
                        .blur(radius: 8)
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status Dot

/// Colored dot for status indicators — never communicates by color alone.
struct HydraStatusDot: View {
    let color: Color
    var pulsing: Bool = false

    @State private var glow = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(glow ? 0.8 : 0.3), radius: glow ? 6 : 3)
            .animation(
                pulsing ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : nil,
                value: glow
            )
            .onAppear { if pulsing { glow = true } }
            .accessibilityHidden(true)
    }
}

// MARK: - Tag Chip (Hydra styled)

/// Purple-themed tag chip replacing the default macOS styling.
struct HydraTagChip: View {
    let label: String
    let color: Color
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(HydraTheme.mono(.caption2, weight: .medium))
                .tracking(0.3)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isSelected ? Color.hydraAccent.opacity(0.2) : color.opacity(0.1))
        )
        .overlay(
            Capsule()
                .strokeBorder(isSelected ? Color.hydraAccent : color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Stat Card

/// Compact metric display for dashboard panels.
struct HydraStatCard: View {
    let title: String
    let value: String
    let icon: String
    var accentColor: Color = .hydraAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(accentColor)
                    .font(.system(size: 12))
                Text(title.uppercased())
                    .font(HydraTheme.mono(.caption2, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.hydraMuted)
            }
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.hydraInk)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hydraCard)
        .overlay(
            RoundedRectangle(cornerRadius: HydraTheme.smallCornerRadius)
                .strokeBorder(Color.hydraLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: HydraTheme.smallCornerRadius))
    }
}
