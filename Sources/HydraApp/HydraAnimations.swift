import SwiftUI

// MARK: - Motion Tokens
// Motion timing tokens.

enum Motion {
    static let pulse = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)
    static let breathe = Animation.easeInOut(duration: 3.2).repeatForever(autoreverses: true)
    static let orbit = Animation.linear(duration: 6).repeatForever(autoreverses: false)
    static let sweep = Animation.linear(duration: 2.2).repeatForever(autoreverses: false)
    static let wave = Animation.easeInOut(duration: 0.7).repeatForever(autoreverses: true)
    static let spring = Animation.spring(duration: 0.45, bounce: 0.3)
    static let quickSpring = Animation.spring(duration: 0.25, bounce: 0.2)
    static let slowGlow = Animation.easeInOut(duration: 2.5).repeatForever(autoreverses: true)
}

// MARK: - Core Animations (purple retune)

/// Health & liveness — the heartbeat of every status dot.
struct HydraLivePulse: View {
    var color: Color = .hydraLive
    var size: CGFloat = 16
    @State private var on = false

    var body: some View {
        Circle().fill(color)
            .frame(width: size, height: size)
            .shadow(color: color, radius: on ? 12 : 3)
            .opacity(on ? 0.45 : 1)
            .scaleEffect(on ? 0.92 : 1)
            .animation(Motion.pulse, value: on)
            .onAppear { on = true }
    }
}

/// The core at rest — a slow expanding purple halo.
struct HydraBreathingRing: View {
    var color: Color = .hydraAccent
    @State private var open = false

    var body: some View {
        Circle().stroke(color, lineWidth: 1.5)
            .frame(width: 46, height: 46)
            .scaleEffect(open ? 1.18 : 0.85)
            .opacity(open ? 0.25 : 0.95)
            .animation(Motion.breathe, value: open)
            .onAppear { open = true }
    }
}

/// A node circling the core — background work in flight.
struct HydraOrbitingSatellite: View {
    var radius: CGFloat = 26
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().fill(Color.hydraAccent).frame(width: 12, height: 12)
                .shadow(color: .hydraAccent, radius: 8)
            Circle().fill(Color.hydraGlow).frame(width: 6, height: 6)
                .shadow(color: .hydraGlow, radius: 6)
                .offset(y: -radius)
                .rotationEffect(.degrees(spin ? 360 : 0))
        }
        .animation(Motion.orbit, value: spin)
        .onAppear { spin = true }
    }
}

/// Staggered bars for streaming inference or memory recall.
struct HydraRecallWaveform: View {
    var bars: Int = 5
    var color: Color = .hydraAccent
    @State private var tall = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<bars, id: \.self) { i in
                Capsule().fill(color)
                    .frame(width: 4, height: 26)
                    .scaleEffect(y: tall ? 1 : 0.3)
                    .animation(Motion.wave.delay(Double(i) * 0.1), value: tall)
            }
        }
        .onAppear { tall = true }
    }
}

/// A comet-tail arc for scans, syncs, and provider resolution.
struct HydraScanSweep: View {
    @State private var spin = false

    var body: some View {
        Circle().trim(from: 0, to: 0.28)
            .stroke(
                AngularGradient(colors: [.clear, .hydraAccent, .hydraGlow], center: .center),
                style: StrokeStyle(lineWidth: 4, lineCap: .round)
            )
            .frame(width: 44, height: 44)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(Motion.sweep, value: spin)
            .onAppear { spin = true }
    }
}

/// The signature — breathe + orbit + glow stacked into one token.
struct HydraCore: View {
    var body: some View {
        ZStack {
            HydraBreathingRing()
            HydraOrbitingSatellite(radius: 30)
            Circle().fill(Color.hydraAccent).frame(width: 14, height: 14)
                .shadow(color: .hydraAccent, radius: 10)
        }
        .frame(width: 62, height: 62)
    }
}

