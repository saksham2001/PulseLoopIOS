import SwiftUI

// MARK: - SubAppEditorView — structured drag-and-drop spec editor
//
// A no-AI, direct manipulation editor for a `SubAppSpec`. Lets the user reorder
// entities / fields / screens via native drag-to-reorder (List + EditMode),
// add/edit/delete each, toggle permissions, and rename metadata. Every change is
// validated live; Save runs the strict validator + guardrails before persisting to
// `UserSubAppStore` and re-registering routes so the running sub-app reflects edits.

struct SubAppEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var spec: SubAppSpec
    @State private var saved = false
    @State private var saveError: String?
    private let isNew: Bool

    init(spec: SubAppSpec, isNew: Bool = false) {
        _spec = State(initialValue: spec)
        self.isNew = isNew
    }

    private var issues: [SubAppSpecIssue] { SubAppSpecValidator.issues(in: spec) }
    private var errors: [SubAppSpecIssue] { issues.filter { $0.severity == .error } }
    private var warnings: [SubAppSpecIssue] { issues.filter { $0.severity == .warning } }
    private var canSave: Bool { errors.isEmpty }

    var body: some View {
        List {
            metadataSection
            entitiesSection
            screensSection
            permissionsSection
            validationSection
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .navigationTitle(isNew ? "New Sub-App" : "Edit Sub-App")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .tint(PulseColors.accent)
    }

    // MARK: Metadata

    private var metadataSection: some View {
        Section("Details") {
            LabeledContent("Name") {
                TextField("Name", text: $spec.displayName)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("SF Symbol") {
                HStack(spacing: 8) {
                    Image(systemName: validIcon(spec.icon) ? spec.icon : "questionmark.square.dashed")
                        .foregroundStyle(PulseColors.textMuted)
                    TextField("e.g. star.fill", text: $spec.icon)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Summary").font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
                TextField("One-line description", text: $spec.summary, axis: .vertical)
                    .lineLimit(1...3)
            }
        }
    }

    // MARK: Entities

    private var entitiesSection: some View {
        Section {
            ForEach($spec.entities, id: \.name) { $entity in
                NavigationLink {
                    EntityEditorView(entity: $entity)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entity.label.isEmpty ? entity.name : entity.label)
                            .font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
                        Text("\(entity.fields.count) field\(entity.fields.count == 1 ? "" : "s") · \(entity.name)")
                            .font(PulseFont.body(12)).foregroundStyle(PulseColors.textFaint)
                    }
                }
            }
            .onMove { spec.entities.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { spec.entities.remove(atOffsets: $0) }

            Button {
                addEntity()
            } label: {
                Label("Add entity", systemImage: "plus.circle")
            }
        } header: {
            Text("Data (drag to reorder)")
        } footer: {
            Text("Entities are your data tables. Drag the handle to reorder, swipe to delete.")
        }
    }

    // MARK: Screens

    private var screensSection: some View {
        Section {
            ForEach($spec.screens, id: \.id) { $screen in
                ScreenRow(screen: $screen, entityNames: spec.entities.map { $0.name })
            }
            .onMove { spec.screens.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { spec.screens.remove(atOffsets: $0) }

            Button {
                addScreen()
            } label: {
                Label("Add screen", systemImage: "plus.circle")
            }
        } header: {
            Text("Screens (first is the entry point)")
        } footer: {
            Text("The top screen opens first. Drag to reorder, swipe to delete.")
        }
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        Section("Permissions") {
            ForEach(SubAppPermission.allCases, id: \.self) { permission in
                Toggle(isOn: binding(for: permission)) {
                    Text(SubAppGuardrails.explain(permission))
                        .font(PulseFont.body(14))
                }
                .tint(Color.black)
            }
        }
    }

    private func binding(for permission: SubAppPermission) -> Binding<Bool> {
        Binding(
            get: { spec.permissions.contains(permission) },
            set: { on in
                if on {
                    if !spec.permissions.contains(permission) { spec.permissions.append(permission) }
                } else {
                    spec.permissions.removeAll { $0 == permission }
                }
            }
        )
    }

    // MARK: Validation

    @ViewBuilder
    private var validationSection: some View {
        if !issues.isEmpty || saved || saveError != nil {
            Section("Status") {
                if let saveError {
                    Label(saveError, systemImage: "xmark.octagon.fill")
                        .font(PulseFont.body(13)).foregroundStyle(PulseColors.heartRate)
                }
                if saved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(PulseFont.body(13)).foregroundStyle(PulseColors.success)
                }
                ForEach(errors, id: \.self) { issue in
                    Label(issueText(issue), systemImage: "exclamationmark.triangle.fill")
                        .font(PulseFont.body(12)).foregroundStyle(PulseColors.heartRate)
                }
                ForEach(warnings, id: \.self) { issue in
                    Label(issueText(issue), systemImage: "exclamationmark.circle")
                        .font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
                }
            }
        }
    }

    private func issueText(_ issue: SubAppSpecIssue) -> String {
        "\(issue.path): \(issue.message)"
    }

    // MARK: Mutations

    private func addEntity() {
        let base = "entity"
        let name = uniqueSlug(base: base, existing: spec.entities.map { $0.name })
        spec.entities.append(
            EntitySpec(
                name: name,
                label: "New Entity",
                fields: [FieldSpec(name: "title", label: "Title", type: .text, required: true)]
            )
        )
    }

    private func addScreen() {
        let entityName = spec.entities.first?.name
        let id = uniqueSlug(base: "screen", existing: spec.screens.map { $0.id })
        spec.screens.append(
            ScreenSpec(id: id, title: "New Screen", kind: .list, entity: entityName)
        )
    }

    // MARK: Save

    private func save() {
        saved = false
        saveError = nil
        do {
            try SubAppSpecValidator.validate(spec)
        } catch {
            saveError = "\(error.localizedDescription)"
            return
        }
        let report = SubAppGuardrails.review(spec)
        guard report.canSave else {
            saveError = report.blockers.map { $0.message }.joined(separator: "; ")
            return
        }
        var updated = spec
        // Bump patch on every edit so installs can detect a changed definition.
        updated.version = SemanticVersion(
            major: spec.version.major,
            minor: spec.version.minor,
            patch: spec.version.patch + 1
        )
        UserSubAppStore.shared.save(updated)
        SubAppRegistry.shared.loadUserSpecs()
        SubAppRegistry.shared.install(SubAppID(updated.id))
        spec = updated
        saved = true
    }

    private func validIcon(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && UIImage(systemName: name) != nil
    }

    /// A fresh, minimal-but-valid starting spec for "create from scratch". The id is
    /// randomized so it never collides with an existing or reserved sub-app.
    static func blankSpec() -> SubAppSpec {
        let suffix = String(UUID().uuidString.prefix(6)).lowercased().filter { $0.isLetter || $0.isNumber }
        return SubAppSpec(
            id: "app_\(suffix.isEmpty ? "new" : suffix)",
            displayName: "My Sub-App",
            icon: "square.grid.2x2",
            summary: "",
            entities: [
                EntitySpec(
                    name: "entry",
                    label: "Entry",
                    fields: [
                        FieldSpec(name: "title", label: "Title", type: .text, required: true),
                        FieldSpec(name: "when", label: "When", type: .date, required: true),
                    ]
                )
            ],
            screens: [
                ScreenSpec(id: "list", title: "Entries", kind: .list, entity: "entry"),
                ScreenSpec(id: "form", title: "New Entry", kind: .form, entity: "entry"),
            ]
        )
    }
}

// MARK: - Helpers shared by editor views

/// Build a unique lowercase slug from `base`, appending `_2`, `_3`, … on collision.
func uniqueSlug(base: String, existing: [String]) -> String {
    let taken = Set(existing)
    if !taken.contains(base) { return base }
    var i = 2
    while taken.contains("\(base)_\(i)") { i += 1 }
    return "\(base)_\(i)"
}

/// Lowercase-slugify free text into an identifier (a-z, 0-9, underscore).
func slugify(_ text: String) -> String {
    let lowered = text.lowercased()
    var out = ""
    var lastWasUnderscore = false
    for ch in lowered {
        if ch.isLetter && ch.isASCII || (ch.isNumber && ch.isASCII) {
            out.append(ch)
            lastWasUnderscore = false
        } else if !lastWasUnderscore {
            out.append("_")
            lastWasUnderscore = true
        }
    }
    out = out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    // Slugs must start with a letter.
    if let first = out.first, !first.isLetter {
        out = "f_" + out
    }
    return out.isEmpty ? "field" : out
}

// MARK: - Entity editor (drag-reorderable fields)

struct EntityEditorView: View {
    @Binding var entity: EntitySpec

    var body: some View {
        List {
            Section("Entity") {
                LabeledContent("Label") {
                    TextField("Label", text: $entity.label)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Name") {
                    Text(entity.name).foregroundStyle(PulseColors.textFaint)
                }
            }

            Section {
                ForEach($entity.fields, id: \.name) { $field in
                    NavigationLink {
                        FieldEditorView(field: $field)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(field.label.isEmpty ? field.name : field.label)
                                .font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
                            HStack(spacing: 6) {
                                Text(field.type.rawValue)
                                if field.required { Text("· required") }
                            }
                            .font(PulseFont.body(12)).foregroundStyle(PulseColors.textFaint)
                        }
                    }
                }
                .onMove { entity.fields.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { entity.fields.remove(atOffsets: $0) }

                Button {
                    addField()
                } label: {
                    Label("Add field", systemImage: "plus.circle")
                }
            } header: {
                Text("Fields (drag to reorder)")
            } footer: {
                Text("The first field is used as the row title in lists.")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .navigationTitle(entity.label.isEmpty ? entity.name : entity.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addField() {
        let name = uniqueSlug(base: "field", existing: entity.fields.map { $0.name })
        entity.fields.append(FieldSpec(name: name, label: "New Field", type: .text))
    }
}

// MARK: - Field editor

struct FieldEditorView: View {
    @Binding var field: FieldSpec
    @State private var optionsText: String = ""

    var body: some View {
        List {
            Section("Field") {
                LabeledContent("Label") {
                    TextField("Label", text: labelBinding)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Name") {
                    Text(field.name).foregroundStyle(PulseColors.textFaint)
                }
                Picker("Type", selection: $field.type) {
                    ForEach(FieldType.allCases, id: \.self) { type in
                        Text(type.rawValue.capitalized).tag(type)
                    }
                }
                Toggle("Required", isOn: $field.required)
                    .tint(Color.black)
            }

            if field.type == .selection {
                Section {
                    TextField("Comma-separated options", text: $optionsText, axis: .vertical)
                        .lineLimit(1...4)
                        .onChange(of: optionsText) { _, new in
                            field.options = new
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        }
                } header: {
                    Text("Options")
                } footer: {
                    Text("Used for the selection menu, e.g. \"Low, Medium, High\".")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(field.label.isEmpty ? field.name : field.label)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { optionsText = field.options.joined(separator: ", ") }
    }

    /// Editing the label re-derives the slug name when it still looks auto-generated,
    /// so renaming a fresh field keeps a sensible identifier without clobbering one
    /// the user (or AI) already set meaningfully.
    private var labelBinding: Binding<String> {
        Binding(
            get: { field.label },
            set: { newLabel in
                let oldAuto = slugify(field.label)
                field.label = newLabel
                if field.name == oldAuto || field.name.hasPrefix("field") {
                    field.name = slugify(newLabel)
                }
            }
        )
    }
}

// MARK: - Screen row

struct ScreenRow: View {
    @Binding var screen: ScreenSpec
    let entityNames: [String]

    private var needsEntity: Bool {
        screen.kind == .list || screen.kind == .form || screen.kind == .detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Screen title", text: $screen.title)
                .font(PulseFont.bodySemibold(15))
            HStack(spacing: 10) {
                Picker("Kind", selection: $screen.kind) {
                    ForEach(ScreenKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue.capitalized).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .tint(PulseColors.textPrimary)

                if needsEntity {
                    Picker("Entity", selection: entityBinding) {
                        ForEach(entityNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(PulseColors.textPrimary)
                }
                Spacer()
            }
            .font(PulseFont.body(12))
        }
        .padding(.vertical, 2)
    }

    private var entityBinding: Binding<String> {
        Binding(
            get: { screen.entity ?? entityNames.first ?? "" },
            set: { screen.entity = $0 }
        )
    }
}
