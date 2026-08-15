import Foundation

/// Platform-safe home directory resolution.
/// macOS: the real user home. iOS: the app sandbox container.
public enum PlatformPaths {
    public static var home: String {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser.path
        #else
        NSHomeDirectory()
        #endif
    }

    /// Expands a ~-prefixed path for the current platform.
    public static func expand(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return home + path.dropFirst()
    }
}
