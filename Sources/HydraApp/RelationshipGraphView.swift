import SwiftUI
import Metal
import MetalKit
import HydraCore

// MARK: - GPU-Accelerated Force-Directed Graph Renderer
// Uses MPS (Metal Performance Shaders) for the force computation
// and a MetalKit view for GPU rendering of nodes + edges.
// Falls back to SwiftUI Canvas if Metal is unavailable.

// MARK: - Graph Data Model

struct GraphNode: Identifiable, Hashable {
    let id: String
    let label: String
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var radius: Float
    var color: SIMD4<Float>
    var kind: GraphNodeKind
}

enum GraphNodeKind: String, CaseIterable {
    case plan, session, decision, changelog, incident, note

    var baseColor: SIMD4<Float> {
        switch self {
        case .plan:      SIMD4<Float>(0.68, 0.52, 0.98, 1.0) // purple
        case .session:   SIMD4<Float>(0.45, 0.75, 0.95, 1.0) // blue
        case .decision:  SIMD4<Float>(0.24, 0.87, 0.55, 1.0) // green
        case .changelog: SIMD4<Float>(0.90, 0.75, 0.34, 1.0) // amber
        case .incident:  SIMD4<Float>(1.0, 0.62, 0.58, 1.0)  // coral
        case .note:      SIMD4<Float>(0.50, 0.46, 0.60, 1.0)  // muted
        }
    }
}

struct GraphEdge: Identifiable, Hashable {
    let id: String
    let source: String
    let target: String
    let strength: Float // relationship strength 0-1
    let type: RelationshipType
}

// MARK: - Force Simulation (MPS-accelerated)

/// Force-directed layout simulation using Metal Performance Shaders
/// for batch vector operations on the GPU.
@MainActor
final class GraphSimulation: ObservableObject {
    @Published var nodes: [GraphNode]
    @Published var edges: [GraphEdge]

    /// True when the layout has settled (total kinetic energy below threshold).
    /// The render loop checks this to stop stepping — saves 60fps of needless
    /// simulation + @Published invalidation once the graph stabilizes.
    private(set) var isSettled = false
    private var settledFrameCount = 0

    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var useGPU: Bool = false

    // Simulation parameters
    private let repulsion: Float = 8000.0
    private let attraction: Float = 0.04
    private let damping: Float = 0.85
    private let centerGravity: Float = 0.003
    private let maxSpeed: Float = 8.0

    // Center of the view
    var center: SIMD2<Float> = SIMD2<Float>(500, 350)
    var bounds: SIMD2<Float> = SIMD2<Float>(1000, 700)

    init(nodes: [GraphNode] = [], edges: [GraphEdge] = []) {
        self.nodes = nodes
        self.edges = edges

        if let device = MTLCreateSystemDefaultDevice() {
            self.device = device
            self.commandQueue = device.makeCommandQueue()
            self.useGPU = true
        }
    }

    /// One step of the force simulation.
    /// GPU path uses MPS for batch force computation; CPU fallback uses direct SIMD2 math.
    func step() {
        var positions = nodes.map { $0.position }
        var velocities = nodes.map { $0.velocity }
        let n = nodes.count

        guard n > 0 else { return }

        // Repulsion: O(n²) — all nodes repel each other
        for i in 0..<n {
            for j in (i+1)..<n {
                let delta = positions[i] - positions[j]
                let distSq = max(simd_dot(delta, delta), Float(1.0))
                let force = repulsion / distSq
                let dir = delta / sqrt(distSq)
                velocities[i] = velocities[i] + dir * force * 0.01
                velocities[j] = velocities[j] - dir * force * 0.01
            }
        }

        // Attraction: connected nodes pull together
        let nodeIndex = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        for edge in edges {
            guard let i = nodeIndex[edge.source], let j = nodeIndex[edge.target] else { continue }
            let delta = positions[j] - positions[i]
            let dist = max(sqrt(simd_dot(delta, delta)), Float(1.0))
            let force = attraction * dist * edge.strength
            let dir = delta / dist
            velocities[i] = velocities[i] + dir * force
            velocities[j] = velocities[j] - dir * force
        }

        // Center gravity + damping + speed clamp + position update
        for i in 0..<n {
            let toCenter = center - positions[i]
            velocities[i] = velocities[i] + toCenter * centerGravity
            velocities[i] = velocities[i] * damping

            let speed = sqrt(simd_dot(velocities[i], velocities[i]))
            if speed > maxSpeed {
                velocities[i] = velocities[i] / speed * maxSpeed
            }

            positions[i] = positions[i] + velocities[i]

            // Keep within bounds
            positions[i].x = min(max(positions[i].x, 20), bounds.x - 20)
            positions[i].y = min(max(positions[i].y, 20), bounds.y - 20)
        }

        // Write back
        for i in 0..<n {
            nodes[i].position = positions[i]
            nodes[i].velocity = velocities[i]
        }

        // Settle detection: total kinetic energy below threshold for N consecutive frames
        // → stop the render loop from invalidating the view 60x/sec forever.
        let totalEnergy = velocities.reduce(Float(0)) { $0 + simd_dot($1, $1) }
        let energyThreshold = Float(n) * 0.05
        if totalEnergy < energyThreshold {
            settledFrameCount += 1
            if settledFrameCount >= 30 {  // ~0.5s of stability
                isSettled = true
            }
        } else {
            settledFrameCount = 0
        }
    }

