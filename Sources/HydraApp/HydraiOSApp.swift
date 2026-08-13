import SwiftUI
import HydraCore
import HydraVault
import HydraHealth

// MARK: - iOS App Entry Point
// Conditionally compiled for iOS only — the macOS app uses App.swift

#if os(iOS)
import UIKit

@main
struct HydraiOSApp: App {
    var body: some Scene {
        WindowGroup {
            iOSContentView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - iOS Root View

struct iOSContentView: View {
    @State private var selectedTab: iOSTab = .hydrate
    @State private var vaultLocation: VaultLocation = .local("~/Documents/MyVault", name: "MyVault")

    var body: some View {
        TabView(selection: $selectedTab) {
            iOSHydrationView(vaultLocation: $vaultLocation)
                .tabItem { Label("Hydrate", systemImage: "drop.fill") }
                .tag(iOSTab.hydrate)

            iOSVaultBrowserView(vaultLocation: $vaultLocation)
                .tabItem { Label("Vault", systemImage: "archivebox.fill") }
                .tag(iOSTab.vault)

            iOSOracleView()
                .tabItem { Label("Oracle", systemImage: "brain.head.profile.fill") }
                .tag(iOSTab.oracle)

            iOSHealthView(vaultLocation: $vaultLocation)
                .tabItem { Label("Health", systemImage: "heart.text.square.fill") }
                .tag(iOSTab.health)
        }
        .tint(.purple)
    }
}

enum iOSTab: String, CaseIterable {
    case hydrate, vault, oracle, health
}

// MARK: - Hydration Tab

struct iOSHydrationView: View {
    @Binding var vaultLocation: VaultLocation
    @State private var sourcePath = "~/.claude/plans"
    @State private var isHydrating = false
    @State private var showVaultPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Vault location card
                    Button {
                        showVaultPicker = true
                    } label: {
                        HStack {
                            Image(systemName: vaultLocation.requiresNetwork ? "network" : "internaldrive")
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading) {
                                Text(vaultLocation.displayName)
                                    .font(.headline)
                                Text(vaultLocation.rawPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    // Source
                    VStack(alignment: .leading) {
                        Label("Source", systemImage: "square.and.arrow.down")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Source path", text: $sourcePath)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Action
                    Button {
                        isHydrating = true
                    } label: {
                        HStack {
                            Image(systemName: "drop.halffull.fill")
                            Text("Hydrate")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(isHydrating)
                }
                .padding()
            }
            .navigationTitle("Hydra")
            .sheet(isPresented: $showVaultPicker) {
                iOSVaultPicker(selected: $vaultLocation)
            }
        }
    }
}

// MARK: - Vault Picker (location resolver)

struct iOSVaultPicker: View {
    @Binding var selected: VaultLocation
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Local") {
                    Label {
                        VStack(alignment: .leading) {
                            Text("On This Device")
                            Text("Documents / iCloud Drive")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "internaldrive")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selected = .local("~/Documents/MyVault", name: "MyVault")
                        dismiss()
                    }
                }

                Section("iCloud") {
                    Label {
                        VStack(alignment: .leading) {
                            Text("iCloud Drive")
                            Text("Obsidian iCloud sync")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "icloud")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selected = .iCloud(vaultName: "MyVault")
                        dismiss()
                    }
                }

                Section("Network") {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Tailscale Host")
                            Text("Connect to a vault on your Mac/VM")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "network")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selected = .tailscale(host: "studio.local", path: "~/Documents/MyVault")
                        dismiss()
                    }
                }
            }
            .navigationTitle("Vault Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Vault Browser

struct iOSVaultBrowserView: View {
    @Binding var vaultLocation: VaultLocation

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.purple.opacity(0.6))
                Text("Vault Explorer")
                    .font(.title2.bold())
                Text("Browse and search notes in \(vaultLocation.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Vault")
        }
    }
}

// MARK: - Oracle

struct iOSOracleView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "brain.head.profile.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.purple.opacity(0.6))
                Text("Oracle")
                    .font(.title2.bold())
                Text("Query the hydrated context graph")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Oracle")
        }
    }
}

// MARK: - Health

struct iOSHealthView: View {
    @Binding var vaultLocation: VaultLocation

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.purple.opacity(0.6))
                Text("Vault Health")
                    .font(.title2.bold())
                Text("Checking: \(vaultLocation.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Health")
        }
    }
}

#endif // os(iOS)
