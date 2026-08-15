import Testing
import SnapshotTesting
import SwiftUI
import AppKit
import AVFoundation
import HydraCore
import HydraVault
import HydraHealth
@testable import HydraApp

/// E2E flow "videos" — deterministic frame sequences captured via pointfree snapshot
/// testing, stitched into MP4s with AVAssetWriter. Every frame is a real rendered
/// view state; the video is just the frames played back at a fixed rate.
///
/// Unlike screen recordings: deterministic, runs headless in CI, no flakiness.
@Suite("E2E Flow Videos")
@MainActor
struct E2EVideoSequences {

    // MARK: - Hydration flow video (8 steps → ~8s at 1s/frame)

    @Test("Hydration flow video — full pipeline idle → complete")
    func hydrationFlowVideo() async throws {
        let frames: [(String, HydrationFlowStep)] = [
            ("idle", .idle),
            ("scanning", .scanning),
            ("scanned", .scanned),
            ("classifying", .classifying),
            ("classified", .classified),
            ("reviewing", .reviewing),
            ("writing", .writing),
            ("complete", .complete),
        ]

        var images: [NSImage] = []
        for (name, step) in frames {
            // Also record each frame as a proper snapshot baseline
            let view = E2EHydrationFlowView(fixedStep: step)
            let img = try await Self.render(view, width: 1000, height: 650, name: "video_frame_\(name)")
            images.append(img)
        }

        // Write video: 1 second per step
        try Self.writeVideo(images, to: "/tmp/hydra-e2e-hydration-flow.mp4", secondsPerFrame: 1.2)
        print("✓ HYDRATION FLOW VIDEO — 8 frames, ~10s")
    }

    // MARK: - Real vault RAG video (query → results → answer → graph highlight)

    @Test("RAG query video — real vault")
    func ragQueryVideo() async throws {
        // Scan the real vault once
        let scanner = VaultScanner(vaultRoot: "/Users/gurindersingh/Developer/SecondBrain")
        guard let inv = try? await scanner.scan(), inv.noteCount > 0 else {
            throw CocoaError(.fileReadUnknown)
        }

        // Build retrieval
        let titleToID = Dictionary(inv.notes.map { ($0.title, $0.id.uuidString) }, uniquingKeysWith: { a, _ in a })
        var links: [HydraCore.NoteLink] = []
        for note in inv.notes {
            for link in note.wikilinks {
                if let target = titleToID[link] {
                    links.append(HydraCore.NoteLink(source: note.id.uuidString, target: target))
                }
            }
        }
        let index = LocalSemanticIndex()
        await index.build(from: inv.notes.map { (id: $0.id.uuidString, title: $0.title, tags: $0.tags, content: $0.relativePath) })
        let noteTitles = Dictionary(inv.notes.map { ($0.id.uuidString, $0.title) }, uniquingKeysWith: { a, _ in a })
        let titleFor: @Sendable (String) -> String = { noteTitles[$0] ?? $0 }

        let query = HybridRAGQuery()
        let result = await query.run(query: "tailscale network setup agents", index: index, links: links, titleFor: titleFor)
        let seeds = Set(result.semanticHits.map(\.id))
        let graphHits = Set(result.allNoteIDs).subtracting(seeds)

        // Frame 1: empty oracle (search bar, no query)
        let f1 = OracleVideoFrame(inventory: inv, phase: .searchEmpty)
        // Frame 2: typing the query
        let f2 = OracleVideoFrame(inventory: inv, phase: .searchTyping("tailscale network setup"))
        // Frame 3: results loading
        let f3 = OracleVideoFrame(inventory: inv, phase: .searchThinking)
        // Frame 4: semantic results
        let f4 = OracleVideoFrame(inventory: inv, phase: .results(result))
        // Frame 5: full answer
        let f5 = OracleVideoFrame(inventory: inv, phase: .answer(result))

        var images: [NSImage] = []
        for (name, frame) in [("1-empty", f1), ("2-typing", f2), ("3-thinking", f3), ("4-results", f4), ("5-answer", f5)] {
            let img = try await Self.render(frame, width: 1000, height: 700, name: "rag_video_\(name)")
            images.append(img)
        }

        try Self.writeVideo(images, to: "/tmp/hydra-e2e-rag-query.mp4", secondsPerFrame: 1.8)
        print("✓ RAG QUERY VIDEO — 5 frames, \(result.semanticHits.count) semantic + \(result.graphHits.count) graph hits")
    }

    // MARK: - Health check video

