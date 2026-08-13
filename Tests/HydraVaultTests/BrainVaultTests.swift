import Testing
import Foundation
@testable import HydraVault

@Test func frontmatterParsing() {
    let content = "---\ntitle: Test\ntags: swift, testing\n---\n# Body"
    let (fm, body) = VaultScanner.parseFrontmatter(content)
    #expect(fm["title"] == "Test")
    #expect(fm["tags"] == "swift, testing")
    #expect(body.hasPrefix("# Body"))
}

@Test func tagExtraction() {
    let tags = VaultScanner.extractTags(from: [:], body: "This has #swift and #testing tags plus #project/ai-config")
    #expect(tags.contains("swift"))
    #expect(tags.contains("testing"))
    #expect(tags.contains("project/ai-config"))
}

@Test func wikilinkExtraction() {
    let links = VaultScanner.extractWikilinks(from: "See [[Andromeda]] and [[BrainOracle|the tool]]")
    #expect(links.contains("Andromeda"))
    #expect(links.contains("BrainOracle"))
    #expect(links.count == 2)
}

@Test func sha256Deterministic() {
    let hash1 = VaultScanner.sha256("test content")
    let hash2 = VaultScanner.sha256("test content")
    #expect(hash1 == hash2)
    #expect(hash1.count == 64)
}

@Test func paraCategoryResolution() {
    #expect(PARACategory.resolve(from: "07-Sessions/test.md") == .session)
    #expect(PARACategory.resolve(from: "01-Permanent/Projects/x.md") == .project)
    #expect(PARACategory.resolve(from: "random/file.md") == .other)
}

@Test func paraCategoryColorFamilies() {
    #expect(PARACategory.project.colorFamily == .projectWarm)
    #expect(PARACategory.session.colorFamily == .statusGreen)
}
