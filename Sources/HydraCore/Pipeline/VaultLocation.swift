import Foundation

// MARK: - Vault Location

/// Abstract vault location resolver.
/// Handles local, iCloud, and network paths (Tailscale/SSH) uniformly.
/// This is what makes Hydra work on any device — iPhone, Mac, VM —
/// pointing at vaults that might be local, in iCloud, or on a remote host.
public struct VaultLocation: Sendable, Equatable {
    public let kind: VaultLocationKind
    public let rawPath: String
    public let displayName: String

    public init(kind: VaultLocationKind, rawPath: String, displayName: String) {
        self.kind = kind
        self.rawPath = rawPath
        self.displayName = displayName
    }

    /// Resolve to a concrete filesystem path.
    /// On iOS, iCloud paths resolve through the app's container.
    /// On macOS, paths resolve directly.
    /// Network paths resolve through Tailscale/SSH tunneling.
    public func resolve() -> String {
        switch kind {
        case .local:
            return rawPath.expandingTildeInPath

        case .iCloud:
            // On macOS: ~/Library/Mobile Documents/iCloud~md~obsidian/Documents/<vault>
            // On iOS: resolved through FileProvider — the rawPath is relative to the iCloud container
            #if os(macOS)
            return rawPath.expandingTildeInPath
            #else
            // iOS: the caller should use the Documents directory or a file provider URL
            return rawPath
            #endif

        case .tailscale(let host):
            // Network path via Tailscale — needs a transport layer
            // For now, return the path as-is; the transport handles resolution
            return rawPath

        case .ssh(let host):
            return rawPath
        }
    }

    /// Whether this location requires network access.
    public var requiresNetwork: Bool {
        switch kind {
        case .local, .iCloud: false
        case .tailscale, .ssh: true
        }
    }
}

// MARK: - Vault Location Kind

public enum VaultLocationKind: Sendable, Equatable {
    case local
    case iCloud
    case tailscale(host: String)   // e.g. "studio.local" or "100.x.x.x"
    case ssh(host: String)
}

// MARK: - Convenience constructors

public extension VaultLocation {
    /// Local vault at a filesystem path.
    static func local(_ path: String, name: String? = nil) -> VaultLocation {
        let display = name ?? (path as NSString).lastPathComponent
        return VaultLocation(kind: .local, rawPath: path, displayName: display)
    }

    /// iCloud vault (Obsidian iCloud sync).
    static func iCloud(vaultName: String) -> VaultLocation {
        VaultLocation(
            kind: .iCloud,
            rawPath: "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/\(vaultName)",
            displayName: "iCloud: \(vaultName)"
        )
    }

    /// Tailscale-connected remote vault.
    static func tailscale(host: String, path: String) -> VaultLocation {
        VaultLocation(
            kind: .tailscale(host: host),
            rawPath: path,
            displayName: "\(host):\(path)"
        )
    }
}

// MARK: - Source Location

/// A source location — where hydration data comes from.
/// Can be local (Claude plans, Codex sessions), iCloud, or remote (VM paths over Tailscale).
public struct SourceLocation: Sendable, Equatable {
    public let kind: SourceKind
    public let vaultLocation: VaultLocation
    public let subpath: String?

    public init(kind: SourceKind, vaultLocation: VaultLocation, subpath: String? = nil) {
        self.kind = kind
        self.vaultLocation = vaultLocation
        self.subpath = subpath
    }

    /// Resolve the full path to scan.
    public func resolvePath() -> String {
        let base = vaultLocation.resolve()
        if let subpath {
            return (base as NSString).appendingPathComponent(subpath)
        }
        return base
    }

    /// Convenience: local Claude plans source.
    static func claudePlans(at location: VaultLocation) -> SourceLocation {
        SourceLocation(kind: .claudePlans, vaultLocation: location, subpath: ".claude/plans")
    }

    /// Convenience: local changelog source.
    static func changelog(at location: VaultLocation, file: String = "CHANGELOG.md") -> SourceLocation {
        SourceLocation(kind: .changelog, vaultLocation: location, subpath: file)
    }

    /// Convenience: remote source over Tailscale (e.g., VM paths).
    static func remote(kind: SourceKind, host: String, path: String, subpath: String? = nil) -> SourceLocation {
        let loc = VaultLocation.tailscale(host: host, path: path)
        return SourceLocation(kind: kind, vaultLocation: loc, subpath: subpath)
    }
}

// MARK: - Path helpers

extension String {
    /// Expand ~ to home directory.
    var expandingTildeInPath: String {
        guard hasPrefix("~") else { return self }
        let home: String
        #if os(macOS)
        home = PlatformPaths.home
        #else
        // iOS: sandbox container; ~ resolves to the app's Documents home
        home = NSHomeDirectory()
        #endif
        return home + dropFirst()
    }

    /// Whether this path is a Tailscale address.
    var isTailscaleAddress: Bool {
        hasPrefix("100.") || contains(".ts.net") || contains(".ts.local")
    }
}
