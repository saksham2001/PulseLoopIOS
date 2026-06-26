import SwiftUI
import SwiftData

// MARK: - Workout Builder ("New Workout")

/// Build or edit a workout template: add exercises from the library, configure
/// sets (reps × weight), and save. Matches the "New Workout" screen.
struct WorkoutBuilderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Existing template to edit, or nil to create a new one.
    var template: WorkoutTemplate?

    @State private var name: String
    @State private var draftExercises: [TemplateExercise]
    @State private var showLibrary = false
    @State private var showMenu = false

    init(template: WorkoutTemplate? = nil) {
        self.template = template
        _name = State(initialValue: template?.name ?? "New Workout")
        _draftExercises = State(initialValue: (template?.exercises ?? []).sorted { $0.order < $1.order })
    }

    private var totalSets: Int { draftExercises.reduce(0) { $0 + $1.sets.count } }
    private var canSave: Bool { !draftExercises.isEmpty && !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    titleHeader

                    if draftExercises.isEmpty {
                        emptyCard
                    } else {
                        ForEach($draftExercises) { $ex in
                            ExerciseBuilderCard(
                                exercise: $ex,
                                onRemove: { remove(ex) }
                            )
                        }
                        addMoreButton
                    }
                }
                .padding(16)
                .padding(.bottom, 120)
            }
            .background(PulseColors.canvas)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PulseColors.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(PulseColors.fillSubtle)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) { draftExercises.removeAll() } label: {
                            Label("Clear all exercises", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PulseColors.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(PulseColors.fillSubtle)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("More options")
                }
            }
            .sheet(isPresented: $showLibrary) {
                ExerciseLibraryView { chosen in
                    addExercises(chosen)
                }
            }
        }
    }

    private var titleHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Workout name", text: $name)
                .font(PulseFont.titleMedium(26))
                .foregroundStyle(PulseColors.textPrimary)
            Text("\(draftExercises.count) exercises, \(totalSets) sets")
                .font(PulseFont.bodyMedium(14))
                .foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            InlineEmptyState(
                title: "No exercises added",
                message: "Tap the \u{201C}+\u{201D} to start adding exercises to your template."
            )
            Button {
                HapticService.impact(.light)
                showLibrary = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add exercises")
                }
                .font(PulseFont.bodySemibold(15))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(height: 48)
                .background(PulseColors.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .pulseCardSurface()
    }

    private var addMoreButton: some View {
        Button {
            HapticService.impact(.light)
            showLibrary = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                Text("Add exercises")
            }
            .font(PulseFont.bodySemibold(15))
            .foregroundStyle(PulseColors.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(PulseColors.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                HapticService.impact(.light)
                showLibrary = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Exercise")
                }
                .font(PulseFont.bodySemibold(15))
                .foregroundStyle(PulseColors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(PulseColors.background)
                .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous)
                        .stroke(PulseColors.borderStrong, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            Button { save() } label: {
                Text("Save")
                    .font(PulseFont.bodySemibold(16))
                    .foregroundStyle(canSave ? .white : PulseColors.textMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(canSave ? PulseColors.accent : PulseColors.fillMuted)
                    .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: Actions

    private func addExercises(_ chosen: [Exercise]) {
        for ex in chosen {
            let te = TemplateExercise(exercise: ex, order: draftExercises.count)
            te.sets = [ExerciseSet(order: 0, reps: 10, weightKg: 0)]
            draftExercises.append(te)
        }
    }

    private func remove(_ ex: TemplateExercise) {
        draftExercises.removeAll { $0.id == ex.id }
        for (i, e) in draftExercises.enumerated() { e.order = i }
    }

    private func save() {
        guard canSave else { return }
        let tmpl = template ?? WorkoutTemplate(name: name)
        tmpl.name = name.trimmingCharacters(in: .whitespaces)
        for (i, e) in draftExercises.enumerated() { e.order = i }
        tmpl.exercises = draftExercises
        if template == nil {
            modelContext.insert(tmpl)
        }
        try? modelContext.save()
        HapticService.success()
        dismiss()
    }
}

// MARK: - Exercise Builder Card

private struct ExerciseBuilderCard: View {
    @Binding var exercise: TemplateExercise
    let onRemove: () -> Void
    @AppStorage(WeightUnit.storageKey) private var weightUnitRaw: String = WeightUnit.kg.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: exercise.equipment.symbol)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(PulseColors.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(PulseFont.bodySemibold(16))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text(exercise.equipment.rawValue)
                        .font(PulseFont.bodyMedium(12))
                        .foregroundStyle(PulseColors.textMuted)
                }
                Spacer()
                Menu {
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove exercise", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PulseColors.textMuted)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Options for \(exercise.name)")
            }
            .padding(.bottom, 6)

            setsHeaderRow

            ForEach(Array(exercise.sets.sorted { $0.order < $1.order }.enumerated()), id: \.element.id) { index, set in
                setRow(set, number: index + 1)
            }

            Button {
                HapticService.impact(.light)
                let next = ExerciseSet(order: exercise.sets.count, reps: exercise.sets.last?.reps ?? 10, weightKg: exercise.sets.last?.weightKg ?? 0)
                exercise.sets.append(next)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add set")
                }
                .font(PulseFont.bodySemibold(13))
                .foregroundStyle(PulseColors.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(14)
        .pulseCardSurface()
    }

    private var setsHeaderRow: some View {
        HStack {
            Text("SET").frame(width: 40, alignment: .leading)
            Spacer()
            Text("REPS").frame(width: 90)
            Text(unit.label.uppercased()).frame(width: 90)
        }
        .font(PulseFont.bodyMedium(11))
        .tracking(0.5)
        .foregroundStyle(PulseColors.textMuted)
        .padding(.vertical, 4)
    }

    private func setRow(_ set: ExerciseSet, number: Int) -> some View {
        HStack {
            Text("\(number)")
                .font(PulseFont.bodySemibold(15))
                .foregroundStyle(PulseColors.textSecondary)
                .frame(width: 40, alignment: .leading)
            Spacer()
            Stepperish(value: Binding(
                get: { set.reps },
                set: { set.reps = max(0, $0) }
            ), unit: nil)
            .frame(width: 90)
            DecimalField(weightKg: Binding(
                get: { set.weightKg },
                set: { set.weightKg = max(0, $0) }
            ), unit: unit)
            .frame(width: 90)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                exercise.sets.removeAll { $0.id == set.id }
            } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

// MARK: - Small numeric controls

private struct Stepperish: View {
    @Binding var value: Int
    var unit: String?

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus") { value = max(0, value - 1) }
            Text("\(value)")
                .font(PulseFont.bodySemibold(15))
                .monospacedDigit()
                .foregroundStyle(PulseColors.textPrimary)
                .frame(maxWidth: .infinity)
            stepButton("plus") { value += 1 }
        }
        .frame(height: 36)
        .background(PulseColors.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticService.selection()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(PulseColors.textSecondary)
                .frame(width: 30, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DecimalField: View {
    /// Bound to the canonical kilogram value; the field displays/edits in `unit`.
    @Binding var weightKg: Double
    let unit: WeightUnit
    @State private var text: String = ""
    /// True while we're programmatically syncing `text`, so the `onChange(of: text)`
    /// handler doesn't write a rounded value back into `weightKg` (which would lose
    /// precision every time the unit is toggled).
    @State private var isSyncing = false

    var body: some View {
        TextField("0", text: $text)
            .font(PulseFont.bodySemibold(15))
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .keyboardType(.decimalPad)
            .foregroundStyle(PulseColors.textPrimary)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(PulseColors.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
            .onAppear { syncText() }
            .onChange(of: unit) { _, _ in syncText() }
            .onChange(of: text) { _, newValue in
                guard !isSyncing else { return }
                weightKg = unit.toKilograms(Double(newValue) ?? 0)
            }
    }

    private func syncText() {
        isSyncing = true
        text = weightKg == 0 ? "" : unit.displayValue(fromKilograms: weightKg)
        // Release the guard after the binding settles so genuine edits register.
        DispatchQueue.main.async { isSyncing = false }
    }
}
