import Foundation

// MARK: - SubAppSpec diff + change classification (Life OS T5)
//
// A pure structural comparison of two `SubAppSpec`s used by the self-improvement
// pipeline to (a) describe a proposed change to the user and (b) classify it as
// breaking vs non-breaking so auto-apply can be limited to safe, additive changes.
//
// Classification rules (conservative — when unsure, treat as breaking):
//   NON-BREAKING (additive, data-preserving):
//     - a new entity
//     - a new (optional) field on an existing entity
//     - a new screen
//     - relabeling (label/title text only)
//   BREAKING (may drop or invalidate existing data):
//     - removing an entity, field, or screen
//     - changing a field's type
//     - making an existing field required
//     - a schema major-version change

struct SubAppSpecDiff: Equatable {
    var addedEntities: [String] = []
    var removedEntities: [String] = []
    var addedFields: [String] = []          // "entity.field"
    var removedFields: [String] = []        // "entity.field"
    var changedFieldTypes: [String] = []    // "entity.field"
    var newlyRequiredFields: [String] = []  // "entity.field"
    var addedScreens: [String] = []
    var removedScreens: [String] = []
    var relabeled: [String] = []
    var schemaMajorChanged = false

    /// No structural change at all (labels aside).
    var isEmpty: Bool {
        addedEntities.isEmpty && removedEntities.isEmpty && addedFields.isEmpty
            && removedFields.isEmpty && changedFieldTypes.isEmpty && newlyRequiredFields.isEmpty
            && addedScreens.isEmpty && removedScreens.isEmpty && relabeled.isEmpty
            && !schemaMajorChanged
    }

    /// True when applying the change could drop or invalidate existing user data.
    var isBreaking: Bool {
        !removedEntities.isEmpty || !removedFields.isEmpty || !changedFieldTypes.isEmpty
            || !newlyRequiredFields.isEmpty || !removedScreens.isEmpty || schemaMajorChanged
    }

    /// Short, user-facing bullet notes describing what changed.
    var notes: [String] {
        var out: [String] = []
        if !addedEntities.isEmpty { out.append("Adds: \(addedEntities.joined(separator: ", "))") }
        if !addedFields.isEmpty { out.append("New fields: \(addedFields.joined(separator: ", "))") }
        if !addedScreens.isEmpty { out.append("New screens: \(addedScreens.joined(separator: ", "))") }
        if !relabeled.isEmpty { out.append("Renamed labels: \(relabeled.joined(separator: ", "))") }
        if !removedEntities.isEmpty { out.append("Removes: \(removedEntities.joined(separator: ", "))") }
        if !removedFields.isEmpty { out.append("Removes fields: \(removedFields.joined(separator: ", "))") }
        if !changedFieldTypes.isEmpty { out.append("Changes field types: \(changedFieldTypes.joined(separator: ", "))") }
        if !newlyRequiredFields.isEmpty { out.append("Now required: \(newlyRequiredFields.joined(separator: ", "))") }
        if !removedScreens.isEmpty { out.append("Removes screens: \(removedScreens.joined(separator: ", "))") }
        if schemaMajorChanged { out.append("Schema version change") }
        return out
    }

    /// Compute the diff from `old` to `new`.
    static func between(_ old: SubAppSpec, _ new: SubAppSpec) -> SubAppSpecDiff {
        var diff = SubAppSpecDiff()
        diff.schemaMajorChanged = old.schemaVersion.major != new.schemaVersion.major

        let oldEntities = Dictionary(uniqueKeysWithValues: old.entities.map { ($0.name, $0) })
        let newEntities = Dictionary(uniqueKeysWithValues: new.entities.map { ($0.name, $0) })

        for name in newEntities.keys where oldEntities[name] == nil { diff.addedEntities.append(name) }
        for name in oldEntities.keys where newEntities[name] == nil { diff.removedEntities.append(name) }

        for (name, newEntity) in newEntities {
            guard let oldEntity = oldEntities[name] else { continue }
            if oldEntity.label != newEntity.label { diff.relabeled.append("\(name) entity") }
            let oldFields = Dictionary(uniqueKeysWithValues: oldEntity.fields.map { ($0.name, $0) })
            let newFields = Dictionary(uniqueKeysWithValues: newEntity.fields.map { ($0.name, $0) })
            for f in newFields.keys where oldFields[f] == nil {
                diff.addedFields.append("\(name).\(f)")
                // A brand-new REQUIRED field is breaking: existing records have no
                // value for it, so they'd violate the new constraint.
                if newFields[f]?.required == true { diff.newlyRequiredFields.append("\(name).\(f)") }
            }
            for f in oldFields.keys where newFields[f] == nil { diff.removedFields.append("\(name).\(f)") }
            for (f, newField) in newFields {
                guard let oldField = oldFields[f] else { continue }
                if oldField.type != newField.type { diff.changedFieldTypes.append("\(name).\(f)") }
                if !oldField.required && newField.required { diff.newlyRequiredFields.append("\(name).\(f)") }
                if oldField.label != newField.label { diff.relabeled.append("\(name).\(f)") }
            }
        }

        let oldScreens = Set(old.screens.map { $0.id })
        let newScreens = Set(new.screens.map { $0.id })
        diff.addedScreens = newScreens.subtracting(oldScreens).sorted()
        diff.removedScreens = oldScreens.subtracting(newScreens).sorted()

        // Stable ordering for deterministic notes/tests.
        diff.addedEntities.sort(); diff.removedEntities.sort()
        diff.addedFields.sort(); diff.removedFields.sort()
        diff.changedFieldTypes.sort(); diff.newlyRequiredFields.sort()
        diff.relabeled.sort()
        return diff
    }
}
