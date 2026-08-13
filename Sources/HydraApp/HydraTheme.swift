import SwiftUI

// MARK: - Hydra Design System
// Adaptive light + dark theme. Purple accent on both.
// Dark: obsidian void ground. Light: warm lavender paper.

// MARK: - Adaptive Color Tokens

/// All theme colors adapt to light/dark automatically.
/// Access via the `HydraColors` namespace or the `Color.hydra*` shortcuts.
enum HydraColors {
    // Accent colors (same in both modes)
    static let accent = Color(red: 0.55, green: 0.35, blue: 0.90)   // #8C59E6 (darker for contrast)
    static let accentLight = Color(red: 0.68, green: 0.52, blue: 0.98) // #AE85FA
    static let glow = Color(red: 0.82, green: 0.72, blue: 1.0)     // #D1B8FF
    static let live = Color(red: 0.20, green: 0.78, blue: 0.48)    // #33C76F
    static let alert = Color(red: 0.90, green: 0.35, blue: 0.30)   // #E6594D
    static let partial = Color(red: 0.82, green: 0.65, blue: 0.20) // #D1A633

    // Dark mode palette
    static let inkDark = Color(red: 0.91, green: 0.88, blue: 0.97)    // #E8E0F8
    static let mutedDark = Color(red: 0.50, green: 0.46, blue: 0.60)  // #80769A
    static let voidDark = Color(red: 0.05, green: 0.03, blue: 0.08)   // #0D0814
    static let panelDark = Color(red: 0.09, green: 0.06, blue: 0.13)  // #170F21
    static let cardDark = Color(red: 0.12, green: 0.08, blue: 0.17)   // #1F142B
    static let popoverDark = Color(red: 0.10, green: 0.07, blue: 0.15) // #1A1126

    // Light mode palette — warm lavender paper
    static let inkLight = Color(red: 0.12, green: 0.08, blue: 0.18)   // #1F142E
    static let mutedLight = Color(red: 0.45, green: 0.40, blue: 0.52) // #736685
    static let voidLight = Color(red: 0.97, green: 0.96, blue: 0.98)  // #F8F5FB
    static let panelLight = Color(red: 1.0, green: 0.99, blue: 1.0)   // #FFFDFE
    static let cardLight = Color(red: 0.95, green: 0.93, blue: 0.97)  // #F2EDF7
    static let popoverLight = Color(red: 0.99, green: 0.98, blue: 1.0) // #FCFAFE
}

extension Color {
    // Accent (consistent across modes, slightly adjusted for contrast)
    static let hydraAccent = Color(light: HydraColors.accentLight, dark: HydraColors.accentLight)
    static let hydraGlow = Color(light: HydraColors.glow, dark: HydraColors.glow)
    static let hydraLive = Color(light: HydraColors.live, dark: HydraColors.live)
    static let hydraAlert = Color(light: HydraColors.alert, dark: Color(red: 1.0, green: 0.62, blue: 0.58))
    static let hydraPartial = Color(light: HydraColors.partial, dark: Color(red: 0.90, green: 0.75, blue: 0.34))

    // Adaptive text/surface colors
    static let hydraInk = Color(light: HydraColors.inkLight, dark: HydraColors.inkDark)
    static let hydraMuted = Color(light: HydraColors.mutedLight, dark: HydraColors.mutedDark)
    static let hydraVoid = Color(light: HydraColors.voidLight, dark: HydraColors.voidDark)
    static let hydraPanel = Color(light: HydraColors.panelLight, dark: HydraColors.panelDark)
    static let hydraCard = Color(light: HydraColors.cardLight, dark: HydraColors.cardDark)
    static let hydraPopover = Color(light: HydraColors.popoverLight, dark: HydraColors.popoverDark)

    // Utility (accent-tinted, adaptive opacity)
    static var hydraLine: Color { hydraAccent.opacity(0.15) }
    static var hydraSelection: Color { hydraAccent.opacity(0.14) }
    static var hydraHover: Color { hydraAccent.opacity(0.07) }
}

// MARK: - Color init helper (light/dark bundles)

extension Color {
    init(light: Color, dark: Color) {
        #if os(macOS)
        self = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil {
                return NSColor(dark)
            }
            return NSColor(light)
        }.mapToColor()
        #else
        self = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        }.mapToColor()
        #endif
    }
}

#if os(macOS)
extension NSColor {
    func mapToColor() -> Color { Color(nsColor: self) }
}
#else
extension UIColor {
    func mapToColor() -> Color { Color(uiColor: self) }
}
#endif

// MARK: - Theme

enum HydraTheme {
    static let cornerRadius: CGFloat = 14
    static let smallCornerRadius: CGFloat = 8

    static func mono(_ style: Font.TextStyle = .callout, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }

    static func display(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .serif)
    }
}

// MARK: - Panel Container (adaptive)

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

// MARK: - Glow Button (adaptive)

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
            .foregroundStyle(.white)
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

// MARK: - Status Dot (adaptive)

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

// MARK: - Tag Chip (adaptive)

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

// MARK: - Stat Card (adaptive)

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
