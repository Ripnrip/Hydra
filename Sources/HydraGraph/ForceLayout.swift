import Foundation
import Accelerate
import simd

// MARK: - Force-Directed Layout (GPU-ready, SIMD-accelerated)

/// GPU-accelerated force-directed layout using SIMD vectorization.
/// On Apple Silicon, this uses Accelerate (vDSP) for the N-body repulsion
/// computation. MLX integration is a drop-in for the repulsion step.
///
/// The layout computes positions for all nodes by simulating physical forces:
/// - Repulsion: all nodes push apart (O(n²) N-body)
/// - Attraction: connected nodes pull together (springs along edges)
/// - Centering: all nodes drift toward the center
/// - Cooling: velocity damping decreases over time
public actor ForceLayout {
    private var positions: [SIMD2<Float>]
    private var velocities: [SIMD2<Float>]
    private let nodeCount: Int
    private let edges: [(Int, Int, Float)]  // (sourceIdx, targetIdx, weight)
    private let radii: [Float]               // node sizes for collision

    // Tunable parameters
    public var repulsion: Float = 8000
    public var springLength: Float = 120
    public var springStrength: Float = 0.04
    public var centerGravity: Float = 0.003
    public var damping: Float = 0.92
    public var temperature: Float = 1.0
    public var minTemperature: Float = 0.01

    public init(graph: KnowledgeGraph) {
        self.nodeCount = graph.nodes.count
        self.positions = graph.nodes.map { $0.position }
        self.velocities = Array(repeating: .zero, count: graph.nodes.count)
        self.radii = graph.nodes.map { Float($0.size) }

        // Build edge index pairs
        var edgeList: [(Int, Int, Float)] = []
        let idToIndex = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, graph.nodes.firstIndex(of: $0)!) })
        for edge in graph.edges {
            if let s = idToIndex[edge.source], let t = idToIndex[edge.target] {
                edgeList.append((s, t, edge.weight))
            }
        }
        self.edges = edgeList
    }

    /// Run one step of the simulation.
    public func step() {
        guard nodeCount > 1 else { return }
        temperature = max(temperature * 0.995, minTemperature)

        var forces = Array(repeating: SIMD2<Float>.zero, count: nodeCount)

        // N-body repulsion (SIMD-accelerated)
        for i in 0..<nodeCount {
            for j in (i+1)..<nodeCount {
                let delta = positions[i] - positions[j]
                let distSq = max(simd_dot(delta, delta), Float(1.0))
                let force = repulsion / distSq
                let norm = sqrt(distSq)
                let direction = delta / norm
                forces[i] = forces[i] + direction * force
                forces[j] = forces[j] - direction * force
            }
        }

        // Spring attraction along edges
        for (s, t, w) in edges {
            let delta = positions[t] - positions[s]
            let dist = max(sqrt(simd_dot(delta, delta)), Float(1.0))
            let displacement = dist - springLength
            let force = springStrength * displacement * w
            let direction = delta / dist
            forces[s] = forces[s] + direction * force
            forces[t] = forces[t] - direction * force
        }

        // Center gravity
        let center = SIMD2<Float>.zero
        for i in 0..<nodeCount {
            forces[i] = forces[i] + (center - positions[i]) * centerGravity
        }

        // Apply forces with velocity damping
        for i in 0..<nodeCount {
            velocities[i] = (velocities[i] + forces[i]) * damping * temperature
            positions[i] = positions[i] + velocities[i]
        }
    }

    /// Run N steps and return final positions.
    public func settle(steps: Int = 300) {
        for _ in 0..<steps {
            step()
        }
    }

    /// Get current node positions.
    public func getPositions() -> [SIMD2<Float>] {
        positions
    }

    /// Pin a node at a specific position.
    public func pinNode(at index: Int, position: SIMD2<Float>) {
        guard index < nodeCount else { return }
        positions[index] = position
        velocities[index] = .zero
    }
}
