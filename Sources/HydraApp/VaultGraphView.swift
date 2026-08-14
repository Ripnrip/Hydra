import SwiftUI
import HydraCore
import HydraVault

// MARK: - Vault Graph View

/// Visual relationship graph rendered in pixel space.
/// Nodes = vault notes, edges = wikilinks. Deterministic layout (no random).
/// Selected node's connections highlight; everything else dims.
struct VaultGraphView: View {
    let inventory: VaultInventory
    /// Notes highlighted by a RAG query: semantic hits (bright) + graph hits (soft)
    var highlightedSemanticIDs: Set<String> = []
    var highlightedGraphIDs: Set<String> = []
    @State private var selectedNode: String?
    @State private var settledLayout: [String: NodeLayout] = [:]
    @State private var settledSize: CGSize = .zero

    private var hasHighlights: Bool { !highlightedSemanticIDs.isEmpty || !highlightedGraphIDs.isEmpty }

    /// Compute layout ONCE per size via onAppear — never mutate @State inside body.
    private func layoutIfNeeded(_ size: CGSize) -> [String: NodeLayout] {
        if settledSize == size, !settledLayout.isEmpty {
            return settledLayout
        }
        // Return the computed value WITHOUT caching (pure read)
        return layout(in: size)
    }

    var body: some View {
        GeometryReader { geo in
            let computed = layoutIfNeeded(geo.size)

            ZStack {
                Color(red: 0.04, green: 0.02, blue: 0.07)

                // Edges
                ForEach(edges(in: computed), id: \.id) { edge in
                    Path { p in
                        p.move(to: edge.from)
                        p.addLine(to: edge.to)
                    }
                    .stroke(
                        edgeStrokeColor(edge),
                        lineWidth: edgeLineWidth(edge)
                    )
                }

                // Nodes
                ForEach(Array(computed.keys.sorted()), id: \.self) { key in
                    if let item = computed[key] {
                        nodeLabel(item, isSelected: selectedNode == key)
                            .position(item.point)
                    }
                }
            }
            .clipped()
        }
        .overlay(alignment: .bottomLeading) {
            Text("\(topNodes.count) nodes · \(edgeCount) edges")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.hydraMuted)
                .padding(8)
                .background(Color.hydraPanel.opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
                .padding(10)
        }
    }

    // MARK: - RAG highlight helpers

    private func edgeStrokeColor(_ edge: EdgeSegment) -> Color {
        if hasHighlights {
            // During RAG highlighting: edges between highlighted nodes glow
            let fromKey = edge.id.components(separatedBy: "|").first ?? ""
            let toKey = edge.id.components(separatedBy: "|").last ?? ""
            let fromHi = highlightedSemanticIDs.contains(fromKey) || highlightedGraphIDs.contains(fromKey)
            let toHi = highlightedSemanticIDs.contains(toKey) || highlightedGraphIDs.contains(toKey)
            if fromHi && toHi { return Color.hydraAccent.opacity(0.7) }
            if fromHi || toHi { return Color.hydraAccent.opacity(0.35) }
            return Color.hydraAccent.opacity(0.05)  // dim non-retrieved
        }
        return Color.hydraAccent.opacity(edge.highlight ? 0.55 : 0.14)
    }

    private func edgeLineWidth(_ edge: EdgeSegment) -> CGFloat {
        if hasHighlights {
            let fromKey = edge.id.components(separatedBy: "|").first ?? ""
            let toKey = edge.id.components(separatedBy: "|").last ?? ""
            let fromHi = highlightedSemanticIDs.contains(fromKey) || highlightedGraphIDs.contains(fromKey)
            let toHi = highlightedSemanticIDs.contains(toKey) || highlightedGraphIDs.contains(toKey)
            if fromHi && toHi { return 2 }
            if fromHi || toHi { return 1 }
            return 0.5
        }
        return edge.highlight ? 1.5 : 0.5
    }