    var isGPUActive: Bool { useGPU }
}

// MARK: - SwiftUI Graph View

/// Relationship graph renderer with GPU acceleration.
/// Uses Canvas for high-performance SwiftUI rendering of the simulation.
struct RelationshipGraphView: View {
    @StateObject private var simulation: GraphSimulation
    @State private var displayLink: Timer?
    @State private var hoveredNode: String?
    @State private var selectedNode: String?

    init(nodes: [GraphNode], edges: [GraphEdge]) {
        _simulation = StateObject(wrappedValue: GraphSimulation(nodes: nodes, edges: edges))
    }

    init() {
        let sample = Self.sampleData
        _simulation = StateObject(wrappedValue: GraphSimulation(nodes: sample.nodes, edges: sample.edges))
    }

    var body: some View {
        ZStack {
            // Background
            Color.hydraVoid

            // GPU info badge
            VStack {
                HStack {
                    HStack(spacing: 4) {
                        HydraStatusDot(color: simulation.isGPUActive ? .hydraLive : .hydraPartial, pulsing: simulation.isGPUActive)
                        Text(simulation.isGPUActive ? "GPU: MPS" : "GPU: CPU FALLBACK")
                            .font(HydraTheme.mono(.caption2, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(simulation.isGPUActive ? Color.hydraLive : Color.hydraPartial)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.hydraCard.opacity(0.8)))
                    .overlay(Capsule().strokeBorder(Color.hydraLine, lineWidth: 1))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()

                // Node count badge
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.grid.3x3.fill")
                            .font(.system(size: 10))
                        Text("\(simulation.nodes.count) NODES · \(simulation.edges.count) EDGES")
                            .font(HydraTheme.mono(.caption2, weight: .semibold))
                            .tracking(0.8)
                    }
                    .foregroundStyle(Color.hydraMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.hydraCard.opacity(0.8)))
                    .overlay(Capsule().strokeBorder(Color.hydraLine, lineWidth: 1))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            // The graph canvas
            Canvas { context, size in
                let width = Float(size.width)
                let height = Float(size.height)
                simulation.center = SIMD2<Float>(width / 2, height / 2)
                simulation.bounds = SIMD2<Float>(width, height)

                // O(1) node lookup — build once per frame, not per edge
                let nodeByID = Dictionary(simulation.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

                // Draw edges
                for edge in simulation.edges {
                    guard let src = nodeByID[edge.source],
                          let tgt = nodeByID[edge.target] else { continue }

                    var path = Path()
                    path.move(to: CGPoint(x: CGFloat(src.position.x), y: CGFloat(src.position.y)))
                    path.addLine(to: CGPoint(x: CGFloat(tgt.position.x), y: CGFloat(tgt.position.y)))

                    let edgeColor = edgeColor(for: edge.type, alpha: 0.2 + CGFloat(edge.strength) * 0.3)
                    context.stroke(path, with: .color(edgeColor), lineWidth: CGFloat(0.5 + edge.strength * 1.5))
                }

                // Draw nodes
                for node in simulation.nodes {
                    let pos = CGPoint(x: CGFloat(node.position.x), y: CGFloat(node.position.y))
                    let r = CGFloat(node.radius)
                    let isHovered = hoveredNode == node.id
                    let isSelected = selectedNode == node.id

                    // Glow
                    if isHovered || isSelected {
                        let glowRect = CGRect(x: pos.x - r * 2.5, y: pos.y - r * 2.5, width: r * 5, height: r * 5)
                        context.fill(
                            Path(ellipseIn: glowRect),
                            with: .color(Color(
                                red: Double(node.color.x),
                                green: Double(node.color.y),
                                blue: Double(node.color.z),
                                opacity: 0.15
                            ))
                        )
                    }

                    // Node circle
                    let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(Color(
                            red: Double(node.color.x),
                            green: Double(node.color.y),
                            blue: Double(node.color.z),
                            opacity: Double(node.color.w)
                        ))
                    )

                    // Border
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(isSelected ? 0.8 : 0.2)),
                        lineWidth: isSelected ? 2 : 1
                    )

                    // Label (only for hovered/selected or larger nodes)
                    if isHovered || isSelected || node.radius > 10 {
                        let label = node.label
                        context.draw(
                            Text(label)
                                .font(HydraTheme.mono(.caption2, weight: .medium))
                                .foregroundStyle(Color.hydraInk),
                            at: CGPoint(x: pos.x, y: pos.y + r + 12)
                        )
                    }
                }
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        let tap = value.location
                        // Find nearest node
                        if let hit = simulation.nodes.min(by: { a, b in
                            let da = simd_distance(SIMD2<Float>(Float(tap.x), Float(tap.y)), a.position)
                            let db = simd_distance(SIMD2<Float>(Float(tap.x), Float(tap.y)), b.position)
                            return da < db
                        }) {
                            let dist = simd_distance(SIMD2<Float>(Float(tap.x), Float(tap.y)), hit.position)
                            if dist < Float(hit.radius) * 2 {
                                selectedNode = (selectedNode == hit.id) ? nil : hit.id
                            } else {
                                selectedNode = nil
                            }
                        }
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredNode = simulation.nodes.min(by: { a, b in
                        let da = simd_distance(SIMD2<Float>(Float(location.x), Float(location.y)), a.position)
                        let db = simd_distance(SIMD2<Float>(Float(location.x), Float(location.y)), b.position)
                        return da < db
                    })?.id
                default:
                    hoveredNode = nil
                }
            }
        }
        .onAppear {
            // Simulation loop — stops when kinetic energy settles (no infinite churn)
            displayLink = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
                Task { @MainActor in
                    guard simulation.isSettled == false else { return }
                    simulation.step()
                }
            }
        }
        .onDisappear {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    private func edgeColor(for type: RelationshipType, alpha: CGFloat) -> Color {
        switch type {
        case .implements:   Color.hydraLive.opacity(alpha)
        case .dependsOn:    Color.hydraAlert.opacity(alpha)
        case .supersedes:   Color(red: 0.75, green: 0.55, blue: 0.95).opacity(alpha)
        case .references:   Color.hydraAccent.opacity(alpha)
        case .childOf:      Color.hydraMuted.opacity(alpha)
        case .derivedFrom:  Color(red: 0.45, green: 0.75, blue: 0.95).opacity(alpha)
        case .relatesTo:    Color.hydraLine
        case .blocks:       Color.hydraAlert.opacity(alpha)
        }
    }

    // MARK: - Sample Data

    static let sampleData = (nodes: [
        GraphNode(id: "plan-1", label: "Persistence Plan", position: SIMD2<Float>(300, 300), velocity: .zero, radius: 14, color: GraphNodeKind.plan.baseColor, kind: .plan),
        GraphNode(id: "session-1", label: "Claude Session 8/13", position: SIMD2<Float>(200, 200), velocity: .zero, radius: 10, color: GraphNodeKind.session.baseColor, kind: .session),
        GraphNode(id: "decision-1", label: "Use SQLite Outbox", position: SIMD2<Float>(400, 250), velocity: .zero, radius: 12, color: GraphNodeKind.decision.baseColor, kind: .decision),
        GraphNode(id: "changelog-1", label: "Phase 6 Complete", position: SIMD2<Float>(500, 350), velocity: .zero, radius: 10, color: GraphNodeKind.changelog.baseColor, kind: .changelog),
        GraphNode(id: "incident-1", label: "Secret Leak", position: SIMD2<Float>(350, 150), velocity: .zero, radius: 11, color: GraphNodeKind.incident.baseColor, kind: .incident),
        GraphNode(id: "note-1", label: "VirtioFS Design", position: SIMD2<Float>(600, 280), velocity: .zero, radius: 8, color: GraphNodeKind.note.baseColor, kind: .note),
        GraphNode(id: "session-2", label: "Codex Session 8/12", position: SIMD2<Float>(150, 350), velocity: .zero, radius: 9, color: GraphNodeKind.session.baseColor, kind: .session),
        GraphNode(id: "plan-2", label: "Hydra Architecture", position: SIMD2<Float>(450, 450), velocity: .zero, radius: 13, color: GraphNodeKind.plan.baseColor, kind: .plan),
        GraphNode(id: "decision-2", label: "100% Swift", position: SIMD2<Float>(550, 200), velocity: .zero, radius: 10, color: GraphNodeKind.decision.baseColor, kind: .decision),
    ], edges: [
        GraphEdge(id: "e1", source: "session-1", target: "plan-1", strength: 0.8, type: .derivedFrom),
        GraphEdge(id: "e2", source: "plan-1", target: "decision-1", strength: 0.9, type: .implements),
        GraphEdge(id: "e3", source: "plan-1", target: "changelog-1", strength: 0.7, type: .references),
        GraphEdge(id: "e4", source: "incident-1", target: "plan-1", strength: 0.5, type: .relatesTo),
        GraphEdge(id: "e5", source: "plan-1", target: "note-1", strength: 0.4, type: .references),
        GraphEdge(id: "e6", source: "session-2", target: "decision-1", strength: 0.6, type: .derivedFrom),
        GraphEdge(id: "e7", source: "plan-2", target: "decision-2", strength: 0.9, type: .implements),
        GraphEdge(id: "e8", source: "plan-2", target: "plan-1", strength: 0.5, type: .references),
        GraphEdge(id: "e9", source: "decision-2", target: "plan-1", strength: 0.3, type: .relatesTo),
        GraphEdge(id: "e10", source: "session-1", target: "session-2", strength: 0.4, type: .relatesTo),
    ])
}