/// Fleet members coming online, phase-offset so the grid shimmers.
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
                    .animation(Motion.pulse.delay(Double(i) * 0.06), value: lit)
            }
        }
        .fixedSize()
        .onAppear { lit = true }
    }
}

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
                        LinearGradient(colors: [.clear, .hydraGlow.opacity(0.5), .clear],
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

// MARK: - Wild Animations (purple retune)

/// A burst of particles launching outward and fading — completions.
struct HydraFireworks: View {
    @State private var go = false

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Circle().fill(Color.hydraGlow).frame(width: 5, height: 5)
                    .shadow(color: .hydraAccent, radius: 4)
                    .offset(x: go ? cos(angle(i)) * 34 : 0, y: go ? sin(angle(i)) * 34 : 0)
                    .opacity(go ? 0 : 1)
            }
        }
        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: go)
        .onAppear { go = true }
    }

    private func angle(_ i: Int) -> Double { Double(i) / 8 * 2 * .pi }
}

/// A sheen travelling across a label — the invitation to act.
struct HydraSlideToAct: View {
    var text: String = "slide to hydrate"
    @State private var phase: CGFloat = -1

    var body: some View {
        Text(text)
            .font(HydraTheme.mono(.callout, weight: .medium))
            .foregroundStyle(Color.hydraMuted)
            .overlay(
                LinearGradient(colors: [.clear, .hydraGlow, .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 64)
                    .offset(x: phase * 130)
                    .mask(Text(text).font(HydraTheme.mono(.callout, weight: .medium)))
            )
            .padding(.horizontal, 16).padding(.vertical, 9)
            .overlay(Capsule().stroke(Color.hydraAccent.opacity(0.3)))
            .onAppear {
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { phase = 1.4 }
            }
    }
}

/// A digit fading up and out as a counter ticks — live totals.
struct HydraNumericCrossfade: View {
    @State private var value = 428
    private let timer = Timer.publish(every: 1.4, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(value, format: .number.grouping(.never))
            .font(.system(size: 30, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.hydraGlow)
            .contentTransition(.numericText(value: Double(value)))
            .onReceive(timer) { _ in withAnimation(.easeInOut) { value += 7 } }
    }
}

// MARK: - Animation Gallery View (for snapshot + visual proof)

/// A gallery showing all Hydra animations side-by-side on the obsidian ground.
struct HydraAnimationGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Hydra Animations")
                    .font(HydraTheme.display(.largeTitle))
                    .foregroundStyle(Color.hydraInk)
                Text("Motion system")
                    .font(HydraTheme.mono(.subheadline))
                    .foregroundStyle(Color.hydraMuted)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    animCard("LivePulse", "heartbeat status") { HydraLivePulse() }
                    animCard("BreathingRing", "idle core") { HydraBreathingRing() }
                    animCard("OrbitingSatellite", "work in flight") { HydraOrbitingSatellite() }
                    animCard("RecallWaveform", "streaming recall") { HydraRecallWaveform() }
                    animCard("ScanSweep", "scanning source") { HydraScanSweep() }
                    animCard("HUDCore", "signature token") { HydraCore() }
                    animCard("Fireworks", "completion burst") { HydraFireworks() }
                    animCard("ShimmerSkeleton", "loading state") { HydraShimmerSkeleton() }
                    animCard("FleetConstellation", "agents online") { HydraFleetConstellation(columns: 4) }
                    animCard("SlideToAct", "action prompt") { HydraSlideToAct() }
                    animCard("NumericCrossfade", "live counter") { HydraNumericCrossfade() }
                }
                .padding(.bottom, 32)
            }
            .padding(24)
        }
        .background(Color.hydraVoid)
    }

    @ViewBuilder
    private func animCard<Content: View>(_ title: String, _ subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) {
            content()
            VStack(spacing: 2) {
                Text(title)
                    .font(HydraTheme.mono(.caption, weight: .semibold))
                    .foregroundStyle(Color.hydraInk)
                Text(subtitle)
                    .font(HydraTheme.mono(.caption2))
                    .foregroundStyle(Color.hydraMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.hydraPanel)
        .overlay(RoundedRectangle(cornerRadius: HydraTheme.cornerRadius).strokeBorder(Color.hydraLine, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: HydraTheme.cornerRadius))
    }
}
