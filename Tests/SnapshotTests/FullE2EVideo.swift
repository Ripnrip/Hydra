import Testing
import SwiftUI
import AppKit
import AVFoundation
import HydraCore
import HydraVault
import HydraHealth
@testable import HydraApp

@Suite("Full E2E Video — Real Vault")
@MainActor
struct FullE2EVideoTest {
    @Test("Complete flow: scan → health → RAG → highlighted graph")
    func fullE2E() async throws {
        let vaultPath = "/Users/gurindersingh/Developer/SecondBrain"
        let scanner = VaultScanner(vaultRoot: vaultPath)
        guard let inv = try? await scanner.scan(), inv.noteCount > 0 else { throw CocoaError(.fileReadUnknown) }
        let report = HealthChecker().checkAll(inv)

        let titleToID = Dictionary(inv.notes.map { ($0.title, $0.id.uuidString) }, uniquingKeysWith: { a, _ in a })
        var links: [HydraCore.NoteLink] = []
        for note in inv.notes {
            for link in note.wikilinks {
                if let t = titleToID[link] { links.append(HydraCore.NoteLink(source: note.id.uuidString, target: t)) }
            }
        }
        let index = LocalSemanticIndex()
        await index.build(from: inv.notes.map { (id: $0.id.uuidString, title: $0.title, tags: $0.tags, content: $0.relativePath) })
        let titles = Dictionary(inv.notes.map { ($0.id.uuidString, $0.title) }, uniquingKeysWith: { a, _ in a })
        let titleFor: @Sendable (String) -> String = { titles[$0] ?? $0 }
        let result = await HybridRAGQuery().run(query: "memory knowledge graph", index: index, links: links, titleFor: titleFor)

        @MainActor
        func snap<V: View>(_ v: V) async throws -> NSImage {
            let c = NSHostingController(rootView: v.preferredColorScheme(.dark))
            c.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
            c.view.appearance = NSAppearance(named: .darkAqua)
            c.view.needsLayout = true
            c.view.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 300_000_000)
            guard let b = c.view.bitmapImageRepForCachingDisplay(in: c.view.bounds) else { throw CocoaError(.fileReadUnknown) }
            c.view.cacheDisplay(in: c.view.bounds, to: b)
            guard let tiff = b.tiffRepresentation, let img = NSImage(data: tiff) else { throw CocoaError(.fileReadUnknown) }
            return img
        }

        var images: [NSImage] = []
        images.append(try await snap(ScanSummaryView(inv: inv)))
        images.append(try await snap(HealthViewWithData(report: report)))
        images.append(try await snap(RealRAGPanel(question: "memory knowledge graph", result: result)))

        let seeds = Set(result.semanticHits.map(\.id))
        let g = Set(result.allNoteIDs).subtracting(seeds)
        images.append(try await snap(
            VaultGraphView(inventory: inv, highlightedSemanticIDs: seeds, highlightedGraphIDs: g)
                .frame(width: 1000, height: 700)
        ))

        try Self.writeVideo(images, to: "/tmp/hydra-full-e2e.mp4", secondsPerFrame: 3.0)
        print("✓ FULL E2E VIDEO — scan → health → RAG → graph, \(inv.noteCount) notes")
    }

    @MainActor static func writeVideo(_ images: [NSImage], to path: String, secondsPerFrame: Double) throws {
        try? FileManager.default.removeItem(atPath: path)
        let writer = try AVAssetWriter(outputURL: URL(fileURLWithPath: path), fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1000, AVVideoHeightKey: 700
        ])
        let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB
        ])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)

        var t = CMTime.zero
        for img in images {
            guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 1000, 700, kCVPixelFormatType_32ARGB, nil, &pb)
            if let buffer = pb {
                CVPixelBufferLockBaseAddress(buffer, [])
                if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 1000, height: 700,
                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
                    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1000, height: 700))
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                while !input.isReadyForMoreMediaData { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
                ad.append(buffer, withPresentationTime: t)
                t = t + CMTime(seconds: secondsPerFrame, preferredTimescale: 600)
            }
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        _ = sem.wait(timeout: .now() + 30)
    }
}

/// Scan summary view for the video frame.
struct ScanSummaryView: View {
    let inv: VaultInventory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Vault Scan — SecondBrain")
                    .font(HydraTheme.display(.largeTitle))
                    .foregroundStyle(Color.hydraInk)
                    .padding(.horizontal, 24).padding(.top, 24)

                HStack(spacing: 12) {
                    HydraStatCard(title: "Notes", value: "\(inv.noteCount)", icon: "doc.text.fill")
                    HydraStatCard(title: "Tags", value: "\(inv.tagFrequency.count)", icon: "tag.fill", accentColor: .hydraLive)
                    HydraStatCard(title: "Orphans", value: "\(inv.orphanedNotes.count)", icon: "questionmark.circle.fill", accentColor: .hydraAlert)
                    HydraStatCard(title: "Broken", value: "\(inv.brokenWikilinks.count)", icon: "link.badge.plus", accentColor: .hydraPartial)
                }
                .padding(.horizontal, 24)

                HydraPanel(title: "PARA Structure", icon: "folder.fill") {
                    VStack(spacing: 6) {
                        let para = Dictionary(grouping: inv.notes, by: \.paraCategory)
                            .map { (cat: $0.key, count: $0.value.count) }
                            .sorted { $0.count > $1.count }
                        ForEach(para, id: \.cat) { item in
                            HStack {
                                HydraTagChip(label: item.cat.rawValue, color: .hydraAccent)
                                Spacer()
                                Text("\(item.count) notes")
                                    .font(HydraTheme.mono(.caption))
                                    .foregroundStyle(Color.hydraMuted)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 32)
        }
        .background(Color.hydraVoid)
    }
}
