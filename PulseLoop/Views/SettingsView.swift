import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RingBLEClient.self) private var ble
    @Environment(RingSyncCoordinator.self) private var coordinator
    @Query private var profiles: [UserProfile]
    @Binding var path: NavigationPath
    @State private var diagnosticsURL: URL?

    @AppStorage("useImperialUnits", store: UserDefaults(suiteName: WorkoutAppGroup.suite))
    private var useImperialUnits = false

    @AppStorage("useAdvancedCalories", store: UserDefaults(suiteName: WorkoutAppGroup.suite))
    private var useAdvancedCalories = false

    private var appVersionLabel: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private var lastSyncedLabel: String {
        guard let date = coordinator.lastSyncAt else { return "Not yet" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionHeader(title: "Profile", action: "Edit")
                    .onTapGesture {
                        path.append(AppRoute.profileEdit)
                    }
                
                Button {
                    path.append(AppRoute.profileEdit)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(profiles.first?.name ?? "Not set")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(PulseColors.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(PulseColors.textMuted)
                        }
                        
                        if let profile = profiles.first, profile.age != nil || profile.heightCm != nil || profile.weightKg != nil {
                            HStack(spacing: 16) {
                                if let age = profile.age {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Age").font(.system(size: 10, weight: .bold)).foregroundStyle(PulseColors.textMuted).textCase(.uppercase)
                                        Text("\(age) yrs").font(.system(size: 14, weight: .medium)).foregroundStyle(PulseColors.textSecondary)
                                    }
                                }
                                
                                if let h = profile.heightCm {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Height").font(.system(size: 10, weight: .bold)).foregroundStyle(PulseColors.textMuted).textCase(.uppercase)
                                        Text(heightDisplayString(h)).font(.system(size: 14, weight: .medium)).foregroundStyle(PulseColors.textSecondary)
                                    }
                                }
                                
                                if let w = profile.weightKg {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Weight").font(.system(size: 10, weight: .bold)).foregroundStyle(PulseColors.textMuted).textCase(.uppercase)
                                        Text(weightDisplayString(w)).font(.system(size: 14, weight: .medium)).foregroundStyle(PulseColors.textSecondary)
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(16)
                    .background(PulseColors.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(PulseColors.borderSubtle, lineWidth: 1))
                }
                .buttonStyle(.plain)

                SectionHeader(title: "Ring", action: nil)
                if ble.state == .connected {
                    StatusCopy(title: "Device", body: ble.activeDeviceType?.displayName ?? "Connected ring")
                    StatusCopy(title: "Battery", body: ble.batteryPercent.map { "\($0)%" } ?? "--")
                    StatusCopy(title: "Last synced", body: lastSyncedLabel)
                    SecondaryButton(title: "Sync now", systemImage: "clock.arrow.circlepath") { coordinator.syncNow() }
                    SecondaryButton(title: "Find ring", systemImage: "bell.fill") { coordinator.findRing() }
                    SecondaryButton(title: "Disconnect", systemImage: "xmark.circle") { ble.disconnect() }
                    SecondaryButton(title: "Forget ring", systemImage: "trash") { ble.forget() }
                } else {
                    StatusCopy(title: "Status", body: ble.state.rawValue.capitalized)
                    PrimaryButton(title: "Add a ring", systemImage: "plus.circle") {
                        path.append(AppRoute.pairing)
                    }
                    if ble.hasLastKnownRing && ble.state != .reconnecting {
                        SecondaryButton(title: "Reconnect last ring", systemImage: "arrow.clockwise") { ble.connectLastKnown() }
                        SecondaryButton(title: "Forget ring", systemImage: "trash") { ble.forget() }
                    }
                }

                CoachSettingsSection()

                SectionHeader(title: "Preferences", action: nil)
                Toggle("Use Imperial Units", isOn: $useImperialUnits)
                    .tint(PulseColors.accent)
                Toggle("Use Advanced Calories", isOn: $useAdvancedCalories)
                    .tint(PulseColors.accent)

                SectionHeader(title: "About", action: nil)
                StatusCopy(title: "Version", body: appVersionLabel)
                SecondaryButton(title: "Export diagnostics", systemImage: "square.and.arrow.up") {
                    diagnosticsURL = DiagnosticsExporter.exportFile(context: modelContext)
                }

                #if DEBUG
                SectionHeader(title: "Developer", action: nil)
                PrimaryButton(title: "Debug feed", systemImage: "ladybug") {
                    path.append(AppRoute.debug)
                }
                SecondaryButton(title: "Component gallery", systemImage: "square.grid.2x2") {
                    path.append(AppRoute.componentGallery)
                }
                #endif

                SectionHeader(title: "Data", action: nil)
                SecondaryButton(title: "Clear demo data", systemImage: "trash") {
                    SeedData.clearAll(modelContext)
                    let fresh = UserProfile()
                    fresh.onboardingCompleted = true
                    fresh.baselineCompleted = true
                    modelContext.insert(fresh)
                    try? modelContext.save()
                }
                SecondaryButton(title: "Reseed demo data", systemImage: "arrow.clockwise") {
                    SeedData.clearAll(modelContext)
                    SeedData.seedDemo(modelContext, completeOnboarding: true)
                }
            }
            .padding()
        }
        .background(PulseColors.background)
        .navigationTitle("Settings")
        .sheet(item: $diagnosticsURL) { url in
            DiagnosticsShareSheet(items: [url])
        }
    }

    private func heightDisplayString(_ cm: Double) -> String {
        if useImperialUnits {
            let totalInches = cm / 2.54
            let ft = Int(totalInches) / 12
            let inch = Int(totalInches.rounded()) % 12
            return "\(ft)'\(inch)\""
        } else {
            return String(format: "%.0f cm", cm)
        }
    }

    private func weightDisplayString(_ kg: Double) -> String {
        if useImperialUnits {
            let lbs = kg * 2.20462
            return String(format: "%.0f lbs", lbs)
        } else {
            return String(format: "%.1f kg", kg)
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Minimal UIKit share-sheet wrapper for exporting the diagnostics file.
private struct DiagnosticsShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
