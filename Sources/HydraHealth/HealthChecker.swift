import Foundation
import HydraCore
import HydraVault

// MARK: - Health Checker

/// Runs health checks against a vault inventory.
/// All checks are pure functions over VaultInventory — no bash, no shell, all Swift.
public struct HealthChecker: Sendable {

    public init() {}

    /// Run all health checks against the vault.
    public func checkAll(_ inventory: VaultInventory) -> HealthReport {
        var checks: [HealthCheck] = []

        checks.append(checkVaultStaleness(inventory))
        checks.append(checkMissingFrontmatter(inventory))
        checks.append(checkOrphanedNotes(inventory))
        checks.append(checkBrokenWikilinks(inventory))
        checks.append(checkTagConsistency(inventory))
        checks.append(checkInboxBacklog(inventory))
        checks.append(checkDigestIntegrity(inventory))

        return HealthReport(
            vaultRoot: inventory.vaultRoot,
            checks: checks
        )
    }

    // MARK: - Individual checks

    /// Vault staleness — latest modification date vs now.
    public func checkVaultStaleness(_ inventory: VaultInventory) -> HealthCheck {
        let latest = inventory.notes.map(\.modifiedDate).max() ?? .distantPast
        let daysSinceLatest = Date().timeIntervalSince(latest) / 86400

        let status: HealthStatus
        let severity: GapSeverity

        if daysSinceLatest > 14 {
            status = .critical
            severity = .warning
        } else if daysSinceLatest > 7 {
            status = .warning
            severity = .info
        } else {
            status = .healthy
            severity = .info
        }

        return HealthCheck(
            name: "Vault Staleness",
            status: status,
            message: "Latest entry was \(Int(daysSinceLatest)) days ago",
            affectedCount: daysSinceLatest > 7 ? 1 : 0,
            severity: severity
        )
    }

    /// Notes missing frontmatter entirely.
    public func checkMissingFrontmatter(_ inventory: VaultInventory) -> HealthCheck {
        let missing = inventory.notesMissingFrontmatter

        return HealthCheck(
            name: "Missing Frontmatter",
            status: missing.isEmpty ? .healthy : .warning,
            message: missing.isEmpty
                ? "All notes have frontmatter"
                : "\(missing.count) notes missing frontmatter",
            affectedCount: missing.count,
            severity: .warning
        )
    }

    /// Orphaned notes — no incoming wikilinks.
    public func checkOrphanedNotes(_ inventory: VaultInventory) -> HealthCheck {
        let orphans = inventory.orphanedNotes

        return HealthCheck(
            name: "Orphaned Notes",
            status: orphans.count > inventory.noteCount / 3 ? .warning : .healthy,
            message: "\(orphans.count) of \(inventory.noteCount) notes are orphaned (no incoming links)",
            affectedCount: orphans.count,
            severity: .info
        )
    }

    /// Broken wikilinks — [[links]] that don't resolve to any note.
    public func checkBrokenWikilinks(_ inventory: VaultInventory) -> HealthCheck {
        let broken = inventory.brokenWikilinks

        return HealthCheck(
            name: "Broken Wikilinks",
            status: broken.isEmpty ? .healthy : .warning,
            message: broken.isEmpty
                ? "All wikilinks resolve"
                : "\(broken.count) broken wikilinks: \(broken.prefix(5).joined(separator: ", "))\(broken.count > 5 ? "…" : "")",
            affectedCount: broken.count,
            severity: .warning
        )
    }

    /// Tag consistency — checks for likely-duplicate tags (case variations, separators).
    public func checkTagConsistency(_ inventory: VaultInventory) -> HealthCheck {
        let tagFreq = inventory.tagFrequency
        let normalizedTags = Dictionary(grouping: tagFreq) { (tag, _) -> String in
            tag.lowercased()
                .replacingOccurrences(of: "_", with: "-")
                .replacingOccurrences(of: " ", with: "-")
        }

        let duplicates = normalizedTags.filter { $0.value.count > 1 }

        return HealthCheck(
            name: "Tag Consistency",
            status: duplicates.isEmpty ? .healthy : .warning,
            message: duplicates.isEmpty
                ? "No duplicate tag variants detected"
                : "\(duplicates.count) tag groups have variants that should be merged",
            affectedCount: duplicates.count,
            severity: .info
        )
    }

    /// Inbox backlog — notes still in 00-Inbox that should be filed.
    public func checkInboxBacklog(_ inventory: VaultInventory) -> HealthCheck {
        let inboxCount = inventory.notes(in: .inbox).count

        return HealthCheck(
            name: "Inbox Backlog",
            status: inboxCount > 10 ? .warning : .healthy,
            message: "\(inboxCount) notes in inbox",
            affectedCount: inboxCount,
            severity: .info
        )
    }

    /// Digest integrity — notes where the stored digest doesn't match recomputed content.
    public func checkDigestIntegrity(_ inventory: VaultInventory) -> HealthCheck {
        // Placeholder — full implementation requires re-reading files to recompute digests.
        // For now, checks that all notes have non-empty digests.
        let emptyDigests = inventory.notes.filter { $0.digest.isEmpty }

        return HealthCheck(
            name: "Digest Integrity",
            status: emptyDigests.isEmpty ? .healthy : .critical,
            message: emptyDigests.isEmpty
                ? "All digests present"
                : "\(emptyDigests.count) notes missing digests",
            affectedCount: emptyDigests.count,
            severity: .critical
        )
    }
}