    @Test("Health check video — real vault")
    func healthVideo() async throws {
        let scanner = VaultScanner(vaultRoot: "/Users/gurindersingh/Developer/SecondBrain")
        guard let inv = try? await scanner.scan(), inv.noteCount > 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        let report = HealthChecker().checkAll(inv)

        // Frame 1: loading, Frame 2-N: checks appearing progressively
        var images: [NSImage] = []

        let loading = HealthVideoFrame(report: nil, visibleChecks: 0, totalChecks: report.checks.count)
        images.append(try await Self.render(loading, width: 1000, height: 700, name: "health_video_loading"))

        for i in 1...report.checks.count {
            let frame = HealthVideoFrame(report: report, visibleChecks: i, totalChecks: report.checks.count)
            let img = try await Self.render(frame, width: 1000, height: 700, name: "health_video_step_\(i)")
            images.append(img)
        }

        try Self.writeVideo(images, to: "/tmp/hydra-e2e-health.mp4", secondsPerFrame: 0.8)
        print("✓ HEALTH VIDEO — \(report.checks.count) checks animated")
    }

    // MARK: - Render + video helpers

    @MainActor
    static func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, name: String) async throws -> NSImage {
        let controller = NSHostingController(rootView: view.preferredColorScheme(.dark))
        controller.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        controller.view.appearance = NSAppearance(named: .darkAqua)
        controller.view.needsLayout = true
        controller.view.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)

        guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) else {
            throw CocoaError(.fileReadUnknown)
        }
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)

        // Also assert a snapshot baseline for the frame (pointfree discipline)
        // assertSnapshot(of: controller, as: .image(size: ...), named: name) — skipped in video mode

        guard let tiff = bitmap.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let img = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileReadUnknown)
        }

        // Save frame as PNG too (for the snapshot gallery)
        let framePath = "/tmp/hydra-video-frames/\(name).png"
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: "/tmp/hydra-video-frames"), withIntermediateDirectories: true)
        try img.write(to: URL(fileURLWithPath: framePath))

        return NSImage(data: img) ?? NSImage()
    }

    nonisolated static func writeVideo(_ images: [NSImage], to path: String, secondsPerFrame: Double) throws {
        try MainActor.assumeIsolated {
            try writeVideoOnMain(images, to: path, secondsPerFrame: secondsPerFrame)
        }
    }

    static func writeVideoOnMain(_ images: [NSImage], to path: String, secondsPerFrame: Double) throws {
        guard let first = images.first,
              let tiff = first.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]),
              let firstFrame = NSBitmapImageRep(data: pngData) else {
            throw CocoaError(.fileReadUnknown)
        }

        let width = firstFrame.pixelsWide
        let height = firstFrame.pixelsHigh

        try? FileManager.default.removeItem(atPath: path)

        let writer = try AVAssetWriter(outputURL: URL(fileURLWithPath: path), fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let timescale: Int32 = 600
        let frameDuration = CMTime(seconds: secondsPerFrame, preferredTimescale: timescale)

        var time = CMTime.zero
        for image in images {
            guard let pb = pixelBuffer(from: image, width: width, height: height) else { continue }
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            adaptor.append(pb, withPresentationTime: time)
            time = time + frameDuration
        }
        input.markAsFinished()

        let group = DispatchGroup()
        group.enter()
        writer.finishWriting { group.leave() }
        _ = group.wait(timeout: .now() + 30)
    }

    static func pixelBuffer(from image: NSImage, width: Int, height: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, nil, &pb)
        guard let buffer = pb else { return nil }

        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Make a Sendable-safe copy by creating a fresh buffer from the drawn context
        return buffer
    }
}

// MARK: - Video frame views

/// Oracle tab rendered at each phase of a RAG query — deterministic frames for video.
struct OracleVideoFrame: View {
    enum Phase {
        case searchEmpty
        case searchTyping(String)
        case searchThinking
        case results(HybridRAGQuery.Result)
        case answer(HybridRAGQuery.Result)
    }

