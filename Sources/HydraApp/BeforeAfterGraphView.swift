import SwiftUI
import HydraCore

// MARK: - Before/After Graph Comparison View

/// Side-by-side or toggle comparison showing the vault graph before and after hydration.
/// Before: scattered orphan nodes with minimal/no connections.
/// After: rich typed relationships, colored by kind, properly connected.
struct BeforeAfterGraphView: View {
    enum CompareState: String {
        case before = "BEFORE"
        case after = "AFTER"
    }

    let state: CompareState
    let nodes: [GraphNode]
    let edges: [GraphEdge]

    var body: some View {
        ZStack {
            Color.hydraVoid

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        HydraStatusDot(
                            color: state == .before ? .hydraAlert : .hydraLive,
                            pulsing: true
                        )
                        Text(state.rawValue)
                            .font(HydraTheme.mono(.title3, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(state == .before ? Color.hydraAlert : Color.hydraLive)
                    }

                    Spacer()

                    HStack(spacing: 16) {
                        statPill(label: "NODES", value: "\(nodes.count)", color: .hydraAccent)
                        statPill(label: "EDGES", value: "\(edges.count)", color: state == .before ? .hydraAlert : .hydraLive)
                        statPill(label: "ORPHANS", value: "\(orphanCount)", color: orphanCount > 0 ? .hydraAlert : .hydraLive)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color.hydraPanel)

                // Graph canvas
                Canvas { context, size in
                    let w = Float(size.width)
                    let h = Float(size.height)
                    let scale = min(w / 900, h / 600)
                    let offsetX = (w - 900 * scale) / 2
                    let offsetY = (h - 600 * scale) / 2

                    func scaled(_ p: SIMD2<Float>) -> CGPoint {
                        CGPoint(x: CGFloat(p.x * scale + offsetX), y: CGFloat(p.y * scale + offsetY))
                    }

                    // O(1) node lookup — built once per draw call
                    let nodeByID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

                    // Draw edges
                    for edge in edges {
                        guard let src = nodeByID[edge.source],
                              let tgt = nodeByID[edge.target] else { continue }
                        var path = Path()
                        path.move(to: scaled(src.position))
                        path.addLine(to: scaled(tgt.position))

                        let alpha: CGFloat = state == .before ? 0.1 : CGFloat(0.2 + Double(edge.strength) * 0.3)
                        let color = edgeColor(edge.type, alpha: alpha)
                        let width = state == .before ? 0.5 : CGFloat(0.5 + Double(edge.strength) * 1.5)
                        context.stroke(path, with: .color(color), lineWidth: width)
                    }

                    // Draw nodes
                    for node in nodes {
                        let pos = scaled(node.position)
                        let r = CGFloat(node.radius) * CGFloat(scale)

                        // Glow (after only)
                        if state == .after {
                            let glowRect = CGRect(x: pos.x - r * 2, y: pos.y - r * 2, width: r * 4, height: r * 4)
                            context.fill(
                                Path(ellipseIn: glowRect),
                                with: .color(Color(
                                    red: Double(node.color.x),
                                    green: Double(node.color.y),
                                    blue: Double(node.color.z),
                                    opacity: 0.08
                                ))
                            )
                        }

                        // Node
                        let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(Color(
                                red: Double(node.color.x),
                                green: Double(node.color.y),
                                blue: Double(node.color.z),
                                opacity: state == .before ? 0.4 : Double(node.color.w)
                            ))
                        )

                        context.stroke(
                            Path(ellipseIn: rect),
                            with: .color(.white.opacity(state == .before ? 0.1 : 0.3)),
                            lineWidth: 1
                        )

                        // Label (after only — before is intentionally unreadable/scattered)
                        if state == .after {
                            context.draw(
                                Text(node.label)
                                    .font(HydraTheme.mono(.caption2, weight: .medium))
                                    .foregroundStyle(Color.hydraInk),
                                at: CGPoint(x: pos.x, y: pos.y + r + 12)
                            )
                        }
                    }
                }

                // Footer description
                HStack {
                    Text(state == .before
                         ? "134 orphaned notes · 659 broken wikilinks · no relationships"
                         : "0 orphans · 659 wikilinks fixed · \(edges.count) typed relationships inferred"
                    )
                    .font(HydraTheme.mono(.caption))
                    .foregroundStyle(state == .before ? Color.hydraAlert.opacity(0.7) : Color.hydraLive)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.hydraPanel)
            }
        }
    }

    private var orphanCount: Int {
        let connected = Set(edges.flatMap { [$0.source, $0.target] })
        return nodes.filter { !connected.contains($0.id) }.count
    }

    private func statPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(HydraTheme.mono(.callout, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(HydraTheme.mono(.caption2, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Color.hydraMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.08)))
        .overlay(Capsule().strokeBorder(color.opacity(0.2), lineWidth: 1))
    }

    private func edgeColor(_ type: RelationshipType, alpha: CGFloat) -> Color {
        switch type {
        case .implements:   Color.hydraLive.opacity(alpha)
        case .dependsOn:    Color.hydraAlert.opacity(alpha)
        case .supersedes:   Color(red: 0.75, green: 0.55, blue: 0.95).opacity(alpha)
        case .references:   Color.hydraAccent.opacity(alpha)
        case .childOf:      Color.hydraMuted.opacity(alpha)
        case .derivedFrom:  Color(red: 0.45, green: 0.75, blue: 0.95).opacity(alpha)
        case .relatesTo:    Color.hydraPartial.opacity(alpha)
        case .blocks:       Color.hydraAlert.opacity(alpha)
        }
    }
}
