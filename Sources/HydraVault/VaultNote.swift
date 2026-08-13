import Foundation
import HydraCore

// MARK: - Vault Note

/// A parsed markdown note from an Obsidian vault.
/// This is what the scanner produces and what the writer targets.
public struct VaultNote: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var relativePath: String       // relative to vault root
    public var title: String
    public var frontmatter: [String: String]
    public var tags: [String]
    public var wikilinks: [String]        // [[note name]] targets
    public var paraCategory: PARACategory
    public var modifiedDate: Date
    public var size: Int                  // bytes
    public var digest: String             // SHA-256 hex
    public var hasFrontmatter: Bool
    public var orphaned: Bool             // no incoming wikilinks from other notes

    public init(
        id: UUID = UUID(),
        relativePath: String,
        title: String,
        frontmatter: [String: String] = [:],
        tags: [String] = [],
        wikilinks: [String] = [],
        paraCategory: PARACategory = .other,
        modifiedDate: Date = .distantPast,
        size: Int = 0,
        digest: String = "",
        hasFrontmatter: Bool = false,
        orphaned: Bool = false
    ) {
        self.id = id
        self.relativePath = relativePath
        self.title = title
        self.frontmatter = frontmatter
        self.tags = tags
        self.wikilinks = wikilinks
        self.paraCategory = paraCategory
        self.modifiedDate = modifiedDate
        self.size = size
        self.digest = digest
        self.hasFrontmatter = hasFrontmatter
        self.orphaned = orphaned
    }
}

// MARK: - PARA Category

/// Maps vault directory structure to PARA categories.
/// Derived from the SecondBrain vault layout:
/// 00-Inbox, 01-Permanent/{Projects, Areas, Resources, Archives, Concepts, Systems},
/// 02-Daily, 03-Templates, 04-Assets, 05-Maps of Content, 06-Journal, 07-Sessions
public enum PARACategory: String, Sendable, CaseIterable, Equatable {
    case inbox       = "00-Inbox"
    case project     = "01-Permanent/Projects"
    case area        = "01-Permanent/Areas"
    case resource    = "01-Permanent/Resources"
    case archive     = "01-Permanent/Archives"
    case concept     = "01-Permanent/Concepts"
    case system      = "01-Permanent/Systems"
    case daily       = "02-Daily"
    case template    = "03-Templates"
    case asset       = "04-Assets"
    case moc         = "05-Maps of Content"
    case journal     = "06-Journal"
    case session     = "07-Sessions"
    case other       = ""

    /// Resolve a vault-relative path to a PARA category.
    public static func resolve(from relativePath: String) -> PARACategory {
        for category in allCases where category != .other {
            if relativePath.hasPrefix(category.rawValue) {
                return category
            }
        }
        return .other
    }

    /// Color family for graph visualization.
    public var colorFamily: VaultColor {
        switch self {
        case .project:  return .projectWarm
        case .area:     return .typeCool
        case .resource: return .typeCool
        case .archive:  return .severityInfo
        case .concept:  return .integrationPurple
        case .system:   return .integrationPurple
        case .session:  return .statusGreen
        case .journal:  return .statusYellow
        case .daily:    return .statusYellow
        case .moc:      return .projectWarm
        case .inbox:    return .severityCritical
        case .template: return .severityInfo
        case .asset:    return .severityInfo
        case .other:    return .severityInfo
        }
    }
}