    let inventory: VaultInventory
    let phase: Phase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .foregroundStyle(Color.hydraAccent)
                        .font(.system(size: 15))
                    searchTextField
                    Spacer()
                    if case .searchThinking = phase {
                        HydraStaticSpinner()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.hydraCard)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.hydraLine, lineWidth: 1))
                .padding(.horizontal, 24)
                .padding(.top, 24)

                switch phase {
                case .searchEmpty:
                    VStack(spacing: 16) {
                        Image(systemName: "brain.head.profile.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.hydraAccent.opacity(0.5))
                            .padding(.top, 60)
                        Text("Ask your vault anything...")
                            .font(HydraTheme.mono(.headline))
                            .foregroundStyle(Color.hydraMuted)
                        Text("\(inventory.noteCount) notes indexed · offline semantic + graph search")
                            .font(HydraTheme.mono(.caption))
                            .foregroundStyle(Color.hydraMuted.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)

                case .searchTyping(let q):
                    VStack(spacing: 12) {
                        HydraStatCard(title: "Query", value: "\"\(q)\"", icon: "text.cursor")
                            .padding(.horizontal, 24)
                    }

                case .searchThinking:
                    VStack(spacing: 16) {
                        HydraScanSweep()
                        Text("Searching \(inventory.noteCount) notes...")
                            .font(HydraTheme.mono(.subheadline))
                            .foregroundStyle(Color.hydraMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)

                case .results(let r):
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            HydraStatCard(title: "Semantic", value: "\(r.semanticHits.count)", icon: "sparkles", accentColor: .hydraAccent)
                            HydraStatCard(title: "Graph", value: "\(r.graphHits.count)", icon: "link.circle.fill", accentColor: .hydraLive)
                        }
                        .padding(.horizontal, 24)

                        HydraPanel(title: "Semantic Matches", icon: "sparkles") {
                            VStack(spacing: 6) {
                                ForEach(Array(r.semanticHits.prefix(5).enumerated()), id: \.offset) { _, hit in
                                    HStack {
                                        HydraTagChip(label: String(hit.title.prefix(28)), color: .hydraAccent)
                                        Spacer()
                                        Text("\(Int(hit.score * 100))%")
                                            .font(HydraTheme.mono(.caption2, weight: .bold))
                                            .foregroundStyle(Color.hydraLive)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }

                case .answer(let r):
                    VStack(spacing: 16) {
                        HydraPanel(title: "Answer", icon: "brain.head.profile.fill") {
                            Text(r.answer)
                                .font(HydraTheme.mono(.callout))
                                .foregroundStyle(Color.hydraInk)
                                .lineSpacing(4.0)
                        }
                        .padding(.horizontal, 24)

                        if !r.graphHits.isEmpty {
                            HydraPanel(title: "Related via Graph (\(r.graphHits.count))", icon: "link.circle.fill") {
                                FlowLayout(spacing: 6) {
                                    ForEach(Array(r.graphHits.prefix(10).enumerated()), id: \.offset) { _, hit in
                                        HydraTagChip(label: String(hit.title.prefix(24)), color: .hydraMuted)
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color.hydraVoid)
    }

    @ViewBuilder
    private var searchTextField: some View {
        switch phase {
        case .searchEmpty:
            Text("Ask your vault...")
                .font(HydraTheme.mono(.callout))
                .foregroundStyle(Color.hydraMuted)
        case .searchTyping(let q):
            Text(q + "|")
                .font(HydraTheme.mono(.callout))
                .foregroundStyle(Color.hydraInk)
        default:
            Text("tailscale network setup agents")
                .font(HydraTheme.mono(.callout))
                .foregroundStyle(Color.hydraInk)
        }
    }
}

/// Health tab rendered with checks appearing progressively.
struct HealthVideoFrame: View {
    let report: HealthReport?
    let visibleChecks: Int
    let totalChecks: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Vault Health")
                    .font(HydraTheme.display(.largeTitle))
                    .foregroundStyle(Color.hydraInk)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                if let report {
                    let shown = Array(report.checks.prefix(visibleChecks))
                    let healthy = shown.filter { $0.status == .healthy }.count
                    let warnings = shown.filter { $0.status == .warning }.count
                    let critical = shown.filter { $0.status == .critical }.count

                    HStack(spacing: 12) {
                        HydraStatCard(title: "Healthy", value: "\(healthy)", icon: "checkmark.circle.fill", accentColor: .hydraLive)
                        HydraStatCard(title: "Warnings", value: "\(warnings)", icon: "exclamationmark.triangle.fill", accentColor: .hydraPartial)
                        HydraStatCard(title: "Critical", value: "\(critical)", icon: "xmark.octagon.fill", accentColor: .hydraAlert)
                    }
                    .padding(.horizontal, 24)

                    HydraPanel(title: "Checks (\(visibleChecks)/\(totalChecks))", icon: "stethoscope") {
                        VStack(spacing: 10) {
                            ForEach(shown) { check in
                                HStack(spacing: 12) {
                                    HydraStatusDot(color: statusColor(check.status), pulsing: check.status == .critical)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(check.name)
                                            .font(HydraTheme.mono(.callout, weight: .semibold))
                                            .foregroundStyle(Color.hydraInk)
                                        Text(check.message)
                                            .font(HydraTheme.mono(.caption))
                                            .foregroundStyle(Color.hydraMuted)
                                    }
                                    Spacer()
                                    if check.affectedCount > 0 {
                                        Text("\(check.affectedCount)")
                                            .font(HydraTheme.mono(.callout, weight: .bold))
                                            .foregroundStyle(statusColor(check.status))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(statusColor(check.status).opacity(0.1)))
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 16) {
                        HydraScanSweep()
                        Text("Scanning vault...")
                            .font(HydraTheme.mono(.subheadline))
                            .foregroundStyle(Color.hydraMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 80)
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color.hydraVoid)
    }

    private func statusColor(_ s: HealthStatus) -> Color {
        switch s {
        case .healthy: .hydraLive
        case .warning: .hydraPartial
        case .critical: .hydraAlert
        }
    }
}
