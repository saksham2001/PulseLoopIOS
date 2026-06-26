import SwiftUI
import Combine

// MARK: - SubAppRuntime — renders a SubAppSpec using design-system widgets (roadmap C2)
//
// The runtime interprets a validated `SubAppSpec` and produces SwiftUI screens for
// `.userCreated` / `.installed` sub-apps without any hand-written Swift per sub-app.
// It renders ONLY design-system widgets (`PulseCard`, `PulseColors`, `PulseFont`,
// `InlineEmptyState`, black primary buttons) so generated UI stays on-brand.
//
// Persistence is abstracted behind `SubAppRecordStore`. This iteration ships an
// in-memory store so the runtime is fully exercised end-to-end; C3 swaps in a
// SwiftData-backed store with additive migration. UI code is store-agnostic.

// MARK: Record model

/// A dynamic field value. Constrained to the `FieldType` cases the spec allows.
enum SubAppFieldValue: Hashable {
    case text(String)
    case number(Double)
    case integer(Int)
    case boolean(Bool)
    case date(Date)
    case selection(String)
    case empty

    var displayString: String {
        switch self {
        case let .text(s): return s
        case let .number(n): return Self.numberFormatter.string(from: n as NSNumber) ?? "\(n)"
        case let .integer(i): return "\(i)"
        case let .boolean(b): return b ? "Yes" : "No"
        case let .date(d): return d.formatted(date: .abbreviated, time: .shortened)
        case let .selection(s): return s
        case .empty: return "—"
        }
    }

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        return f
    }()
}

/// One stored record for a dynamic entity.
struct SubAppRecord: Identifiable, Hashable {
    let id: UUID
    var values: [String: SubAppFieldValue]
    var createdAt: Date

    init(id: UUID = UUID(), values: [String: SubAppFieldValue] = [:], createdAt: Date = Date()) {
        self.id = id
        self.values = values
        self.createdAt = createdAt
    }
}

/// Storage seam for dynamic entity records. C3 replaces the in-memory impl with a
/// SwiftData-backed one; the runtime UI only ever talks to this protocol.
@MainActor
protocol SubAppRecordStore: AnyObject {
    func records(subAppID: String, entity: String) -> [SubAppRecord]
    func upsert(_ record: SubAppRecord, subAppID: String, entity: String)
    func delete(_ id: UUID, subAppID: String, entity: String)
}

/// Default in-memory store (C2). Keyed by "subAppID/entity".
@MainActor
final class InMemorySubAppRecordStore: SubAppRecordStore, ObservableObject {
    @Published private var storage: [String: [SubAppRecord]] = [:]

    private func key(_ subAppID: String, _ entity: String) -> String { "\(subAppID)/\(entity)" }

    func records(subAppID: String, entity: String) -> [SubAppRecord] {
        storage[key(subAppID, entity)]?.sorted { $0.createdAt > $1.createdAt } ?? []
    }

    func upsert(_ record: SubAppRecord, subAppID: String, entity: String) {
        let k = key(subAppID, entity)
        var list = storage[k] ?? []
        if let idx = list.firstIndex(where: { $0.id == record.id }) {
            list[idx] = record
        } else {
            list.append(record)
        }
        storage[k] = list
    }

    func delete(_ id: UUID, subAppID: String, entity: String) {
        let k = key(subAppID, entity)
        storage[k]?.removeAll { $0.id == id }
    }
}

// MARK: - Runtime root

/// Renders a spec's entry screen and drives navigation between its screens. The
/// store is any `SubAppRecordStore` (in-memory for previews, SwiftData in prod).
struct SubAppRuntimeView: View {
    let spec: SubAppSpec
    let store: any SubAppRecordStore
    @State private var path = NavigationPath()
    @State private var reloadToken = UUID()

    private var entryScreen: ScreenSpec? { spec.screens.first }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let screen = entryScreen {
                    SubAppScreenView(spec: spec, screen: screen, store: store, path: $path, reloadToken: $reloadToken)
                } else {
                    InlineEmptyState(title: spec.displayName, message: "This sub-app has no screens.")
                }
            }
            .navigationTitle(spec.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SubAppNavTarget.self) { target in
                if let screen = spec.screens.first(where: { $0.id == target.screenID }) {
                    SubAppScreenView(spec: spec, screen: screen, store: store, path: $path, reloadToken: $reloadToken, editingRecordID: target.recordID)
                }
            }
        }
        .onAppear { SubAppAnalytics.shared.record(.opened, subAppID: spec.id) }
    }
}

/// A navigation hop inside a runtime sub-app.
struct SubAppNavTarget: Hashable {
    let screenID: String
    var recordID: UUID?
}

// MARK: - Screen dispatch

struct SubAppScreenView: View {
    let spec: SubAppSpec
    let screen: ScreenSpec
    let store: any SubAppRecordStore
    @Binding var path: NavigationPath
    @Binding var reloadToken: UUID
    var editingRecordID: UUID?

