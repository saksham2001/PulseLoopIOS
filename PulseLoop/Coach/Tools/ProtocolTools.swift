import Foundation
import SwiftData

// MARK: - Protocol / Medication / Routine Coach Tools
//
// Read + write access to the user's protocol: medications/supplements/peptides
// (`Medication`, `MedicationLog`) and daily routines (`Routine`, `RoutineStep`).
// Reads are always on; writes are gated by `flags.writeToolsEnabled`.
// Logging a dose, creating/updating a medication, and toggling routine steps
// apply immediately; deleting a medication routes through a `.deleteEntity`
// confirm card.
@MainActor
enum ProtocolTools {
    static var readTools: [AnyCoachTool] { [listMedications, getMedicationLog, listRoutines] }
    static var writeTools: [AnyCoachTool] { [logMedicationTaken, addToProtocol, upsertMedication, deleteMedication, toggleRoutineStep, searchProduct] }

    private static let categoryEnum = ["medication", "supplement", "vitamin", "peptide"]
    private static let doseStatusEnum = ["taken", "skipped", "late"]

    private static func meds(_ ctx: ToolExecutionContext) -> [Medication] {
        (try? ctx.modelContext.fetch(FetchDescriptor<Medication>())) ?? []
    }
    private static func routines(_ ctx: ToolExecutionContext) -> [Routine] {
        (try? ctx.modelContext.fetch(FetchDescriptor<Routine>())) ?? []
    }

    private static func medDict(_ m: Medication) -> [String: Any] {
        var d: [String: Any] = [
            "id": m.id.uuidString,
            "name": m.name,
            "dose": m.dose,
            "category": m.categoryRaw,
            "timing": m.timing,
            "is_active": m.isActive,
        ]
        if let i = m.instructions { d["instructions"] = i }
        if let b = m.benefit { d["benefit"] = b }
        return d
    }

    // MARK: list_medications

    private struct ListMedArgs: Decodable {
        let activeOnly: Bool?
        let category: String?
        enum CodingKeys: String, CodingKey { case activeOnly = "active_only", category }
    }

    private static var listMedications: AnyCoachTool {
        .make(
            name: "list_medications",
            label: "Reviewing your protocol",
            description: "List the user's medications, supplements, vitamins, and peptides. Optionally filter by active_only and category (medication/supplement/vitamin/peptide). Returns ids for log_medication_taken, update_medication, delete_medication.",
            parameters: JSONSchema.object([
                "active_only": ["type": ["boolean", "null"]],
                "category": ["type": ["string", "null"], "enum": categoryEnum + [NSNull()]],
            ], required: ["active_only", "category"]),
            argsType: ListMedArgs.self
        ) { args, ctx in
            var items = meds(ctx)
            if args.activeOnly == true { items = items.filter { $0.isActive } }
            if let cat = args.category, !cat.isEmpty { items = items.filter { $0.categoryRaw == cat } }
            return .object(["medications": items.map(medDict), "count": items.count])
        }
    }

    // MARK: get_medication_log

    private struct LogQueryArgs: Decodable {
        let days: Int?
        let medicationId: String?
        enum CodingKeys: String, CodingKey { case days, medicationId = "medication_id" }
    }

    private static var getMedicationLog: AnyCoachTool {
        .make(
            name: "get_medication_log",
            label: "Checking your dose history",
            description: "Get recent medication dose logs (taken/skipped/late) over the last N days (default 7). Optionally filter to one medication_id.",
            parameters: JSONSchema.object([
                "days": ["type": ["integer", "null"]],
                "medication_id": ["type": ["string", "null"]],
            ], required: ["days", "medication_id"]),
            argsType: LogQueryArgs.self
        ) { args, ctx in
            let days = max(1, args.days ?? 7)
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            var logs = ((try? ctx.modelContext.fetch(FetchDescriptor<MedicationLog>())) ?? [])
                .filter { $0.loggedAt >= cutoff }
            if let mid = args.medicationId, let uuid = UUID(uuidString: mid) {
                logs = logs.filter { $0.medicationId == uuid }
            }
            let byId = Dictionary(uniqueKeysWithValues: meds(ctx).map { ($0.id, $0.name) })
            let f = ISO8601DateFormatter()
            let rows = logs.sorted { $0.loggedAt > $1.loggedAt }.prefix(60).map { log -> [String: Any] in
                [
                    "medication": byId[log.medicationId] ?? "Unknown",
                    "status": log.statusRaw,
                    "logged_at": f.string(from: log.loggedAt),
                ]
            }
            return .object(["logs": rows, "count": rows.count, "days": days])
        }
    }

