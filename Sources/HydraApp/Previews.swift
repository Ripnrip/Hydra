import SwiftUI

// MARK: - Xcode Previews
// Every major view and component gets a #Preview in both light and dark mode.
// These render live in Xcode's canvas — no build required.

// MARK: - Component Previews

#Preview("Tag Chip — Dark") {
    HydraTagChip(label: "project/hydra", color: .hydraAccent)
        .padding()
        .background(Color.hydraVoid)
        .preferredColorScheme(.dark)
}

#Preview("Tag Chip — Light") {
    HydraTagChip(label: "project/hydra", color: .hydraAccent)
        .padding()
        .background(Color.hydraVoid)
        .preferredColorScheme(.light)
}

#Preview("Stat Card") {
    HydraStatCard(title: "Vault Notes", value: "155", icon: "doc.text.fill")
        .padding()
        .background(Color.hydraVoid)
        .preferredColorScheme(.dark)
}

#Preview("Glow Button") {
    HydraButton("Hydrate", icon: "drop.fill") {}
        .padding()
        .background(Color.hydraVoid)
        .preferredColorScheme(.dark)
}

#Preview("Status Dot") {
    VStack(spacing: 12) {
        HydraStatusDot(color: .hydraLive, pulsing: true)
        HydraStatusDot(color: .hydraAccent, pulsing: true)
        HydraStatusDot(color: .hydraAlert)
    }
    .padding()
    .background(Color.hydraVoid)
    .preferredColorScheme(.dark)
}

#Preview("Hydra Panel") {
    HydraPanel(title: "Source", icon: "folder.fill") {
        Text("Content goes here")
            .foregroundStyle(Color.hydraInk)
    }
    .padding()
    .background(Color.hydraVoid)
    .preferredColorScheme(.dark)
}

// MARK: - Animation Previews

#Preview("Live Pulse") {
    HydraLivePulse()
        .padding(40)
        .background(Color.hydraVoid)
        .preferredColorScheme(.dark)
}

#Preview("Scan Sweep") {
    HydraScanSweep()
        .padding(40)
        .background(Color.hydraVoid)
        .preferredColorScheme(.dark)
}

#Preview("Recall Waveform") {
    HydraRecallWaveform()
        .padding(40)
        .background(Color.hydraVoid)
        .preferredColorScheme(.dark)
}

#Preview("Shimmer Skeleton") {
    HydraShimmerSkeleton()
        .padding(40)
        .background(Color.hydraVoid)
        .preferredColorScheme(.dark)
}

// MARK: - Panel Previews

#Preview("Hydration — Dark") {
    HydrationView()
        .preferredColorScheme(.dark)
}

#Preview("Hydration — Light") {
    HydrationView()
        .preferredColorScheme(.light)
}

#Preview("Full App — Dark") {
    ContentView()
        .frame(width: 1000, height: 650)
        .preferredColorScheme(.dark)
}

#Preview("Full App — Light") {
    ContentView()
        .frame(width: 1000, height: 650)
        .preferredColorScheme(.light)
}

#Preview("Backfill Config — Dark") {
    BackfillConfigView()
        .preferredColorScheme(.dark)
}

#Preview("Relationship Graph") {
    RelationshipGraphView()
        .preferredColorScheme(.dark)
}

#Preview("E2E Flow — Classified") {
    E2EHydrationFlowView(fixedStep: .classified)
        .preferredColorScheme(.dark)
}

#Preview("E2E Flow — Complete") {
    E2EHydrationFlowView(fixedStep: .complete)
        .preferredColorScheme(.dark)
}