    private var entity: EntitySpec? {
        guard let name = screen.entity else { return nil }
        return spec.entities.first { $0.name == name }
    }

    var body: some View {
        switch screen.kind {
        case .list:
            SubAppListScreen(spec: spec, screen: screen, entity: entity, store: store, path: $path, reloadToken: $reloadToken)
        case .form:
            SubAppFormScreen(spec: spec, screen: screen, entity: entity, store: store, path: $path, reloadToken: $reloadToken, editingRecordID: editingRecordID)
        case .detail:
            SubAppDetailScreen(spec: spec, entity: entity, store: store, recordID: editingRecordID)
        case .dashboard:
            SubAppDashboardScreen(spec: spec, store: store, reloadToken: $reloadToken)
        }
    }
}

// MARK: - List

struct SubAppListScreen: View {
    let spec: SubAppSpec
    let screen: ScreenSpec
    let entity: EntitySpec?
    let store: any SubAppRecordStore
    @Binding var path: NavigationPath
    @Binding var reloadToken: UUID

    private var formScreenID: String? {
        spec.screens.first { $0.kind == .form && $0.entity == entity?.name }?.id
    }

    private var records: [SubAppRecord] {
        guard let entity else { return [] }
        _ = reloadToken
        return store.records(subAppID: spec.id, entity: entity.name)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if records.isEmpty {
                    PulseCard {
                        InlineEmptyState(
                            title: "Nothing yet",
                            message: "Add your first \(entity?.label.lowercased() ?? "entry") to get started."
                        )
                    }
                } else {
                    ForEach(records) { record in
                        Button {
                            if let fid = formScreenID {
                                path.append(SubAppNavTarget(screenID: fid, recordID: record.id))
                            }
                        } label: {
                            SubAppRecordRow(entity: entity, record: record)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(PulseColors.background)
        .navigationTitle(screen.title)
        .onAppear { reloadToken = UUID() }
        .toolbar {
            if let fid = formScreenID {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        path.append(SubAppNavTarget(screenID: fid, recordID: nil))
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add \(entity?.label ?? "entry")")
                }
            }
        }
    }
}

struct SubAppRecordRow: View {
    let entity: EntitySpec?
    let record: SubAppRecord

    private var primaryField: FieldSpec? { entity?.fields.first }
    private var secondaryFields: [FieldSpec] { Array((entity?.fields ?? []).dropFirst().prefix(2)) }

    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(value(for: primaryField))
                    .font(PulseFont.bodySemibold(15))
                    .foregroundStyle(PulseColors.textPrimary)
                if !secondaryFields.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(secondaryFields, id: \.name) { field in
                            Text("\(field.label): \(value(for: field))")
                                .font(PulseFont.body(12))
                                .foregroundStyle(PulseColors.textMuted)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func value(for field: FieldSpec?) -> String {
        guard let field else { return "—" }
        return (record.values[field.name] ?? .empty).displayString
    }
}

// MARK: - Form

struct SubAppFormScreen: View {
    let spec: SubAppSpec
    let screen: ScreenSpec
    let entity: EntitySpec?
    let store: any SubAppRecordStore
    @Binding var path: NavigationPath
    @Binding var reloadToken: UUID
    var editingRecordID: UUID?

    @State private var values: [String: SubAppFieldValue] = [:]
    @State private var existing: SubAppRecord?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(entity?.fields ?? [], id: \.name) { field in
                    SubAppFieldEditor(field: field, value: binding(for: field))
                }

                Button(action: save) {
                    Text("Save")
                        .font(PulseFont.bodySemibold(15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSave ? Color.black : PulseColors.textFaint)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(!canSave)
            }
            .padding(16)
        }
        .background(PulseColors.background)
        .navigationTitle(existing == nil ? "New \(entity?.label ?? "Entry")" : "Edit \(entity?.label ?? "Entry")")
        .onAppear(perform: load)
    }

    private var canSave: Bool {
        guard let entity else { return false }
        return entity.fields.filter { $0.required }.allSatisfy { field in
            if case .empty = (values[field.name] ?? .empty) { return false }
            if case let .text(s) = (values[field.name] ?? .empty), s.isEmpty { return false }
            return true
        }
    }

    private func load() {
        guard let entity, let id = editingRecordID,
              let record = store.records(subAppID: spec.id, entity: entity.name).first(where: { $0.id == id })
        else { return }
        existing = record
        values = record.values
    }

    private func save() {
        guard let entity else { return }
        let isNew = existing == nil
        var record = existing ?? SubAppRecord()
        record.values = values
        store.upsert(record, subAppID: spec.id, entity: entity.name)
        if isNew { SubAppAnalytics.shared.record(.recordCreated, subAppID: spec.id) }
        reloadToken = UUID()
        if !path.isEmpty { path.removeLast() }
    }

    private func binding(for field: FieldSpec) -> Binding<SubAppFieldValue> {
        Binding(
            get: { values[field.name] ?? .empty },
            set: { values[field.name] = $0 }
        )
    }
}

/// Renders a single field editor matched to its `FieldType`.
struct SubAppFieldEditor: View {
    let field: FieldSpec
    @Binding var value: SubAppFieldValue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.label.isEmpty ? field.name : field.label)
                .font(PulseFont.bodyMedium(12))
                .foregroundStyle(PulseColors.textMuted)
            editor
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var editor: some View {
        switch field.type {
        case .text, .number, .integer:
            TextField(field.label, text: textBinding)
                .keyboardType(field.type == .text ? .default : .decimalPad)
                .padding(12)
                .pulseCardSurface()
        case .boolean:
            Toggle(field.label, isOn: boolBinding)
                .tint(Color.black)
        case .date:
            DatePicker(field.label, selection: dateBinding, displayedComponents: [.date, .hourAndMinute])
        case .rating:
            ratingEditor
        case .selection:
            selectionEditor
        }
    }

    private var ratingEditor: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: currentInt >= star ? "star.fill" : "star")
                    .foregroundStyle(currentInt >= star ? Color.black : PulseColors.textFaint)
                    .onTapGesture { value = .integer(star) }
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
            }
        }
    }

    @ViewBuilder private var selectionEditor: some View {
        let options = field.options
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) { value = .selection(option) }
            }
        } label: {
            HStack {
                Text(currentSelection.isEmpty ? "Choose…" : currentSelection)
                    .foregroundStyle(currentSelection.isEmpty ? PulseColors.textMuted : PulseColors.textPrimary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").foregroundStyle(PulseColors.textMuted)
            }
            .font(PulseFont.body(14))
            .padding(12)
            .pulseCardSurface()
        }
    }

    // Bindings that bridge typed values to/from the editors.
    private var textBinding: Binding<String> {
        Binding(
            get: {
                switch value {
                case let .text(s): return s
                case let .number(n): return n == 0 ? "" : "\(n)"
                case let .integer(i): return i == 0 ? "" : "\(i)"
                default: return ""
                }
            },
            set: { newValue in
                switch field.type {
                case .number: value = newValue.isEmpty ? .empty : .number(Double(newValue) ?? 0)
                case .integer: value = newValue.isEmpty ? .empty : .integer(Int(newValue) ?? 0)
                default: value = newValue.isEmpty ? .empty : .text(newValue)
                }
            }
        )
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { if case let .boolean(b) = value { return b }; return false },
            set: { value = .boolean($0) }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { if case let .date(d) = value { return d }; return Date() },
            set: { value = .date($0) }
        )
    }

    private var currentInt: Int { if case let .integer(i) = value { return i }; return 0 }
    private var currentSelection: String { if case let .selection(s) = value { return s }; return "" }
}

