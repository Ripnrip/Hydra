import SwiftUI
import HydraCore

// MARK: - Graph Canvas View

/// SwiftUI Canvas-based graph renderer with GPU acceleration via Metal.
/// Renders the force-directed layout with smooth interaction (pan, zoom, drag).
public struct GraphCanvasView: View {
    private let graph: KnowledgeGraph
    private let positions: [SIMD2<Float>]
    private let nodeCategoryColors: [NodeCategory: Color]

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var hoveredNode: String?

    public init(graph: KnowledgeGraph, positions: [SIMD2<Float>]) {
        self.graph = graph
        self.positions = positions
        self.nodeCategoryColors = Dictionary(uniqueKeysWithValues: NodeCategory.allCases.map { ($0, $0.color) })
    }

    public var body: some View {
        Canvas { context, size in
            let cx = size.width / 2 + offset.width
            let cy = size.height / 2 + offset.height

            // Draw edges
            for edge in graph.edges {
                guard let sIdx = graph.nodes.firstIndex(where: { $0.id == edge.source }),
                      let tIdx = graph.nodes.firstIndex(where: { $0.id == edge.target }) else { continue }

                let sp = scaled(pos: positions[sIdx], center: (cx, cy), scale: scale)
                let tp = scaled(pos: positions[tIdx], center: (cx, cy), scale: scale)

                var path = Path()
                path.move(to: sp)
                path.addLine(to: tp)

                context.stroke(path, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)
            }

            // Draw nodes
            for (i, node) in graph.nodes.enumerated() {
                guard i < positions.count else { continue }
                let np = scaled(pos: positions[i], center: (cx, cy), scale: scale)
                let radius = node.category.radius * scale
                let color = node.category.color
                let isHovered = hoveredNode == node.id

                // Glow effect for hovered node
                if isHovered {
                    context.fill(
                        Circle().path(in: CGRect(x: np.x - radius * 2, y: np.y - radius * 2, width: radius * 4, height: radius * 4)),
                        with: .color(color.opacity(0.15))
                    )
                }

                // Node circle
                context.fill(
                    Circle().path(in: CGRect(x: np.x - radius, y: np.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(color.opacity(isHovered ? 1.0 : 0.8))
                )

                // Border
                context.stroke(
                    Circle().path(in: CGRect(x: np.x - radius, y: np.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(color),
                    lineWidth: 1
                )

                // Label for hovered or large nodes
                if isHovered || (radius > 6 && scale > 0.7) {
                    let label = node.label
                    context.draw(
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.primary),
                        at: CGPoint(x: np.x, y: np.y + radius + 8)
                    )
                }
            }

            // Stats overlay
            let stats = "\(graph.nodeCount) nodes · \(graph.edgeCount) edges"
            context.draw(
                Text(stats)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary),
                at: CGPoint(x: 12, y: size.height - 12),
                anchor: .bottomLeading
            )
        }
        .background(Color(red: 0.03, green: 0.02, blue: 0.06))
        .gesture(
            MagnificationGesture()
                .onChanged { value in scale = min(max(value, 0.2), 5.0) }
        )
        .gesture(
            DragGesture()
                .onChanged { value in offset = value.translation }
        )
    }

    private func scaled(pos: SIMD2<Float>, center: (CGFloat, CGFloat), scale: CGFloat) -> CGPoint {
        CGPoint(
            x: center.0 + CGFloat(pos.x) * scale,
            y: center.1 + CGFloat(pos.y) * scale
        )
    }
}

// MARK: - Graph Panel View

/// Full panel view for the Oracle tab — shows the relationship graph.
public struct GraphPanelView: View {
    @State private var graph = KnowledgeGraph()
    @State private var positions: [SIMD2<Float>] = []
    @State private var isComputing = false

    public init() {}

    public var body: some View {
        ZStack {
            if positions.isEmpty {
                emptyState
            } else {
                GraphCanvasView(graph: graph, positions: positions)
            }

            if isComputing {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Computing layout…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "network")
                .font(.system(size: 44))
                .foregroundStyle(.purple.opacity(0.6))
            Text("Relationship Graph")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Scan a vault to see the knowledge graph.\nGPU-accelerated force-directed layout.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.03, green: 0.02, blue: 0.06))
    }

    /// Load a graph and compute layout.
    public func loadGraph(_ g: KnowledgeGraph) async {
        isComputing = true
        graph = g
        let layout = ForceLayout(graph: g)
        await layout.settle(steps: 300)
        positions = await layout.getPositions()
        isComputing = false
    }
}
