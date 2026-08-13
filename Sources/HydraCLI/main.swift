import Foundation
import ArgumentParser
import HydraCore
import HydraVault
import HydraHealth
import HydraMCP

// MARK: - Brain Oracle CLI

@main
struct BrainOracleCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hydra",
        abstract: "Context Hydration Engine — sources → enrich → vault → export. 100% Swift.",
        subcommands: [Scan.self, Health.self, Hydrate.self, Search.self, Serve.self]
    )
}

// MARK: - scan

extension BrainOracleCLI {
    struct Scan: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Scan an Obsidian vault and print inventory stats."
        )

        @Option(help: "Path to vault root")
        var vault: String

        @Flag(help: "Show all notes (not just summary)")
        var verbose = false

        func run() async throws {
            let scanner = VaultScanner(vaultRoot: vault)
            let inventory = try await scanner.scan()

            print("Vault: \(vault)")
            print("Notes: \(inventory.noteCount)")
            print("Tags: \(inventory.tagFrequency.count) unique")

            let paraBreakdown: [(PARACategory, Int)] = PARACategory.allCases.compactMap { cat in
                let count = inventory.notes(in: cat).count
                return count > 0 ? (cat, count) : nil
            }
            print("\nPARA Breakdown:")
            for (cat, count) in paraBreakdown.sorted(by: { $0.1 > $1.1 }) {
                let label = cat.rawValue.isEmpty ? "other" : cat.rawValue
                print("  \(label.padding(toLength: 30, withPad: " ", startingAt: 0)) \(count)")
            }

            print("\nOrphaned: \(inventory.orphanedNotes.count)")
            print("Broken wikilinks: \(inventory.brokenWikilinks.count)")
            print("Missing frontmatter: \(inventory.notesMissingFrontmatter.count)")

            if verbose {
                print("\n--- Top Tags ---")
                for (tag, count) in inventory.tagFrequency.prefix(20) {
                    print("  \(tag.padding(toLength: 30, withPad: " ", startingAt: 0)) \(count)")
                }
            }
        }
    }
}

// MARK: - health

extension BrainOracleCLI {
    struct Health: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run vault health checks."
        )

        @Option(help: "Path to vault root")
        var vault: String

        func run() async throws {
            let scanner = VaultScanner(vaultRoot: vault)
            let inventory = try await scanner.scan()
            let checker = HealthChecker()
            let report = checker.checkAll(inventory)

            print("Vault Health: \(vault)")
            print("Overall: \(report.overallStatus.rawValue.uppercased())")
            print("Summary: \(report.summary)\n")

            for check in report.checks {
                let icon: String
                switch check.status {
                case .healthy:  icon = "✅"
                case .warning:  icon = "⚠️ "
                case .critical: icon = "🔴"
                }
                print("\(icon) \(check.name.padding(toLength: 25, withPad: " ", startingAt: 0)) \(check.message)")
            }
        }
    }
}

// MARK: - hydrate

extension BrainOracleCLI {
    struct Hydrate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run a context hydration pass from sources into the vault."
        )

        @Option(help: "Path to vault root")
        var vault: String

        @Option(help: "Source path to scan (e.g. ~/.claude/plans/)")
        var source: String

        @Flag(help: "Dry run — classify and report without writing")
        var dryRun = false

        func run() async throws {
            print("Hydration (dry run: \(dryRun))")
            print("Source: \(source)")
            print("Vault:  \(vault)")
            print("\n[Pipeline not yet wired — HydraCore classifier in progress]")
        }
    }
}

// MARK: - search

extension BrainOracleCLI {
    struct Search: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Search vault notes by text or tag."
        )

        @Option(help: "Path to vault root")
        var vault: String

        @Option(help: "Search query")
        var query: String

        @Option(help: "Filter by tag")
        var tag: String?

        @Option(help: "Max results")
        var limit: Int = 20

        func run() async throws {
            let scanner = VaultScanner(vaultRoot: vault)
            let inventory = try await scanner.scan()

            var results = inventory.notes.filter { note in
                note.title.localizedCaseInsensitiveContains(query)
                || note.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            }

            if let tag {
                results = results.filter { note in
                    note.tags.contains { $0.localizedCaseInsensitiveContains(tag) }
                }
            }

            print("Found \(results.count) notes\n")

            for note in results.prefix(limit) {
                let tags = note.tags.isEmpty ? "" : " [\(note.tags.joined(separator: ", "))]"
                print("  \(note.title)\(tags)")
                print("    \(note.relativePath)\n")
            }
        }
    }
}

// MARK: - serve (MCP)

extension BrainOracleCLI {
    struct Serve: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Start the MCP server (Claude stdio transport)."
        )

        @Option(help: "Path to vault root")
        var vault: String

        func run() async throws {
            let server = HydraMCPServer(vaultRoot: vault)
            await server.run()
        }
    }
}