// MARK: - Detail

struct SubAppDetailScreen: View {
    let spec: SubAppSpec
    let entity: EntitySpec?
    let store: any SubAppRecordStore
    var recordID: UUID?

    private var record: SubAppRecord? {
        guard let entity, let recordID else { return nil }
        return store.records(subAppID: spec.id, entity: entity.name).first { $0.id == recordID }
    }

    var body: some View {
        ScrollView {
            if let entity, let record {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(entity.fields, id: \.name) { field in
                        PulseCard {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field.label).font(PulseFont.bodyMedium(12)).foregroundStyle(PulseColors.textMuted)
                                Text((record.values[field.name] ?? .empty).displayString)
                                    .font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(16)
            } else {
                InlineEmptyState(title: "Not found", message: "This record no longer exists.")
                    .padding(16)
            }
        }
        .background(PulseColors.background)
        .navigationTitle(entity?.label ?? "Detail")
    }
}

// MARK: - Dashboard

struct SubAppDashboardScreen: View {
    let spec: SubAppSpec
    let store: any SubAppRecordStore
    @Binding var reloadToken: UUID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(spec.entities, id: \.name) { entity in
                    PulseCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entity.label).font(PulseFont.bodyMedium(13)).foregroundStyle(PulseColors.textMuted)
                                Text("\(count(entity))")
                                    .font(PulseFont.title(28)).foregroundStyle(PulseColors.textPrimary)
                                Text("records").font(PulseFont.body(11)).foregroundStyle(PulseColors.textFaint)
                            }
                            Spacer()
                            Image(systemName: spec.icon).font(.system(size: 22)).foregroundStyle(PulseColors.textMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if spec.entities.isEmpty {
                    PulseCard { InlineEmptyState(title: spec.displayName, message: spec.summary) }
                }
            }
            .padding(16)
        }
        .background(PulseColors.background)
        .navigationTitle(spec.displayName)
        .onAppear { reloadToken = UUID() }
    }

    private func count(_ entity: EntitySpec) -> Int {
        _ = reloadToken
        return store.records(subAppID: spec.id, entity: entity.name).count
    }
}
