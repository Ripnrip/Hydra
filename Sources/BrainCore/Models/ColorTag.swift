import Foundation

// MARK: - Color Tag

/// Rich tag with color and axis classification for Obsidian graph visualization.
public struct ColorTag: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var axis: ColorAxis
    public var value: String          // e.g. "ai-config", "claude", "completed"
    public var color: VaultColor

    public init(
        id: UUID = UUID(),
        axis: ColorAxis,
        value: String,
        color: VaultColor
    ) {
        self.id = id
        self.axis = axis
        self.value = value
        self.color = color
    }

    /// Renders as an Obsidian graph color group query string.
    /// e.g. "tag:#project/ai-config"
    public var graphQuery: String {
        "tag:#\(axis.rawValue)/\(value)"
    }
}

// MARK: - Color Axis

/// Multi-axis tag taxonomy. Each axis maps to a color family in the Obsidian graph.
public enum ColorAxis: String, Sendable, CaseIterable, Equatable {
    case project      // warm tones (orange, amber, red)
    case type         // cool tones (blue, cyan, teal)
    case status       // semantic (green=done, yellow=active, red=blocked)
    case integration  // purple/magenta (claude, codex, hermes, etc.)
    case severity     // intensity scale (light=info, dark=critical)
}

// MARK: - Vault Color

/// RGB color for Obsidian graph groups and frontmatter metadata.
public struct VaultColor: Sendable, Equatable {
    public var r: Int    // 0-255
    public var g: Int    // 0-255
    public var b: Int    // 0-255
    public var a: Double // 0.0-1.0

    public init(r: Int, g: Int, b: Int, a: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Obsidian graph.json rgb value (single integer: r*65536 + g*256 + b)
    public var graphRGB: Int {
        r * 65536 + g * 256 + b
    }

    /// CSS hex string for Obsidian CSS snippets
    public var hex: String {
        String(format: "#%02X%02X%02X", r, g, b)
    }

    // Preset palette per axis
    public static let projectWarm     = VaultColor(r: 225, g: 120, b: 71)   // warm orange
    public static let typeCool        = VaultColor(r: 71, g: 155, b: 225)   // cool blue
    public static let statusGreen     = VaultColor(r: 80, g: 200, b: 120)   // semantic green
    public static let statusYellow    = VaultColor(r: 225, g: 200, b: 71)   // semantic yellow
    public static let statusRed       = VaultColor(r: 225, g: 80, b: 80)    // semantic red
    public static let integrationPurple = VaultColor(r: 160, g: 100, b: 225) // purple
    public static let severityInfo    = VaultColor(r: 180, g: 180, b: 180)  // light gray
    public static let severityCritical = VaultColor(r: 180, g: 40, b: 40)   // dark red
}