    // MARK: list_routines

    private static var listRoutines: AnyCoachTool {
        .make(
            name: "list_routines",
            label: "Reviewing your routines",
            description: "List the user's daily routines with their steps, streaks, and which steps are done today. Returns step ids for toggle_routine_step.",
            parameters: JSONSchema.empty,
            argsType: NoArgs.self
        ) { _, ctx in
            let rows = routines(ctx).map { r -> [String: Any] in
                [
                    "id": r.id.uuidString,
                    "name": r.name,
                    "time_of_day": r.timeOfDay,
                    "current_streak": r.currentStreak,
                    "steps": r.steps.sorted { $0.order < $1.order }.map { s in
                        ["id": s.id.uuidString, "title": s.title, "done_today": s.completedToday]
                    },
                ]
            }
            return .object(["routines": rows, "count": rows.count])
        }
    }

    // MARK: log_medication_taken

    private struct LogDoseArgs: Decodable {
        let medicationId: String
        let status: String
        enum CodingKeys: String, CodingKey { case medicationId = "medication_id", status }
    }

    private static var logMedicationTaken: AnyCoachTool {
        .make(
            name: "log_medication_taken",
            label: "Logging a dose",
            description: "Log that the user took, skipped, or was late for a medication (status: taken/skipped/late). Applies immediately.",
            parameters: JSONSchema.object([
                "medication_id": JSONSchema.string,
                "status": JSONSchema.enumString(doseStatusEnum),
            ], required: ["medication_id", "status"]),
            argsType: LogDoseArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.medicationId),
                  let med = meds(ctx).first(where: { $0.id == id }) else {
                return .error("medication '\(args.medicationId)' not found. Call list_medications.")
            }
            let status = DoseStatus(rawValue: args.status) ?? .taken
            let log = MedicationLog(medicationId: id, status: status)
            ctx.modelContext.insert(log)
            ctx.modelContext.saveOrLog("coach.protocol")
            return .object(["ok": true, "logged": true, "medication": med.name, "status": status.rawValue])
        }
    }

    // MARK: create_or_update_medication

    private struct UpsertMedArgs: Decodable {
        let medicationId: String?
        let name: String?
        let dose: String?
        let category: String?
        let timing: String?
        let instructions: String?
        let isActive: Bool?
        enum CodingKeys: String, CodingKey {
            case medicationId = "medication_id", name, dose, category, timing, instructions, isActive = "is_active"
        }
    }

    private static var upsertMedication: AnyCoachTool {
        .make(
            name: "create_or_update_medication",
            label: "Updating your protocol",
            description: "Create a new medication/supplement (omit medication_id) or update an existing one (pass medication_id, then only the fields to change). For a new item, name and dose are required. category: medication/supplement/vitamin/peptide. Applies immediately.",
            parameters: JSONSchema.object([
                "medication_id": ["type": ["string", "null"]],
                "name": ["type": ["string", "null"]],
                "dose": ["type": ["string", "null"]],
                "category": ["type": ["string", "null"], "enum": categoryEnum + [NSNull()]],
                "timing": ["type": ["string", "null"]],
                "instructions": ["type": ["string", "null"]],
                "is_active": ["type": ["boolean", "null"]],
            ], required: ["medication_id", "name", "dose", "category", "timing", "instructions", "is_active"]),
            argsType: UpsertMedArgs.self
        ) { args, ctx in
            if let mid = args.medicationId, !mid.isEmpty {
                guard let id = UUID(uuidString: mid), let med = meds(ctx).first(where: { $0.id == id }) else {
                    return .error("medication '\(mid)' not found.")
                }
                var changed: [String] = []
                if let n = args.name, !n.isEmpty { med.name = n; changed.append("name") }
                if let d = args.dose, !d.isEmpty { med.dose = d; changed.append("dose") }
                if let c = args.category, categoryEnum.contains(c) { med.categoryRaw = c; changed.append("category") }
                if let t = args.timing, !t.isEmpty { med.timing = t; changed.append("timing") }
                if let i = args.instructions { med.instructions = i; changed.append("instructions") }
                if let a = args.isActive { med.isActive = a; changed.append("is_active") }
                guard !changed.isEmpty else { return .error("no valid fields to update.") }
                ctx.modelContext.saveOrLog("coach.protocol")
                return .object(["ok": true, "updated": changed, "medication_id": med.id.uuidString, "name": med.name])
            }
            // Create
            guard let name = args.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let dose = args.dose, !dose.isEmpty else {
                return .error("name and dose are required to create a new medication.")
            }
            let category = MedicationCategory(rawValue: args.category ?? "supplement") ?? .supplement
            let med = Medication(name: name, dose: dose, category: category,
                                 timing: args.timing?.isEmpty == false ? args.timing! : "AM",
                                 instructions: args.instructions)
            if let a = args.isActive { med.isActive = a }
            ctx.modelContext.insert(med)
            ctx.modelContext.saveOrLog("coach.protocol")
            return .object(["ok": true, "created": true, "medication_id": med.id.uuidString, "name": med.name])
        }
    }

    // MARK: add_to_protocol (single-shot, fast)

    private struct AddToProtocolArgs: Decodable {
        let name: String
        let dose: String?
        let category: String?
        let timing: String?
    }

    /// One-call "add X to my protocol" — the fast path. Resolves the item's
    /// dose/timing/benefit/mechanism/warnings from the local knowledge base
    /// instantly (BPC-157, creatine, etc. are all bundled), only touching the
    /// network when the name is genuinely unknown, and creates the `Medication`
    /// in the same tool call. This collapses the old search_product →
    /// create_or_update_medication two-round-trip dance into one, so adding is
    /// near-instant. If the item is already on the protocol it's reactivated
    /// rather than duplicated.
    private static var addToProtocol: AnyCoachTool {
        .make(
            name: "add_to_protocol",
            label: "Adding to your protocol",
            description: "FAST single-call way to add a supplement/medication/vitamin/peptide to the user's protocol by name. Auto-fills accurate dose, timing, benefit, mechanism, and warnings from the knowledge base — you only need the name (pass dose/category/timing only to override). Applies immediately. PREFER THIS over search_product + create_or_update_medication whenever the user just wants to add a named item to their protocol/stack.",
            parameters: JSONSchema.object([
                "name": JSONSchema.string,
                "dose": ["type": ["string", "null"]],
                "category": ["type": ["string", "null"], "enum": categoryEnum + [NSNull()]],
                "timing": ["type": ["string", "null"]],
            ], required: ["name", "dose", "category", "timing"]),
            argsType: AddToProtocolArgs.self
        ) { args, ctx in
            let name = args.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return .error("name is required.") }

            // Already on the protocol? Reactivate instead of duplicating.
            if let existing = meds(ctx).first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
                let wasInactive = !existing.isActive
                existing.isActive = true
                if let d = args.dose, !d.isEmpty { existing.dose = d }
                ctx.modelContext.saveOrLog("coach.protocol")
                return .object([
                    "ok": true, "already_existed": true, "reactivated": wasInactive,
                    "medication_id": existing.id.uuidString, "name": existing.name,
                    "dose": existing.dose, "category": existing.categoryRaw, "timing": existing.timing,
                    "summary": "\(existing.name) is \(wasInactive ? "back on" : "already on") your protocol.",
                ])
            }

            // Resolve rich details. Local KB first (instant); only hit the tiered
            // search (network/AI) when the name isn't already known locally.
            var info: SupplementInfo? = SupplementKnowledge.find(name)
                ?? SupplementKnowledge.fuzzyMatch(name).first
                ?? CustomProductStore.find(name, in: ctx.modelContext).map(CustomProductStore.toSupplementInfo)
            if info == nil {
                info = (await ProductSearchService.searchAndPersist(query: name, in: ctx.modelContext)).results.first?.info
            }

            let category = MedicationCategory(rawValue: args.category ?? info?.category ?? "supplement") ?? .supplement
            let dose = args.dose?.isEmpty == false ? args.dose! : (info?.defaultDose ?? "As directed")
            let timing = args.timing?.isEmpty == false ? args.timing! : (info?.timing ?? "AM")

            let med = Medication(
                name: info?.name ?? name,
                dose: dose,
                category: category,
                emoji: info?.emoji ?? "pills.fill",
                timing: timing,
                benefit: info?.benefit,
                mechanism: info?.mechanism,
                interactionNotes: info?.interactionNotes,
                bestTimeReason: info?.bestTimeReason,
                stackNotes: info?.stackNotes
            )
            ctx.modelContext.insert(med)
            ctx.modelContext.saveOrLog("coach.protocol")

            var out: [String: Any] = [
                "ok": true, "created": true,
                "medication_id": med.id.uuidString, "name": med.name,
                "dose": med.dose, "category": med.categoryRaw, "timing": med.timing,
                "summary": "Added \(med.name) (\(med.dose), \(med.timing)) to your protocol.",
            ]
            if let b = med.benefit { out["benefit"] = b }
            if let w = med.interactionNotes { out["warnings"] = w }
            return .object(out)
        }
    }

    // MARK: delete_medication

    private struct MedIdArgs: Decodable {
        let medicationId: String
        enum CodingKeys: String, CodingKey { case medicationId = "medication_id" }
    }

    private static var deleteMedication: AnyCoachTool {
        .make(
            name: "delete_medication",
            label: "Removing from your protocol",
            description: "Permanently delete a medication/supplement by id. Always returns needs_confirmation and shows a Confirm card; deletion only happens after the user taps Confirm. Set response_type to action_confirmation. (To temporarily pause one, set is_active=false via create_or_update_medication instead.)",
            parameters: JSONSchema.object(["medication_id": JSONSchema.string], required: ["medication_id"]),
            argsType: MedIdArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.medicationId),
                  let med = meds(ctx).first(where: { $0.id == id }) else {
                return .error("medication '\(args.medicationId)' not found.")
            }
            ctx.pendingActions.append(PendingAction(
                kind: .deleteEntity,
                summary: "Delete \(med.name) from your protocol? This can't be undone.",
                confirmLabel: "Delete",
                entity: EntityActionPayload(entityType: "medication", id: med.id.uuidString, displayName: med.name)
            ))
            return .object(["ok": true, "needs_confirmation": true,
                            "summary": "Awaiting your confirmation to delete \(med.name)."])
        }
    }

    // MARK: search_product

    private struct SearchProductArgs: Decodable {
        let query: String
    }

    /// Unified product search engine exposed to the Coach. Runs the same tiered
    /// pipeline as the UI (local catalogs + persisted custom entries → Open Food
    /// Facts / openFDA → AI research with citations) and persists discoveries so
    /// they're reusable. Returns structured results the Coach can summarize or feed
    /// into create_or_update_medication.
    private static var searchProduct: AnyCoachTool {
        .make(
            name: "search_product",
            label: "Searching products",
            description: "Search for any food, drug, supplement, vitamin, or peptide by name — including items not yet in the catalog. Runs a tiered search (local catalog, Open Food Facts, FDA, then AI web research) and saves anything new to the user's catalog for reuse. Returns name, category, dose, timing, benefit, mechanism, warnings, source, confidence, citations, and ai_generated. Use this before create_or_update_medication when the user names something you don't already see in list_medications, so you can fill in accurate dose/benefit/interaction details.",
            parameters: JSONSchema.object([
                "query": JSONSchema.string,
            ], required: ["query"]),
            argsType: SearchProductArgs.self
        ) { args, ctx in
            let q = args.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return .error("query is required.") }
            let outcome = await ProductSearchService.searchAndPersist(query: q, in: ctx.modelContext)
            guard !outcome.results.isEmpty else {
                return .object(["query": q, "results": [], "count": 0,
                                "summary": "No product found for '\(q)'."])
            }
            let rows = outcome.results.prefix(5).map { r -> [String: Any] in
                let info = r.info
                var d: [String: Any] = [
                    "name": info.name,
                    "category": info.category,
                    "default_dose": info.defaultDose,
                    "timing": info.timing,
                    "benefit": info.benefit,
                    "mechanism": info.mechanism,
                    "warnings": info.interactionNotes,
                    "source": r.source.rawValue,
                    "confidence": r.confidence,
                    "ai_generated": r.isAIGenerated,
                ]
                if !r.citations.isEmpty { d["citations"] = Array(r.citations.prefix(5)) }
                return d
            }
            return .object([
                "query": q,
                "results": rows,
                "count": rows.count,
                "persisted_to_catalog": outcome.persistedNames,
            ])
        }
    }

    // MARK: toggle_routine_step

    private struct ToggleStepArgs: Decodable {
        let stepId: String
        let done: Bool
        enum CodingKeys: String, CodingKey { case stepId = "step_id", done }
    }

    private static var toggleRoutineStep: AnyCoachTool {
        .make(
            name: "toggle_routine_step",
            label: "Updating a routine",
            description: "Mark a routine step done or not-done for today (use step ids from list_routines). Applies immediately.",
            parameters: JSONSchema.object([
                "step_id": JSONSchema.string,
                "done": JSONSchema.boolean,
            ], required: ["step_id", "done"]),
            argsType: ToggleStepArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.stepId) else { return .error("invalid step_id.") }
            let allSteps = routines(ctx).flatMap { $0.steps }
            guard let step = allSteps.first(where: { $0.id == id }) else {
                return .error("routine step '\(args.stepId)' not found. Call list_routines.")
            }
            step.completedToday = args.done
            ctx.modelContext.saveOrLog("coach.protocol")
            return .object(["ok": true, "step_id": step.id.uuidString, "title": step.title, "done_today": step.completedToday])
        }
    }
}
