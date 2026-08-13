import SwiftUI

// MARK: - Hydra Motion

/// Animation timing curves matching the Hydra design system.
/// Same timing, same feel — purple instead of teal.
enum HydraMotion {
    static let pulse   = Animation.easeInOut(duration: 1.2).repeatForever()
    static let breathe = Animation.easeInOut(duration: 1.6).repeatForever()
    static let orbit   = Animation.linear(duration: 7).repeatForever(autoreverses: false)
    static let sweep   = Animation.linear(duration: 2).repeatForever(autoreverses: false)
    static let wave    = Animation.easeInOut(duration: 0.5).repeatForever()

    static func spring(_ bounce: Double = 0.5, _ duration: Double = 0.5) -> Animation {
        .spring(duration: duration, bounce: bounce)
    }
}

// MARK: - Hydra Surface

/// Deep-space void background with a faint purple glow wash.
/// The deep-space surface adapted to purple.
struct HydraSurface: View {
    var body: some View {
        Color.hydraVoid.overlay(
            RadialGradient(
                colors: [Color.hydraAccent.opacity(0.10), .clear],
                center: .center, startRadius: 4, endRadius: 160
            )
        )
    }
}

// MARK: - Live Pulse

/// Health & liveness — the heartbeat of every status dot.
struct HydraLivePulse: View {
    var color: Color = Color.hydraAccent
    var size: CGFloat = 16
    @State private var on = false

    var body: some View {
        Circle().fill(color)
            .frame(width: size, height: size)
            .shadow(color: color, radius: on ? 12 : 3)
            .opacity(on ? 0.45 : 1)
            .scaleEffect(on ? 0.92 : 1)
            .animation(HydraMotion.pulse, value: on)
            .onAppear { on = true }
    }
}

// MARK: - Breathing Ring

/// The core at rest — a slow expanding halo.
struct HydraBreathingRing: View {
    var color: Color = Color.hydraAccent
    @State private var open = false

    var body: some View {
        Circle().stroke(color, lineWidth: 1.5)
            .frame(width: 46, height: 46)
            .scaleEffect(open ? 1.18 : 0.85)
            .opacity(open ? 0.25 : 0.95)
            .animation(HydraMotion.breathe, value: open)
            .onAppear { open = true }
    }
}

// MARK: - Orbiting Satellite

/// A node circling the core — background work in flight.
struct HydraOrbitingSatellite: View {
    var radius: CGFloat = 26
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().fill(Color.hydraAccent).frame(width: 12, height: 12)
                .shadow(color: Color.hydraAccent, radius: 8)
            Circle().fill(Color.hydraGlow).frame(width: 6, height: 6)
                .shadow(color: Color.hydraGlow, radius: 6)
                .offset(y: -radius)
                .rotationEffect(.degrees(spin ? 360 : 0))
        }
        .animation(HydraMotion.orbit, value: spin)
        .onAppear { spin = true }
    }
}

// MARK: - Recall Waveform

/// Staggered bars for streaming inference or memory recall.
struct HydraRecallWaveform: View {
    var bars: Int = 5
    @State private var tall = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<bars, id: \.self) { i in
                Capsule().fill(Color.hydraAccent)
                    .frame(width: 4, height: 26)
                    .scaleEffect(y: tall ? 1 : 0.3)
                    .animation(HydraMotion.wave.delay(Double(i) * 0.1), value: tall)
            }
        }
        .onAppear { tall = true }
    }
}

// MARK: - Scan Sweep

/// A comet-tail arc for scans, syncs, and provider resolution.
struct HydraScanSweep: View {
    @State private var spin = false

    var body: some View {
        Circle().trim(from: 0, to: 0.28)
            .stroke(
                AngularGradient(colors: [.clear, Color.hydraAccent, Color.hydraGlow], center: .center),
                style: StrokeStyle(lineWidth: 4, lineCap: .round)
            )
            .frame(width: 44, height: 44)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(HydraMotion.sweep, value: spin)
            .onAppear { spin = true }
    }
}

// MARK: - HUD Core

/// The signature — breathe + orbit + glow stacked into one token.
struct HydraHUDCore: View {
    var body: some View {
        ZStack {
            HydraBreathingRing()
            HydraOrbitingSatellite(radius: 30)
            Circle().fill(Color.hydraAccent).frame(width: 14, height: 14)
                .shadow(color: Color.hydraAccent, radius: 10)
        }
        .frame(width: 62, height: 62)
    }
}

// MARK: - Fleet Constellation

/// Sources coming online, phase-offset so the grid shimmers.
struct HydraFleetConstellation: View {
    var columns: Int = 4
    @State private var lit = false

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(10), spacing: 8), count: columns),
            spacing: 8
        ) {
            ForEach(0..<(columns * columns), id: \.self) { i in
                RoundedRectangle(cornerRadius: 2).fill(Color.hydraAccent)
                    .frame(width: 8, height: 8)
                    .opacity(lit ? 0.9 : 0.18)
                    .animation(HydraMotion.pulse.delay(Double(i) * 0.06), value: lit)
            }
        }
        .fixedSize()
        .onAppear { lit = true }
    }
}

// MARK: - Shimmer Skeleton

/// Loading placeholders — a purple sheen crossing redacted rows.
struct HydraShimmerSkeleton: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.hydraAccent.opacity(0.12))
                    .frame(width: i == 2 ? 74 : 124, height: 10)
                    .overlay(
                        LinearGradient(colors: [.clear, Color.hydraGlow.opacity(0.5), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: 60)
                            .offset(x: phase * 124)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    )
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 2 }
        }
    }
}

// MARK: - Glow Modifier

/// Purple glow shadow for interactive elements.
struct HydraGlow: ViewModifier {
    var color: Color = Color.hydraAccent
    var radius: CGFloat = 8
    var isActive: Bool = true

    func body(content: Content) -> some View {
        content.shadow(color: isActive ? color.opacity(0.5) : .clear, radius: radius)
    }
}

extension View {
    func hydraGlow(_ color: Color = Color.hydraAccent, radius: CGFloat = 8, active: Bool = true) -> some View {
        modifier(HydraGlow(color: color, radius: radius, isActive: active))
    }
}