    private func nodeHighlightLevel(_ key: String) -> HighlightLevel {
        if highlightedSemanticIDs.contains(key) { return .semantic }
        if highlightedGraphIDs.contains(key) { return .graph }
        return hasHighlights ? .dimmed : .normal
    }

    enum HighlightLevel {
        case normal, semantic, graph, dimmed
    }

    // MARK: - Node view

    private func isDimmed(_ item: NodeLayout, isSelected: Bool) -> Bool {
        let level = nodeHighlightLevel(item.key)
        if level == .dimmed { return true }
        return selectedNode != nil && !isSelected && !item.isConnectedToSelected
    }

    @ViewBuilder
    private func nodeLabel(_ item: NodeLayout, isSelected: Bool) -> some View {
        let connections = item.connections
        let level = nodeHighlightLevel(item.key)
        let dimmed = isDimmed(item, isSelected: isSelected)

        ZStack {
            if isSelected || level == .semantic {
                // Glow halo for selected + semantic hits
                Circle()
                    .fill(Color.hydraAccent.opacity(level == .semantic ? 0.25 : 0.18))
                    .frame(width: item.radius * (level == .semantic ? 5 : 4.5),
                           height: item.radius * (level == .semantic ? 5 : 4.5))
                    .shadow(color: Color.hydraAccent.opacity(0.5), radius: level == .semantic ? 8 : 0)
            }

            Circle()
                .fill(level == .semantic ? Color.hydraAccent : item.color)
                .frame(width: item.radius * (level == .semantic ? 2.2 : 2.0),
                       height: item.radius * (level == .semantic ? 2.2 : 2.0))
                .overlay(
                    Circle().strokeBorder(
                        isSelected || level == .semantic
                            ? Color.hydraAccent
                            : Color(red: 0.04, green: 0.02, blue: 0.07),
                        lineWidth: isSelected || level == .semantic ? 2.5 : 1
                    )
                )
                .opacity(dimmed ? 0.15 : level == .graph ? 0.7 : 1)

            Text(item.title)
                .font(.system(size: isSelected || level == .semantic ? 11 : 9, design: .monospaced))
                .foregroundStyle(Color.hydraInk.opacity(dimmed ? 0.15 : level == .graph ? 0.6 : 0.9))
                .lineLimit(1)
                .fixedSize()
                .offset(y: item.radius + 9)
                .opacity(isSelected || connections >= 2 || selectedNode == nil || level != .dimmed ? 1 : 0)
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedNode = selectedNode == item.key ? nil : item.key
            }
        }
    }

    // MARK: - Layout (deterministic, pixel space)

    struct NodeLayout {
        let key: String
        let title: String
        let point: CGPoint
        let radius: CGFloat
        let color: Color
        let connections: Int
        let isConnectedToSelected: Bool
    }

    private func layout(in size: CGSize) -> [String: NodeLayout] {
        let nodes = topNodes
        guard !nodes.isEmpty, size.width > 10 else { return [:] }

        // Sort: most connected first → placed closest to center
        let ranked = nodes.map { note -> (VaultNote, Int) in
            (note, inventory.adjacencyList[note.title.lowercased()]?.count ?? 0)
        }
        .sorted { $0.1 > $1.1 }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = min(size.width, size.height) / 2 - 50
        let selected = selectedNode
        var result: [String: NodeLayout] = [:]

        // Connected nodes: concentric rings by degree. Orphans: outer ring.
        let connected = ranked.filter { $0.1 > 0 }
        let orphans = ranked.filter { $0.1 == 0 }

        func place(_ entries: [(VaultNote, Int)], baseRadius: CGFloat, ringSpread: CGFloat) {
            guard !entries.isEmpty else { return }
            let n = entries.count
            for (i, entry) in entries.enumerated() {
                let (note, connections) = entry
                let key = note.title.lowercased()
                let angle = (Double(i) / Double(n)) * 2 * .pi - .pi / 2
                // Inner (more connected) → tighter ring
                let ringOffset = ringSpread * CGFloat(min(connections, 8)) / 8.0
                let r = max(baseRadius - ringOffset, 30)
                let point = CGPoint(
                    x: center.x + cos(angle) * r,
                    y: center.y + sin(angle) * r * 0.85  // slight ellipse
                )
                let isLinkedToSelected: Bool
                if let sel = selected {
                    isLinkedToSelected = inventory.adjacencyList[sel]?.contains(key) ?? false
                        || inventory.adjacencyList[key]?.contains(sel) ?? false
                } else {
                    isLinkedToSelected = false
                }
                result[key] = NodeLayout(
                    key: key,
                    title: note.title.isEmpty ? "untitled" : note.title,
                    point: point,
                    radius: radius(for: connections),
                    color: color(for: note),
                    connections: connections,
                    isConnectedToSelected: isLinkedToSelected
                )
            }
        }

        // Connected nodes occupy inner space; orphans on the rim
        if !connected.isEmpty && !orphans.isEmpty {
            let split = maxRadius * 0.62
            place(connected, baseRadius: split, ringSpread: split * 0.5)
            place(orphans, baseRadius: maxRadius, ringSpread: maxRadius * 0.1)
        } else {
            place(ranked, baseRadius: maxRadius * 0.8, ringSpread: maxRadius * 0.45)
        }

        return result
    }

    // MARK: - Edges

    private struct EdgeSegment: Identifiable {
        let id: String
        let from: CGPoint
        let to: CGPoint
        let highlight: Bool
    }

    private func edges(in layout: [String: NodeLayout]) -> [EdgeSegment] {
        layoutCompactEdges(layout, highlightKey: selectedNode)
    }

    private func layoutCompactEdges(_ layout: [String: NodeLayout], highlightKey: String?) -> [EdgeSegment] {
        var segments: [EdgeSegment] = []
        var seen = Set<String>()

        for note in topNodes {
            let fromKey = note.title.lowercased()
            guard let fromNode = layout[fromKey] else { continue }

            for target in note.wikilinks {
                let toKey = target.lowercased()
                guard let toNode = layout[toKey] else { continue }

                let edgeID = fromKey < toKey ? "\(fromKey)|\(toKey)" : "\(toKey)|\(fromKey)"
                guard !seen.contains(edgeID) else { continue }
                seen.insert(edgeID)

                let highlight = highlightKey != nil &&
                    (fromKey == highlightKey || toKey == highlightKey)

                segments.append(EdgeSegment(
                    id: edgeID,
                    from: fromNode.point,
                    to: toNode.point,
                    highlight: highlight
                ))
            }
        }
        return segments
    }

    // MARK: - Selection

    private var topNodes: [VaultNote] {
        inventory.notes
            .map { note in
                (note, inventory.adjacencyList[note.title.lowercased()]?.count ?? 0)
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return a.0.modifiedDate > b.0.modifiedDate
            }
            .prefix(36)
            .map(\.0)
    }

    private var edgeCount: Int {
        topNodes.reduce(0) { sum, note in
            sum + note.wikilinks.filter { link in
                topNodes.contains { $0.title.lowercased() == link.lowercased() }
            }.count
        }
    }

    private func radius(for connections: Int) -> CGFloat {
        switch connections {
        case 0...1: 5
        case 2...3: 7
        case 4...6: 9
        case 7...10: 11
        default: 13
        }
    }

    private func color(for note: VaultNote) -> Color {
        switch note.paraCategory {
        case .session:  Color(red: 0.70, green: 0.53, blue: 1.0)
        case .system:   Color.hydraAccent
        case .project:  Color(red: 0.92, green: 0.58, blue: 0.35)
        case .concept:  Color(red: 0.93, green: 0.78, blue: 0.40)
        case .journal, .daily: Color(red: 0.55, green: 0.52, blue: 0.66)
        case .resource: Color(red: 0.45, green: 0.78, blue: 0.62)
        default:        Color(red: 0.45, green: 0.40, blue: 0.55)
        }
    }
}
