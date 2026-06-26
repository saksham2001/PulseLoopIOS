import SwiftUI
import SwiftData

// MARK: - Symptoms Tracking View

struct SymptomsTrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SymptomLog.date, order: .reverse) private var logs: [SymptomLog]
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 16) {
            header
            if !logs.isEmpty { recentSymptoms }
            else { emptyState }
        }
        .sheet(isPresented: $showAdd) { AddSymptomSheet() }
    }

    private var header: some View {
        HStack {
            Text("SYMPTOMS")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)
            Spacer()
            Button { showAdd = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    Text("Log").font(PulseFont.bodySemibold(12))
                }
                .foregroundStyle(PulseColors.accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(PulseColors.accent.opacity(0.1))
                .clipShape(Capsule())
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "stethoscope")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(PulseColors.textPrimary)
            Text("No symptoms logged").font(PulseFont.body(13)).foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PulseColors.borderHairline, lineWidth: 1) }
    }

    private var recentSymptoms: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(logs.prefix(6)) { log in
                HStack(spacing: 10) {
                    severityDot(log.severity)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.symptom).font(PulseFont.bodySemibold(14)).foregroundStyle(PulseColors.textPrimary)
                        if let area = log.bodyArea {
                            Text(area).font(PulseFont.body(11)).foregroundStyle(PulseColors.textMuted)
                        }
                    }
                    Spacer()
                    Text("\(log.severity)/10").font(PulseFont.bodySemibold(12)).foregroundStyle(severityColor(log.severity))
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PulseColors.borderHairline, lineWidth: 1) }
    }

    private func severityDot(_ level: Int) -> some View {
        Circle().fill(severityColor(level)).frame(width: 10, height: 10)
    }

    private func severityColor(_ level: Int) -> Color {
        if level <= 3 { return .green }
        if level <= 6 { return .orange }
        return .red
    }
}

struct AddSymptomSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var symptom = ""
    @State private var severity = 5
    @State private var bodyArea = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    TextField("Symptom (e.g. Headache)", text: $symptom)
                        .font(PulseFont.body(15)).padding(12)
                        .background(PulseColors.fillSubtle).clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Severity: \(severity)/10").font(PulseFont.bodyMedium(13)).foregroundStyle(PulseColors.textMuted)
                        HStack(spacing: 4) {
                            ForEach(1...10, id: \.self) { i in
                                Button { severity = i } label: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(i <= severity ? severityColor(severity) : PulseColors.fillSubtle)
                                        .frame(height: 28)
                                }
                            }
                        }
                    }

                    TextField("Body area (optional)", text: $bodyArea)
                        .font(PulseFont.body(15)).padding(12)
                        .background(PulseColors.fillSubtle).clipShape(RoundedRectangle(cornerRadius: 10))

                    TextField("Notes", text: $notes)
                        .font(PulseFont.body(15)).padding(12)
                        .background(PulseColors.fillSubtle).clipShape(RoundedRectangle(cornerRadius: 10))

                    Button { save() } label: {
                        Text("Log Symptom").font(PulseFont.bodySemibold(15)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(symptom.isEmpty ? PulseColors.textMuted : Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }.disabled(symptom.isEmpty)
                }.padding(20)
            }
            .background(PulseColors.background)
            .navigationTitle("Log Symptom").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func severityColor(_ level: Int) -> Color {
        if level <= 3 { return .green }; if level <= 6 { return .orange }; return .red
    }

    private func save() {
        modelContext.insert(SymptomLog(symptom: symptom, severity: severity, notes: notes.isEmpty ? nil : notes, bodyArea: bodyArea.isEmpty ? nil : bodyArea))
        try? modelContext.save(); dismiss()
    }
}

// MARK: - Labs/Bloodwork View

struct LabsTrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 16) {
            header
            if !results.isEmpty { labResults }
            else { emptyState }
        }
        .sheet(isPresented: $showAdd) { AddLabSheet() }
    }

    private var header: some View {
        HStack {
            Text("LABS & BLOODWORK")
                .font(PulseFont.bodyMedium(11)).foregroundStyle(PulseColors.textMuted).tracking(0.8)
            Spacer()
            Button { showAdd = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    Text("Add").font(PulseFont.bodySemibold(12))
                }
                .foregroundStyle(PulseColors.accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(PulseColors.accent.opacity(0.1)).clipShape(Capsule())
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "flask.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(PulseColors.textPrimary)
            Text("Add lab results to track trends").font(PulseFont.body(13)).foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PulseColors.borderHairline, lineWidth: 1) }
    }

    private var labResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(results.prefix(8)) { r in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.testName).font(PulseFont.bodySemibold(14)).foregroundStyle(PulseColors.textPrimary)
                        Text(r.date, style: .date).font(PulseFont.body(11)).foregroundStyle(PulseColors.textFaint)
                    }
                    Spacer()
                    Text("\(String(format: "%.1f", r.value)) \(r.unit)")
                        .font(PulseFont.bodySemibold(13))
                        .foregroundStyle(r.isOutOfRange ? .red : PulseColors.textPrimary)
                    if r.isOutOfRange {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PulseColors.borderHairline, lineWidth: 1) }
    }
}

struct AddLabSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var testName = ""
    @State private var value = ""
    @State private var unit = "mg/dL"
    @State private var refMin = ""
    @State private var refMax = ""
    @State private var category = "General"

    private let categories = ["General", "Hormones", "Metabolic", "Lipids", "Vitamins", "Thyroid", "Inflammatory", "Blood Count"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TextField("Test name (e.g. Testosterone)", text: $testName)
                        .font(PulseFont.body(15)).padding(12)
                        .background(PulseColors.fillSubtle).clipShape(RoundedRectangle(cornerRadius: 10))

                    HStack(spacing: 12) {
                        TextField("Value", text: $value)
                            .keyboardType(.decimalPad).font(PulseFont.body(15)).padding(12)
                            .background(PulseColors.fillSubtle).clipShape(RoundedRectangle(cornerRadius: 10))
                        TextField("Unit", text: $unit)
                            .font(PulseFont.body(15)).padding(12)
                            .background(PulseColors.fillSubtle).clipShape(RoundedRectangle(cornerRadius: 10))
                            .frame(width: 100)
                    }

                    HStack(spacing: 12) {
                        TextField("Ref min", text: $refMin).keyboardType(.decimalPad).font(PulseFont.body(15)).padding(12)
                            .background(PulseColors.fillSubtle).clipShape(RoundedRectangle(cornerRadius: 10))
                        TextField("Ref max", text: $refMax).keyboardType(.decimalPad).font(PulseFont.body(15)).padding(12)
                            .background(PulseColors.fillSubtle).clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }.pickerStyle(.menu)

                    Button { save() } label: {
                        Text("Save Result").font(PulseFont.bodySemibold(15)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(testName.isEmpty || value.isEmpty ? PulseColors.textMuted : Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }.disabled(testName.isEmpty || value.isEmpty)
                }.padding(20)
            }
            .background(PulseColors.background)
            .navigationTitle("Add Lab Result").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() {
        guard let v = Double(value) else { return }
        modelContext.insert(LabResult(testName: testName, value: v, unit: unit, referenceMin: Double(refMin), referenceMax: Double(refMax), category: category))
        try? modelContext.save(); dismiss()
    }
}
