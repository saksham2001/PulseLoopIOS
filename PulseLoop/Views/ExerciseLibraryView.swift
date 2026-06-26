import SwiftUI
import SwiftData

// MARK: - Exercise Library Picker

/// Searchable, A–Z sectioned exercise library with group/equipment filters,
/// info detail, and multi-add — mirroring a dedicated strength app's picker.
struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    /// Called with the chosen catalog exercises when the user taps "Add".
    var onAdd: ([Exercise]) -> Void

    @State private var search = ""
    @State private var groupFilter: MuscleGroup?
    @State private var equipmentFilter: Equipment?
    @State private var selected: Set<UUID> = []
    @State private var showGroupSheet = false
    @State private var showEquipmentSheet = false
    @State private var showCustom = false
    @State private var infoExercise: Exercise?

    private var filtered: [Exercise] {
        exercises.filter { ex in
            let matchesSearch = search.isEmpty || ex.name.localizedCaseInsensitiveContains(search) || ex.equipment.rawValue.localizedCaseInsensitiveContains(search)
            let matchesGroup = groupFilter == nil || ex.muscleGroup == groupFilter
            let matchesEquipment = equipmentFilter == nil || ex.equipment == equipmentFilter
            return matchesSearch && matchesGroup && matchesEquipment
        }
    }

    private var customExercises: [Exercise] {
        filtered.filter(\.isCustom)
    }

    /// A→Z sections keyed by the first letter of the name.
    private struct LetterSection: Identifiable {
        let letter: String
        let items: [Exercise]
        var id: String { letter }
    }

    private var sections: [LetterSection] {
        let nonCustom = filtered.filter { !$0.isCustom }
        let grouped = Dictionary(grouping: nonCustom) { String($0.name.prefix(1)).uppercased() }
        return grouped.keys.sorted().map { key in
            LetterSection(letter: key, items: grouped[key]!.sorted { $0.name < $1.name || ($0.name == $1.name && $0.equipment.rawValue < $1.equipment.rawValue) })
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                filterRow
                Divider().overlay(PulseColors.borderHairline)
                listContent
            }
            .background(PulseColors.background)
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PulseColors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { commit() }
                        .font(PulseFont.bodySemibold(16))
                        .foregroundStyle(selected.isEmpty ? PulseColors.textMuted : PulseColors.accent)
                        .disabled(selected.isEmpty)
                }
            }
            .sheet(isPresented: $showGroupSheet) {
                FilterPickerSheet(title: "Muscle group", options: MuscleGroup.allCases.map { ($0.rawValue, $0) }, selection: $groupFilter)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showEquipmentSheet) {
                FilterPickerSheet(title: "Equipment", options: Equipment.allCases.map { ($0.rawValue, $0) }, selection: $equipmentFilter)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showCustom) {
                AddCustomExerciseSheet()
                    .presentationDetents([.medium])
            }
            .sheet(item: $infoExercise) { ex in
                ExerciseInfoSheet(exercise: ex)
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PulseColors.textMuted)
            TextField("Search", text: $search)
                .font(PulseFont.bodyMedium(16))
                .foregroundStyle(PulseColors.textPrimary)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PulseColors.textMuted)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(PulseColors.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var filterRow: some View {
        HStack(spacing: 10) {
            FilterChip(
                title: groupFilter?.rawValue ?? "All groups",
                isActive: groupFilter != nil,
                action: { showGroupSheet = true }
            )
            FilterChip(
                title: equipmentFilter?.rawValue ?? "All equipment",
                isActive: equipmentFilter != nil,
                action: { showEquipmentSheet = true }
            )
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: List

    private var listContent: some View {
        List {
            customSection
            ForEach(sections) { section in
                letterSection(section)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PulseColors.background)
        .overlay {
            if filtered.isEmpty {
                emptyState
            }
        }
    }

    @ViewBuilder
    private var customSection: some View {
        Section {
            Button {
                HapticService.impact(.light)
                showCustom = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PulseColors.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(PulseColors.fillSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
                    Text("Add custom exercise")
                        .font(PulseFont.bodySemibold(16))
                        .foregroundStyle(PulseColors.textPrimary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(PulseColors.background)

            ForEach(customExercises) { ex in
                exerciseRow(ex)
            }
        } header: {
            sectionHeader("Custom")
        }
    }

    @ViewBuilder
    private func letterSection(_ section: LetterSection) -> some View {
        Section {
            ForEach(section.items) { ex in
                exerciseRow(ex)
            }
        } header: {
            sectionHeader(section.letter)
        }
    }

    private func sectionHeader(_ text: String) -> Text {
        Text(text)
            .font(PulseFont.bodyMedium(12))
            .tracking(0.4)
            .foregroundStyle(PulseColors.textMuted)
    }

    private func exerciseRow(_ ex: Exercise) -> AnyView {
        AnyView(
            ExerciseLibraryRow(
                exercise: ex,
                isSelected: selected.contains(ex.id),
                onInfo: { infoExercise = ex },
                onToggle: { toggleSelect(ex) }
            )
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparatorTint(PulseColors.borderHairline)
            .listRowBackground(PulseColors.background)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(PulseColors.textMuted)
            InlineEmptyState(
                title: "No exercises match",
                message: "Try a different search or clear the filters."
            )
        }
        .padding(.vertical, 24)
        .background(PulseColors.background)
    }

    private func toggleSelect(_ ex: Exercise) {
        HapticService.selection()
        if selected.contains(ex.id) { selected.remove(ex.id) } else { selected.insert(ex.id) }
    }

    private func commit() {
        let chosen = exercises.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        HapticService.success()
        onAdd(chosen)
        dismiss()
    }
}

// MARK: - Exercise Library Row

private struct ExerciseLibraryRow: View {
    let exercise: Exercise
    let isSelected: Bool
    let onInfo: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: exercise.equipment.symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(PulseColors.textSecondary)
                .frame(width: 44, height: 44)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(PulseFont.bodySemibold(16))
                    .foregroundStyle(PulseColors.textPrimary)
                Text(exercise.equipment.rawValue)
                    .font(PulseFont.bodyMedium(13))
                    .foregroundStyle(PulseColors.textMuted)
            }

            Spacer()

            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(PulseColors.textMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Info about \(exercise.name)")

            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? PulseColors.accent : PulseColors.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(isSelected ? PulseColors.accent.opacity(0.12) : PulseColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous)
                            .stroke(isSelected ? PulseColors.accent : PulseColors.borderStrong, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Remove \(exercise.name)" : "Add \(exercise.name)")
        }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(PulseFont.bodySemibold(14))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(isActive ? PulseColors.accent : PulseColors.textSecondary)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(isActive ? PulseColors.accent.opacity(0.1) : PulseColors.background)
            .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous)
                    .stroke(isActive ? PulseColors.accent.opacity(0.4) : PulseColors.borderStrong, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter Picker Sheet

private struct FilterPickerSheet<T: Equatable>: View {
    let title: String
    let options: [(String, T)]
    @Binding var selection: T?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selection = nil
                    dismiss()
                } label: {
                    HStack {
                        Text("All")
                            .foregroundStyle(PulseColors.textPrimary)
                        Spacer()
                        if selection == nil {
                            Image(systemName: "checkmark").foregroundStyle(PulseColors.accent)
                        }
                    }
                }
                .listRowBackground(PulseColors.background)
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button {
                        selection = option.1
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.0)
                                .foregroundStyle(PulseColors.textPrimary)
                            Spacer()
                            if selection == option.1 {
                                Image(systemName: "checkmark").foregroundStyle(PulseColors.accent)
                            }
                        }
                    }
                    .listRowBackground(PulseColors.background)
                }
            }
            .font(PulseFont.bodyMedium(16))
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(PulseColors.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Exercise Info Sheet

struct ExerciseInfoSheet: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        Image(systemName: exercise.equipment.symbol)
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(PulseColors.textSecondary)
                            .frame(width: 64, height: 64)
                            .background(PulseColors.fillSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name)
                                .font(PulseFont.titleMedium(22))
                                .foregroundStyle(PulseColors.textPrimary)
                            Text(exercise.equipment.rawValue)
                                .font(PulseFont.bodyMedium(14))
                                .foregroundStyle(PulseColors.textMuted)
                        }
                    }

                    HStack(spacing: 8) {
                        StatusChip(label: exercise.muscleGroup.rawValue, style: .neutral, icon: "figure.strengthtraining.traditional")
                        StatusChip(label: exercise.equipment.rawValue, style: .neutral, icon: "dumbbell.fill")
                        if exercise.isCustom {
                            StatusChip(label: "Custom", style: .success, icon: "person.fill")
                        }
                    }

                    if let instructions = exercise.instructions, !instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            EyebrowLabel("HOW TO")
                            Text(instructions)
                                .font(PulseFont.body(16))
                                .foregroundStyle(PulseColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                }
                .padding(20)
            }
            .background(PulseColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Add Custom Exercise

struct AddCustomExerciseSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var group: MuscleGroup = .chest
    @State private var equipment: Equipment = .barbell

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise name", text: $name)
                    Picker("Muscle group", selection: $group) {
                        ForEach(MuscleGroup.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(PulseColors.background)
            .navigationTitle("Custom Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let ex = Exercise(name: trimmed, muscleGroup: group, equipment: equipment, isCustom: true)
        modelContext.insert(ex)
        try? modelContext.save()
        HapticService.success()
        dismiss()
    }
}
