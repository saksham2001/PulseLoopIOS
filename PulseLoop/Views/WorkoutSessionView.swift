import SwiftUI
import SwiftData
import Combine

// MARK: - Workout Session Route
//
// Resolves a `WorkoutTemplate` by id for deep-link navigation (`AppRoute.workoutSession`).
// The primary entry point is a sheet from the fitness dashboard, but this keeps the
// route functional.

struct WorkoutSessionRoute: View {
    let templateId: UUID
    @Query private var templates: [WorkoutTemplate]

    init(templateId: UUID) {
        self.templateId = templateId
        _templates = Query(filter: #Predicate<WorkoutTemplate> { $0.id == templateId })
    }

    var body: some View {
        if let template = templates.first {
            WorkoutSessionView(template: template)
        } else {
            InlineEmptyState(title: "Workout not found", message: "This template may have been deleted.")
        }
    }
}

// MARK: - Workout Session
//
// Perform a workout from a template: tick off each set (editing the actual reps /
// weight you hit), then finish → a `WorkoutLog` session is written via
// `WorkoutSessionBridge` (stamping `lastPerformed`, feeding history + the dashboard
// charts). Presented as a sheet from the fitness dashboard. Design-system styled.

struct WorkoutSessionView: View {
    @Bindable var template: WorkoutTemplate
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var startedAt = Date()
    @State private var intensity = 6
    @State private var notes = ""
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var elapsedMinutes: Int { max(0, Int(now.timeIntervalSince(startedAt) / 60)) }
    private var completedSets: Int { template.exercises.reduce(0) { $0 + $1.sets.filter(\.completed).count } }
    private var volume: Double { WorkoutSessionBridge.totalVolume(of: template) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statsCard
                    ForEach(template.exercises.sorted { $0.order < $1.order }) { exercise in
                        exerciseCard(exercise)
                    }
                    notesField
                    finishButton
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(PulseColors.canvas)
            .navigationTitle(template.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PulseColors.textSecondary)
                }
            }
            .onReceive(timer) { now = $0 }
        }
    }

    private var statsCard: some View {
        PulseCard {
            HStack {
                stat("\(elapsedMinutes)", "min")
                Divider().frame(height: 32)
                stat("\(completedSets)/\(template.totalSets)", "sets")
                Divider().frame(height: 32)
                stat("\(Int(volume))", "volume")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(PulseFont.bodySemibold(17)).foregroundStyle(PulseColors.textPrimary)
            Text(label).font(PulseFont.body(11)).foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func exerciseCard(_ exercise: TemplateExercise) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: exercise.equipment.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PulseColors.textSecondary)
                    Text(exercise.name)
                        .font(PulseFont.bodySemibold(15))
                        .foregroundStyle(PulseColors.textPrimary)
                    Spacer()
                    Text(exercise.muscleGroup.rawValue)
                        .font(PulseFont.body(11))
                        .foregroundStyle(PulseColors.textMuted)
                }
                HStack {
                    Text("SET").frame(width: 36, alignment: .leading)
                    Text("REPS").frame(maxWidth: .infinity, alignment: .center)
                    Text("WEIGHT").frame(maxWidth: .infinity, alignment: .center)
                    Text("").frame(width: 32)
                }
                .font(PulseFont.bodyMedium(10)).tracking(0.6)
                .foregroundStyle(PulseColors.textMuted)

                ForEach(Array(exercise.sets.sorted { $0.order < $1.order }.enumerated()), id: \.element.id) { idx, set in
                    setRow(set, number: idx + 1)
                }
            }
        }
    }

    private func setRow(_ set: ExerciseSet, number: Int) -> some View {
        @Bindable var set = set
        return HStack(spacing: 8) {
            Text("\(number)")
                .font(PulseFont.bodyMedium(13))
                .foregroundStyle(PulseColors.textSecondary)
                .frame(width: 36, alignment: .leading)
            TextField("0", value: $set.reps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(PulseFont.body(14))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            TextField("0", value: $set.weightKg, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(PulseFont.body(14))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Button {
                set.completed.toggle()
                HapticService.impact(.light)
            } label: {
                Image(systemName: set.completed ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(set.completed ? Color.black : PulseColors.borderStrong)
            }
            .buttonStyle(.plain)
            .frame(width: 32)
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("INTENSITY (\(intensity)/10)")
                .font(PulseFont.bodyMedium(11)).tracking(0.8).foregroundStyle(PulseColors.textMuted)
            Slider(value: Binding(get: { Double(intensity) }, set: { intensity = Int($0) }), in: 1...10, step: 1)
                .tint(PulseColors.textPrimary)
            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .font(PulseFont.body(14))
                .padding(12)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var finishButton: some View {
        Button {
            WorkoutSessionBridge.logSession(
                from: template,
                durationMinutes: max(1, elapsedMinutes),
                intensity: intensity,
                notes: notes.isEmpty ? nil : notes,
                in: modelContext,
                date: startedAt
            )
            HapticService.success()
            dismiss()
        } label: {
            Text("Finish workout")
                .font(PulseFont.bodySemibold(15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(completedSets > 0 ? Color.black : PulseColors.textFaint)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(completedSets == 0)
        .padding(.top, 4)
    }
}

// MARK: - Workout History

/// Recent logged sessions, shown on the fitness dashboard so completed workouts have
/// a home (mirrors MyFitnessPal's exercise history).
struct WorkoutHistoryCard: View {
    let workouts: [WorkoutLog]

    private var recent: [WorkoutLog] { Array(workouts.prefix(6)) }

    var body: some View {
        if recent.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(recent) { w in
                    HStack(spacing: 12) {
                        Image(systemName: w.type.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(PulseColors.textPrimary)
                            .frame(width: 38, height: 38)
                            .background(PulseColors.fillSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.name).font(PulseFont.bodySemibold(14)).foregroundStyle(PulseColors.textPrimary)
                            Text(subtitle(w)).font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
                        }
                        Spacer()
                        Text(w.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(PulseFont.body(11)).foregroundStyle(PulseColors.textMuted)
                    }
                    .padding(12)
                    .pulseCardSurface()
                }
            }
        }
    }

    private func subtitle(_ w: WorkoutLog) -> String {
        var parts = ["\(w.durationMinutes) min"]
        let sets = w.exercises.compactMap(\.sets).reduce(0, +)
        if sets > 0 { parts.append("\(sets) sets") }
        if let cal = w.caloriesBurned { parts.append("\(cal) kcal") }
        return parts.joined(separator: " · ")
    }
}
