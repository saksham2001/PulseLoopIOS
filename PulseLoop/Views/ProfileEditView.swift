import SwiftUI
import SwiftData
import HealthKit

struct ProfileEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Binding var path: NavigationPath

    @State private var nameText = ""
    @State private var ageText = ""
    @State private var selectedSex = "not set"
    
    // Metric height
    @State private var heightCmText = ""
    
    // Imperial height
    @State private var heightFeetText = ""
    @State private var heightInchesText = ""
    
    // Weight (displayed as kg or lbs based on setting)
    @State private var weightText = ""
    
    // UI state
    @State private var importErrorMessage: String? = nil
    @State private var importSuccessMessage: String? = nil
    @State private var isImporting = false

    private var useImperialUnits: Bool {
        WorkoutAppGroup.useImperialUnits
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // Form Container
                VStack(alignment: .leading, spacing: 18) {
                    
                    ProfileInputField(label: "Name", placeholder: "Enter your name", text: $nameText)
                    
                    HStack(spacing: 16) {
                        ProfileInputField(label: "Age", placeholder: "Age", text: $ageText, keyboardType: .numberPad)
                            .frame(maxWidth: 120)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sex")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(PulseColors.textSecondary)
                                .textCase(.uppercase)
                            
                            Picker("Sex", selection: $selectedSex) {
                                Text("Not Set").tag("not set")
                                Text("Male").tag("male")
                                Text("Female").tag("female")
                                Text("Other").tag("other")
                            }
                            .pickerStyle(.segmented)
                            .frame(height: 44)
                        }
                    }
                    
                    // Height input based on imperial setting
                    if useImperialUnits {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Height")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(PulseColors.textSecondary)
                                .textCase(.uppercase)
                            
                            HStack(spacing: 12) {
                                HStack {
                                    TextField("FT", text: $heightFeetText)
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(PulseColors.textPrimary)
                                    Text("ft")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(PulseColors.textMuted)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(PulseColors.cardSoft, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(PulseColors.borderSubtle, lineWidth: 1))
                                
                                HStack {
                                    TextField("IN", text: $heightInchesText)
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(PulseColors.textPrimary)
                                    Text("in")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(PulseColors.textMuted)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(PulseColors.cardSoft, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(PulseColors.borderSubtle, lineWidth: 1))
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Height")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(PulseColors.textSecondary)
                                .textCase(.uppercase)
                            
                            HStack {
                                TextField("Height", text: $heightCmText)
                                    .keyboardType(.decimalPad)
                                    .foregroundStyle(PulseColors.textPrimary)
                                Spacer()
                                Text("cm")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(PulseColors.textMuted)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(PulseColors.cardSoft, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(PulseColors.borderSubtle, lineWidth: 1))
                        }
                    }
                    
                    // Weight input based on imperial setting
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Weight")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PulseColors.textSecondary)
                            .textCase(.uppercase)
                        
                        HStack {
                            TextField("Weight", text: $weightText)
                                .keyboardType(.decimalPad)
                                .foregroundStyle(PulseColors.textPrimary)
                            Spacer()
                            Text(useImperialUnits ? "lbs" : "kg")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(PulseColors.textMuted)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(PulseColors.cardSoft, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(PulseColors.borderSubtle, lineWidth: 1))
                    }
                }
                .padding(20)
                .background(PulseColors.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
                
                // Apple Health Integration Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.red)
                        Text("Apple Health Sync")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(PulseColors.textPrimary)
                    }
                    
                    Text("Import age, sex, height, and weight directly from Apple Health. Name is not syncable due to privacy limits.")
                        .font(.system(size: 13))
                        .foregroundStyle(PulseColors.textSecondary)
                        .lineSpacing(4)
                    
                    SecondaryButton(
                        title: isImporting ? "Syncing..." : "Sync from Apple Health",
                        systemImage: "arrow.down.heart.fill"
                    ) {
                        importFromAppleHealth()
                    }
                    .disabled(isImporting)
                    
                    if let success = importSuccessMessage {
                        Text(success)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PulseColors.success)
                    }
                    
                    if let error = importErrorMessage {
                        Text(error)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
                .background(PulseColors.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
                
                // Save Button
                PrimaryButton(title: "Save Profile", systemImage: "checkmark.circle.fill") {
                    saveProfile()
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .background(PulseColors.background.ignoresSafeArea())
        .navigationTitle("Edit Profile")
        .onAppear(perform: loadProfileData)
    }

    // MARK: - Helper Methods

    private func loadProfileData() {
        guard let profile = profiles.first else { return }
        nameText = profile.name ?? ""
        ageText = profile.age.map { "\($0)" } ?? ""
        selectedSex = profile.sex ?? "not set"
        
        if let h = profile.heightCm {
            if useImperialUnits {
                let totalInches = h / 2.54
                let ft = Int(totalInches) / 12
                let inch = Int(totalInches.rounded()) % 12
                heightFeetText = "\(ft)"
                heightInchesText = "\(inch)"
            } else {
                heightCmText = String(format: "%.1f", h)
            }
        }
        
        if let w = profile.weightKg {
            if useImperialUnits {
                let lbs = w * 2.20462
                weightText = String(format: "%.1f", lbs)
            } else {
                weightText = String(format: "%.1f", w)
            }
        }
    }

    private func importFromAppleHealth() {
        isImporting = true
        importErrorMessage = nil
        importSuccessMessage = nil
        
        Task { @MainActor in
            do {
                try await HealthSyncService.shared.requestAuthorization()
                let data = await HealthSyncService.shared.fetchUserProfileData()
                
                var importedCount = 0
                
                if let age = data.age {
                    ageText = "\(age)"
                    importedCount += 1
                }
                if let sex = data.sex {
                    selectedSex = sex
                    importedCount += 1
                }
                
                if let heightCm = data.heightCm {
                    importedCount += 1
                    if useImperialUnits {
                        let totalInches = heightCm / 2.54
                        let ft = Int(totalInches) / 12
                        let inch = Int(totalInches.rounded()) % 12
                        heightFeetText = "\(ft)"
                        heightInchesText = "\(inch)"
                    } else {
                        heightCmText = String(format: "%.1f", heightCm)
                    }
                }
                
                if let weightKg = data.weightKg {
                    importedCount += 1
                    if useImperialUnits {
                        let lbs = weightKg * 2.20462
                        weightText = String(format: "%.1f", lbs)
                    } else {
                        weightText = String(format: "%.1f", weightKg)
                    }
                }
                
                isImporting = false
                if importedCount > 0 {
                    importSuccessMessage = "Successfully imported \(importedCount) metric(s) from Apple Health!"
                } else {
                    importErrorMessage = "No profile data was found in Apple Health."
                }
            } catch {
                isImporting = false
                importErrorMessage = "Health access denied or failed: \(error.localizedDescription)"
            }
        }
    }

    private func saveProfile() {
        let profile = profiles.first ?? UserProfile()
        profile.name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.age = Int(ageText)
        profile.sex = selectedSex
        
        // Height Conversion & Saving
        if useImperialUnits {
            let ft = Double(heightFeetText) ?? 0.0
            let inch = Double(heightInchesText) ?? 0.0
            if ft > 0 || inch > 0 {
                profile.heightCm = (ft * 12 + inch) * 2.54
            }
        } else {
            if let h = Double(heightCmText) {
                profile.heightCm = h
            }
        }
        
        // Weight Conversion & Saving
        if let w = Double(weightText) {
            if useImperialUnits {
                profile.weightKg = w / 2.20462
            } else {
                profile.weightKg = w
            }
        }
        
        profile.updatedAt = Date()
        
        if profiles.isEmpty {
            modelContext.insert(profile)
        }
        
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Input Field Component

struct ProfileInputField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PulseColors.textSecondary)
                .textCase(.uppercase)
            
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(PulseColors.cardSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
                .foregroundStyle(PulseColors.textPrimary)
        }
    }
}
