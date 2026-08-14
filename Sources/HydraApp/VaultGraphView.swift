import SwiftUI
import HydraCore
import HydraVault

// MARK: - Vault Graph View

/// Visual force-directed relationship graph rendered directly in the Oracle tab.
/// Nodes = vault notes, edges = wikilinks. Purple obsidian theme.
struct VaultGraphView: View {
    let inventory: VaultInventory
    @State private var nodePositions: [String: CGPoint] = [:]
    @State private var selectedNode: String?
    @State private var computed = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.hydraVoid

                // Edges
                ForEach(edgeSegments(in: geo.size), id: \.id) { edge in
                    Path { p in
                        p.move(to: edge.from)
                        p.addLine(to: edge.to)
                    }
                    .stroke(
                        Color.hydraAccent.opacity(edge.isHighlight ? 0.5 : 0.12),
                        lineWidth: edge.isHighlight ? 1.5 : 0.5
                    )
                }

                // Nodes
                ForEach(topNodes, id: \.id) { note in
                    if let pos = nodePositions[note.title.lowercased()] {
                        nodeView(note, at: pos)
                    }
                }

                // Stats overlay
                VStack {
                    Spacer()
                    HStack {
                        Text("\(topNodes.count) nodes · \(edgeCount) edges")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.hydraMuted)
                            .padding(8)
                            .background(Color.hydraPanel.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                        Spacer()
                    }
                    .padding(12)
                }
            }
        }
        .onAppear { computeLayout() }
    }

    // MARK: - Node rendering

    @ViewBuilder
    private func nodeView(_ note: VaultNote, at pos: CGPoint) -> some View {
        let isSelected = selectedNode == note.title.lowercased()
        let connections = inventory.adjacencyList[note.title.lowercased()]?.count ?? 0
        let radius = nodeRadius(for: connections)

        ZStack {
            // Glow for selected
            if isSelected {
                Circle()
                    .fill(Color.hydraAccent.opacity(0.15))
                    .frame(width: radius * 4, height: radius * 4)
            }

            Circle()
                .fill(color(for: note))
                .frame(width: radius * 2, height: radius * 2)
                .overlay(
                    Circle().strokeBorder(
                        isSelected ? Color.hydraAccent : Color.hydraVoid,
                        lineWidth: isSelected ? 2 : 1
                    )
                )

            // Label (always for selected/large, on hover otherwise)
            if isSelected || connections > 2 {
                Text(note.title)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.hydraInk)
                    .lineLimit(1)
                    .offset(y: radius + 10)
            }
        }
        .position(pos)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedNode = selectedNode == note.title.lowercased() ? nil : note.title.lowercased()
            }
        }
    }

    // MARK: - Layout computation (deterministic circular with jitter)

    private func computeLayout() {
        guard !computed else { return }
        computed = true

        let nodes = topNodes
        var positions: [String: CGPoint] = [:]

        // Group by connectivity — most connected in center
        let sorted = nodes.sorted { a, b in
            (inventory.adjacencyList[a.title.lowercased()]?.count ?? 0) >
            (inventory.adjacencyList[b.title.lowercased()]?.count ?? 0)
        }

        let center = CGPoint(x: 0.5, y: 0.5)
        for (i, note) in sorted.enumerated() {
            let connections = inventory.adjacencyList[note.title.lowercased()]?.count ?? 0
            let angle = Double(i) / Double(sorted.count) * 2 * .pi
            let dist = connections > 2 ? 0.15 : connections > 0 ? 0.3 : 0.42
            let jitter = connections == 0 ? 0.08 : 0.02

            let x = center.x + cos(angle) * (dist + Double.random(in: -jitter...jitter))
            let y = center.y + sin(angle) * (dist + Double.random(in: -jitter...jitter))

            positions[note.title.lowercased()] = CGPoint(x: x, y: y)
        }
        nodePositions = positions
    }

    // MARK: - Edge computation

    private struct GraphEdgeSegment: Identifiable {
        let id: String
        let from: CGPoint
        let to: CGPoint
        let isHighlight: Bool
    }

    private func edgeSegments(in size: CGSize) -> [GraphEdgeSegment] {
        var segments: [GraphEdgeSegment] = []
        let selected = selectedNode

        for note in topNodes {
            let fromKey = note.title.lowercased()
            guard let from = nodePositions[fromKey] else { continue }

            for target in note.wikilinks {
                let toKey = target.lowercased()
                guard let to = nodePositions[toKey] else { continue }

                let isHighlight = selected != nil &&
                    (fromKey == selected || toKey == selected)

                segments.append(GraphEdgeSegment(
                    id: "\(fromKey)→\(toKey)",
                    from: CGPoint(x: from.x * size.width, y: from.y * size.height),
                    to: CGPoint(x: to.x * size.width, y: to.y * size.height),
                    isHighlight: isHighlight
                ))
            }
        }
        return segments
    }

    // MARK: - Node selection (top 40 by connectivity + recency)

    private var topNodes: [VaultNote] {
        let sorted = inventory.notes.sorted { a, b in
            let aLinks = inventory.adjacencyList[a.title.lowercased()]?.count ?? 0
            let bLinks = inventory.adjacencyList[b.title.lowercased()]?.count ?? 0
            if aLinks != bLinks { return aLinks > bLinks }
            return a.modifiedDate > b.modifiedDate
        }
        return Array(sorted.prefix(40))
    }

    private var edgeCount: Int {
        topNodes.reduce(0) { $0 + $1.wikilinks.count }
    }

    private func nodeRadius(for connections: Int) -> CGFloat {
        switch connections {
        case 0...1: 4
        case 2...4: 6
        case 5...9: 8
        default: 10
        }
    }

    private func color(for note: VaultNote) -> Color {
        switch note.paraCategory {
        case .session:  Color.hydraAccent.opacity(0.7)
        case .system:   Color.hydraAccent
        case .project:  Color(red: 0.88, green: 0.53, blue: 0.28)
        case .concept:  Color(red: 0.90, green: 0.75, blue: 0.34)
        case .journal, .daily: Color(red: 0.47, green: 0.47, blue: 0.56)
        default:        Color.hydraMuted
        }
    }
}
