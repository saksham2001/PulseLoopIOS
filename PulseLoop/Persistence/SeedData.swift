import Foundation
import SwiftData

enum SeedData {
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let descriptor = FetchDescriptor<Device>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }
        seedDemo(context, completeOnboarding: true)
    }
    
    @MainActor
    static func seedDemo(_ context: ModelContext, completeOnboarding: Bool = false) {
        let calendar = Calendar.current
        let now = Date()
        
        let profile = UserProfile(
            name: "Rey",
            age: 25,
            sex: "not set",
            heightCm: 178,
            weightKg: 73,
            onboardingCompleted: completeOnboarding,
            baselineCompleted: false
        )
        context.insert(profile)
        context.insert(UserGoal(steps: 10000, sleepMinutes: 480, activeMinutes: 45, workoutsPerWeek: 4))
        context.insert(Device(advertisedName: "SMART_RING", bleAddressHint: "41:42:2e:c7:5b:6a", batteryPercent: 82, state: .connected))

        // ~90 days of daily activity so Week/Month/Year range graphs render fully.
        for offset in stride(from: -89, through: 0, by: 1) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            let isWeekend = weekday == 1 || weekday == 7
            // Weekly rhythm + slow upward trend + deterministic wobble.
            let base = 7600.0 + Double(offset + 89) * 9
            let wobble = sin(Double(offset) * 0.9) * 1400 + Double((abs(offset) * 37) % 900)
            let steps = max(2600, Int(base + wobble - (isWeekend ? 1500 : 0)))
            context.insert(
                ActivityDaily(
                    date: date,
                    steps: steps,
                    calories: Double(steps) * 0.045 + 120,
                    distanceMeters: Double(steps) * 0.72,
                    activeMinutes: max(8, steps / 230)
                )
            )
        }

        // Dense recent HR/SpO2 samples for the Vitals charts.
        for hour in stride(from: -24, through: 0, by: 1) {
            guard let ts = calendar.date(byAdding: .hour, value: hour, to: now) else { continue }
            let hr = 60 + Int((sin(Double(hour) * 0.7) + 1) * 14) + abs(hour % 5)
            context.insert(Measurement(kind: .heartRate, value: Double(hr), unit: "bpm", timestamp: ts, source: .mock))
        }
        for hour in stride(from: -22, through: 0, by: 3) {
            guard let ts = calendar.date(byAdding: .hour, value: hour, to: now) else { continue }
            context.insert(Measurement(kind: .spo2, value: Double(96 + abs(hour % 4 == 0 ? 3 : abs(hour) % 3)), unit: "%", timestamp: ts, source: .mock))
        }

        // ~30 nights of sleep with stage blocks + per-night scores.
        for i in 0..<30 {
            guard let dayDate = calendar.date(byAdding: .day, value: -i, to: calendar.startOfDay(for: now)) else { continue }
            let totalMin = 360 + Int((sin(Double(i) * 0.8) + 1) * 70) + (i % 3 == 0 ? -25 : 15)
            let wake = calendar.date(bySettingHour: 7, minute: 10, second: 0, of: dayDate) ?? dayDate
            let startAt = calendar.date(byAdding: .minute, value: -totalMin, to: wake) ?? dayDate
            let blocks = stageBlocks(total: totalMin, start: startAt)
            let light = blocks.filter { $0.stage == .light }.reduce(0) { $0 + $1.durationMinutes }
            let deep = blocks.filter { $0.stage == .deep }.reduce(0) { $0 + $1.durationMinutes }
            let awake = blocks.filter { $0.stage == .awake }.reduce(0) { $0 + $1.durationMinutes }
            let summary = SleepSummary(
                session: SleepSession(date: dayDate, startAt: startAt, endAt: wake, totalMinutes: totalMin),
                lightMinutes: light, deepMinutes: deep, awakeMinutes: awake, blocks: blocks
            )
            let score = SleepScore.calculate(summary)
            let session = SleepSession(date: dayDate, startAt: startAt, endAt: wake, totalMinutes: totalMin, score: score.score, syncedAt: wake)
            context.insert(session)
            for block in blocks {
                context.insert(SleepStageBlock(sessionId: session.id, startAt: block.startAt, startMinute: block.startMinute, durationMinutes: block.durationMinutes, stage: block.stage))
            }
        }

        // Several finished workouts across recent days (one today). `origin` seeds a synthetic
        // GPS loop so the route map renders in the Simulator (which has no real GPS).
        let workouts: [(offset: Int, type: String, minutes: Int, distance: Double, calories: Double, origin: (Double, Double)?)] = [
            (0,  "run",  38, 6100,  330, (40.4443, -79.9436)),   // CMU / Pittsburgh
            (-1, "walk", 52, 4200,  210, (40.4406, -79.9959)),
            (-3, "cycle", 64, 18400, 460, (40.4612, -79.9249)),
            (-6, "gym",  45, 0,     280, nil),
            (-10, "run", 41, 7300,  372, (40.4280, -79.9420))
        ]
        for workout in workouts {
            let dayStart = calendar.date(byAdding: .day, value: workout.offset, to: now) ?? now
            let start = calendar.date(bySettingHour: 18, minute: 5, second: 0, of: dayStart) ?? dayStart
            let end = calendar.date(byAdding: .minute, value: workout.minutes, to: start)
            let useGps = workout.origin != nil
            let session = ActivitySession(type: workout.type, status: .finished, startedAt: start, endedAt: end, calories: workout.calories, distanceMeters: workout.distance > 0 ? workout.distance : nil, notes: nil, useGps: useGps)
            session.avgHeartRate = 132 + Double(abs(workout.offset) % 12)
            session.minHeartRate = 108
            session.maxHeartRate = 158 + Double(abs(workout.offset) % 8)
            session.avgSpO2 = 97
            session.latestSpO2 = 97
            session.perceivedEffort = "moderate"
            context.insert(session)
            context.insert(ActivityEvent(sessionId: session.id, kind: "finished"))
            if let origin = workout.origin {
                seedRoute(context, sessionId: session.id, start: start, durationMinutes: workout.minutes, origin: origin)
            }
        }
        
        let conversation = CoachConversation(title: "Recovery check")
        context.insert(conversation)
        context.insert(CoachMessage(conversationId: conversation.id, role: "assistant", body: "Your sleep is synced and activity is trending above baseline. Keep today's effort steady unless your HR stays elevated."))
        
        context.insert(RawPacketRow(direction: .incoming, commandId: 0x03, hexPayload: "03112233447e240000a51a000064010000000000", decodedKind: "activity", decodedJSON: #"{"steps":9342}"#, confidence: .known))
        context.insert(RawPacketRow(direction: .outgoing, commandId: 0x0c, hexPayload: "0c00000000000000000000000000000000000000", decodedKind: "status_command", confidence: .known))
        context.insert(DerivedUpdateRow(kind: "seed", entityType: "database", entityId: "demo", payloadJSON: #"{"source":"SeedData"}"#))

        seedLifeOS(context)
        
        context.saveOrLog("seed")
    }

    /// Seeds the built-in exercise library if it's empty. Safe to call on every
    /// launch — only inserts when no non-custom exercises exist yet.
    @MainActor
    static func seedExerciseCatalogIfNeeded(_ context: ModelContext) {
        let descriptor = FetchDescriptor<Exercise>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }
        for exercise in ExerciseCatalog.makeAll() {
            context.insert(exercise)
        }
        context.saveOrLog("seed")
    }

    /// Seeds a couple of demo workout templates plus a week of journal entries.
    @MainActor
    private static func seedFitnessAndJournal(_ context: ModelContext) {
        seedExerciseCatalogIfNeeded(context)

        let all = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        func find(_ name: String, _ equipment: Equipment) -> Exercise? {
            all.first { $0.name == name && $0.equipment == equipment } ?? all.first { $0.name == name }
        }

        // Template 1 — Push day
        let push = WorkoutTemplate(name: "Push Day")
        push.lastPerformed = Calendar.current.date(byAdding: .day, value: -2, to: Date())
        let pushPlan: [(String, Equipment, [(Int, Double)])] = [
            ("Bench Press", .barbell, [(8, 60), (8, 60), (6, 70)]),
            ("Incline Bench Press", .dumbbellDouble, [(10, 22), (10, 22)]),
            ("Overhead Press", .barbell, [(8, 40), (8, 40)]),
            ("Tricep Pushdown", .rope, [(12, 25), (12, 25)]),
        ]
        for (i, p) in pushPlan.enumerated() {
            guard let ex = find(p.0, p.1) else { continue }
            let te = TemplateExercise(exercise: ex, order: i)
            te.sets = p.2.enumerated().map { ExerciseSet(order: $0.offset, reps: $0.element.0, weightKg: $0.element.1) }
            push.exercises.append(te)
        }
        context.insert(push)

        // Template 2 — Pull day
        let pull = WorkoutTemplate(name: "Pull Day")
        pull.lastPerformed = Calendar.current.date(byAdding: .day, value: -4, to: Date())
        let pullPlan: [(String, Equipment, [(Int, Double)])] = [
            ("Deadlift", .barbell, [(5, 100), (5, 110), (3, 120)]),
            ("Lat Pulldown", .cableSingle, [(10, 50), (10, 50)]),
            ("Bent Over Row", .barbell, [(8, 60), (8, 60)]),
            ("Bicep Curl", .dumbbellDouble, [(12, 14), (12, 14)]),
        ]
        for (i, p) in pullPlan.enumerated() {
            guard let ex = find(p.0, p.1) else { continue }
            let te = TemplateExercise(exercise: ex, order: i)
            te.sets = p.2.enumerated().map { ExerciseSet(order: $0.offset, reps: $0.element.0, weightKg: $0.element.1) }
            pull.exercises.append(te)
        }
        context.insert(pull)

        // Journal — last 6 days of tri-state entries.
        let cal = Calendar.current
        let toggleKeys = ["added_sugar", "morning_sunlight", "keto_diet", "device_in_bed", "late_meal"]
        let scoreKeys = ["stress_score", "nutrition_score"]
        for offset in 0..<6 {
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let day = JournalDay(date: date)
            for (i, key) in toggleKeys.enumerated() {
                let state = (offset + i) % 3 == 0 ? 1 : ((offset + i) % 3 == 1 ? -1 : 0)
                if state != 0 { day.entries.append(JournalMetricEntry(metricKey: key, state: state)) }
            }
            for key in scoreKeys {
                day.entries.append(JournalMetricEntry(metricKey: key, state: offset % 2 == 0 ? 1 : 0))
            }
            day.entries.append(JournalMetricEntry(metricKey: "alcohol", state: offset == 1 ? 1 : 0, amount: offset == 1 ? 2 : nil))
            day.entries.append(JournalMetricEntry(metricKey: "caffeine", state: 1, amount: 120))
            context.insert(day)
        }

        context.saveOrLog("seed")
    }

    @MainActor
    private static func seedLifeOS(_ context: ModelContext) {
        // Collections
        let collections = [
            ("doc.text", "Notes"), ("pills.fill", "Protocol"), ("book.closed.fill", "Journal"), ("target", "Goals"),
            ("person.2", "People"), ("bookmark.fill", "Bookmarks"), ("airplane", "Travel"), ("creditcard", "Money")
        ]
        for (i, c) in collections.enumerated() {
            context.insert(Collection(name: c.1, emoji: c.0, order: i))
        }

        // Tasks
        let tasks: [(String, TaskStatus, String, String?)] = [
            ("Draft Q3 strategy outline", .todo, "Today", "Work"),
            ("Review PulseLoop research notes", .inProgress, "Today", "Doing"),
            ("Reply to Maya about the launch", .todo, "Today", "Today"),
            ("Plan trip itinerary", .todo, "This week", "Wed"),
            ("Reorder peptide supplies", .todo, "This week", "Thu"),
            ("Book bloodwork panel", .inProgress, "This week", "Health"),
            ("Send weekly review", .done, "Done", nil),
            ("Book dentist", .done, "Done", nil),
            ("Scope AI coach v2", .inProgress, "This week", "Projects"),
        ]
        for (i, t) in tasks.enumerated() {
            context.insert(TaskItem(title: t.0, status: t.1, group: t.2, label: t.3, order: i))
        }

        // Weighted, day-assigned tasks for the Week planner ("Weekline") view.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: weekStart) ?? today }
        // (title, status, dayOffset (nil = Week Edge), weight)
        let weekTasks: [(String, TaskStatus, Int?, Int)] = [
            ("Deep work: presentation draft", .todo, 2, 6),
            ("Call the dentist", .todo, 2, 1),
            ("Pay the electricity bill", .todo, 2, 2),
            ("Review meeting notes", .todo, 2, 2),
            ("Finish the project brief", .todo, 1, 4),
            ("Pick up birthday gift", .todo, 1, 2),
            ("Pick up the package", .todo, 3, 3),
            ("Clean room", .todo, 4, 2),
            ("Send the insurance form", .todo, nil, 3),
            ("Plan dinners for the week", .done, nil, 2),
            ("Reply to the landlord", .done, nil, 2),
        ]
        for (i, t) in weekTasks.enumerated() {
            let due = t.2.map(day)
            context.insert(TaskItem(title: t.0, status: t.1, group: "Week", dueDate: due, order: 100 + i, weight: t.3))
        }
        context.insert(TaskBoard(name: "Default", columns: ["To do", "In progress", "Done"]))

        // Notes
        let note = Note(title: "Q3 product strategy", aiSummary: "Focus Q3 on retention over acquisition. Ship the AI coach v2, cut two low-usage features, and run a pricing test in August.")
        context.insert(note)
        context.insert(NoteBlock(noteId: note.id, order: 0, kind: .paragraph, content: "We're entering Q3 with strong retention signals but flat top-of-funnel growth."))
        context.insert(NoteBlock(noteId: note.id, order: 1, kind: .heading, content: "Key decisions"))
        context.insert(NoteBlock(noteId: note.id, order: 2, kind: .todo, content: "Lock the Q3 OKRs with leadership"))
        context.insert(NoteBlock(noteId: note.id, order: 3, kind: .todo, content: "Scope the AI coach v2 milestones"))
        context.insert(NoteBlock(noteId: note.id, order: 4, kind: .todo, content: "Draft the August pricing experiment"))

        // Medications / Supplements / Peptides (enriched with AI metadata)
        context.insert(Medication(name: "Vitamin D3", dose: "2,000 IU · with breakfast", category: .supplement, emoji: "☀️", timing: "AM",
            benefit: "Supports bone health, immune function, and mood regulation",
            mechanism: "Fat-soluble secosteroid that regulates calcium absorption and immune cell activity",
            interactionNotes: "Space 2h from magnesium for optimal uptake",
            bestTimeReason: "Take with a fat-containing meal for 50% better absorption",
            stackNotes: "Synergizes with K2 for proper calcium routing to bones instead of arteries"))
        context.insert(Medication(name: "Omega-3", dose: "1,000 mg · with breakfast", category: .supplement, emoji: "drop.fill", timing: "AM",
            benefit: "Reduces inflammation, supports brain and heart health",
            mechanism: "EPA/DHA integrate into cell membranes, modulating inflammatory pathways",
            interactionNotes: "May increase bleeding risk with blood thinners at high doses",
            bestTimeReason: "Take with meals to reduce fishy aftertaste and improve absorption",
            stackNotes: "Complements D3 absorption (provides fat vehicle)"))
        context.insert(Medication(name: "Metformin", dose: "500 mg · with meals", category: .medication, emoji: "pills.fill", timing: "2×",
            benefit: "Blood sugar regulation, longevity, AMPK activation",
            mechanism: "Inhibits hepatic glucose production and activates AMPK for cellular energy sensing",
            interactionNotes: "Depletes B12 over time  -  supplement B12 if using long-term",
            bestTimeReason: "With meals to reduce GI side effects",
            stackNotes: "Consider pairing with B12 and CoQ10"))
        context.insert(Medication(name: "Magnesium", dose: "400 mg · before bed", category: .supplement, emoji: "moon.fill", timing: "PM",
            benefit: "Supports sleep quality, muscle relaxation, and 300+ enzymatic reactions",
            mechanism: "Cofactor for ATP production, GABA receptor agonist promoting calm",
            interactionNotes: "Space 2h from calcium and D3  -  they compete for absorption",
            bestTimeReason: "PM dosing leverages calming effect for better sleep onset",
            stackNotes: "Pairs well with zinc and B6 for sleep (ZMA stack)"))
        context.insert(Medication(name: "Creatine", dose: "5 g · daily", category: .supplement, emoji: "figure.strengthtraining.traditional", timing: "AM",
            benefit: "Increases strength, power output, and cognitive performance",
            mechanism: "Replenishes phosphocreatine stores for rapid ATP regeneration",
            interactionNotes: "Stay well-hydrated. No significant negative interactions",
            bestTimeReason: "Timing doesn't matter much  -  consistency is key",
            stackNotes: "Safe to combine with most supplements. Pairs with protein for muscle gains"))
        context.insert(Medication(name: "Vitamin C", dose: "500 mg · daily", category: .vitamin, emoji: "drop.fill", timing: "AM",
            benefit: "Antioxidant, immune support, collagen synthesis, iron absorption",
            mechanism: "Electron donor that neutralizes free radicals and enables hydroxylation reactions",
            interactionNotes: "High doses may reduce copper absorption",
            bestTimeReason: "AM with food to reduce GI irritation",
            stackNotes: "Enhances iron absorption  -  take together if supplementing iron"))
        context.insert(Medication(name: "Zinc", dose: "15 mg · before bed", category: .supplement, emoji: "shield.fill", timing: "PM",
            benefit: "Immune function, testosterone support, wound healing",
            mechanism: "Cofactor for 100+ enzymes, supports thymus function and T-cell maturation",
            interactionNotes: "Competes with copper and iron  -  space from iron supplements by 2h",
            bestTimeReason: "PM with magnesium for sleep support (ZMA effect)",
            stackNotes: "Pairs with magnesium and B6 for sleep. Take with copper long-term"))
        context.insert(Medication(name: "BPC-157", dose: "250 mcg · SC · cycle day 14/28", category: .peptide, emoji: "syringe.fill", timing: "AM",
            benefit: "Accelerates tissue repair, gut healing, and tendon/ligament recovery",
            mechanism: "Upregulates growth factor receptors (VEGF, FGF) and nitric oxide pathways",
            interactionNotes: "Avoid NSAIDs which may counteract healing pathways",
            bestTimeReason: "Inject subcutaneously AM near injury site or abdomen for systemic effect",
            stackNotes: "Often stacked with TB-500 for enhanced tissue repair"))
        context.insert(Medication(name: "Ipamorelin", dose: "200 mcg · SC · before bed", category: .peptide, emoji: "syringe.fill", timing: "PM",
            benefit: "Stimulates growth hormone release for recovery, fat loss, and sleep quality",
            mechanism: "Selective ghrelin mimetic that triggers pulsatile GH release from pituitary",
            interactionNotes: "Fast 2h before injection. Avoid with food/carbs that spike insulin",
            bestTimeReason: "Before bed on empty stomach  -  aligns with natural GH pulse during deep sleep",
            stackNotes: "Often combined with CJC-1295 (no DAC) for amplified GH release"))

        // Routines
        let morning = Routine(name: "Morning routine", emoji: "sunrise.fill", timeOfDay: "morning", currentStreak: 24)
        context.insert(morning)
        for (i, step) in ["Hydrate", "Stretch", "Morning stack", "Journal", "Meditate"].enumerated() {
            context.insert(RoutineStep(routineId: morning.id, title: step, order: i, completedToday: true))
        }
        let evening = Routine(name: "Evening wind-down", emoji: "moon.fill", timeOfDay: "evening", currentStreak: 18)
        context.insert(evening)
        for (i, step) in ["No screens", "Magnesium", "Journal", "Lights out"].enumerated() {
            context.insert(RoutineStep(routineId: evening.id, title: step, order: i, completedToday: false))
        }

        // Meals
        context.insert(MealLog(name: "Breakfast", description_: "Greek yogurt, berries, granola", emoji: "cup.and.saucer.fill", calories: 420, proteinG: 28))
        context.insert(MealLog(name: "Snack", description_: "Protein shake · oat milk", emoji: "☕", calories: 180, proteinG: 30))
        context.insert(MealLog(name: "Lunch", description_: "Chicken bowl, rice, greens", emoji: "fork.knife", calories: 640, proteinG: 38, isPlanned: true))

        // Inbox items
        context.insert(InboxItem(title: "Electric bill  -  $84", subtitle: "Gmail · due Jun 22", source: .gmail, icon: "✉︎", suggestedAction: "Task · pay by Jun 22", actionType: .createTask))
        context.insert(InboxItem(title: "Your order ships today", subtitle: "Amazon · arriving Wed", source: .gmail, icon: "shippingbox", suggestedAction: "Track shipment", actionType: .trackShipment))
        context.insert(InboxItem(title: "Magnesium Glycinate restocked", subtitle: "Amazon · 120ct bottle arriving Thu", source: .gmail, icon: "pills.fill", suggestedAction: "Add to Protocol · 400mg", actionType: .addToProtocol, detectedProduct: "Magnesium Glycinate", detectedDose: "400mg"))
        context.insert(InboxItem(title: "Vitamin D3 running low", subtitle: "iHerb · reorder reminder", source: .gmail, icon: "sun.max.fill", suggestedAction: "Restock reminder · 30 days", actionType: .restockReminder, detectedProduct: "Vitamin D3", detectedDose: "2,000 IU"))
        context.insert(InboxItem(title: "Dentist appointment", subtitle: "Gmail invite · Thu 3:00 PM", source: .gmail, icon: "calendar.badge.clock", suggestedAction: "Add to calendar", actionType: .addToCalendar))
        context.insert(InboxItem(title: "Maya: can you review the deck?", subtitle: "Gmail · launch", source: .gmail, icon: "#", suggestedAction: "Reply by voice", actionType: .reply))
        context.insert(InboxItem(title: "BPC-157 order confirmed", subtitle: "Peptide Sciences · ships Mon", source: .gmail, icon: "syringe", suggestedAction: "Add to Protocol · 250mcg", actionType: .addToProtocol, detectedProduct: "BPC-157", detectedDose: "250mcg"))
        context.insert(InboxItem(title: "Slack: team standup reminder", subtitle: "Slack · #general", source: .slack, icon: "#", suggestedAction: "Join call", actionType: .joinCall))

        // Connected accounts
        context.insert(ConnectedAccount(provider: .gmail, displayName: "Gmail", isConnected: true))
        context.insert(ConnectedAccount(provider: .googleCalendar, displayName: "Google Calendar", isConnected: true))
        context.insert(ConnectedAccount(provider: .appleWatch, displayName: "Apple Watch", isConnected: false))
        context.insert(ConnectedAccount(provider: .slack, displayName: "Slack", isConnected: false))

        // Subscriptions
        context.insert(Subscription(name: "Spotify", emoji: "music.note", monthlyAmount: 11))
        context.insert(Subscription(name: "ChatGPT Plus", emoji: "brain", monthlyAmount: 20))
        context.insert(Subscription(name: "iCloud+", emoji: "icloud.fill", monthlyAmount: 3))
        context.insert(Subscription(name: "Notion", emoji: "doc.text", monthlyAmount: 8))
        context.insert(Subscription(name: "YouTube Premium", emoji: "play.rectangle.fill", monthlyAmount: 14))

        // Audit log
        context.insert(AuditLogEntry(actionDescription: "Read 14 emails, flagged 6 as actions", sourceContext: "Gmail"))
        context.insert(AuditLogEntry(actionDescription: "Added \"Pay electric bill\" to tasks", sourceContext: nil))
        context.insert(AuditLogEntry(actionDescription: "Drafted 2 replies in your writing style", sourceContext: "Gmail"))

        // Permission gates
        context.insert(PermissionGate(actionType: "draft_replies", permissionLevel: "allowed"))
        context.insert(PermissionGate(actionType: "send_messages", permissionLevel: "ask"))
        context.insert(PermissionGate(actionType: "reschedule_events", permissionLevel: "ask"))
        context.insert(PermissionGate(actionType: "pay_bills", permissionLevel: "ask"))

        seedFitnessAndJournal(context)
    }
    
    @MainActor
    static func clearAll(_ context: ModelContext) {
        deleteAll(Device.self, context)
        deleteAll(ActivityDaily.self, context)
        deleteAll(Measurement.self, context)
        deleteAll(SleepSession.self, context)
        deleteAll(SleepStageBlock.self, context)
        deleteAll(RawPacketRow.self, context)
        deleteAll(DerivedUpdateRow.self, context)
        deleteAll(UserProfile.self, context)
        deleteAll(UserGoal.self, context)
        deleteAll(ActivitySession.self, context)
        deleteAll(ActivitySample.self, context)
        deleteAll(ActivityGpsPoint.self, context)
        deleteAll(ActivityEvent.self, context)
        deleteAll(CoachConversation.self, context)
        deleteAll(CoachMessage.self, context)
        deleteAll(CoachMemory.self, context)
        deleteAll(CoachToolCall.self, context)
        // Life OS models
        deleteAll(Note.self, context)
        deleteAll(NoteBlock.self, context)
        deleteAll(TaskItem.self, context)
        deleteAll(TaskBoard.self, context)
        deleteAll(Collection.self, context)
        deleteAll(InboxItem.self, context)
        deleteAll(ConnectedAccount.self, context)
        deleteAll(Routine.self, context)
        deleteAll(RoutineStep.self, context)
        deleteAll(Medication.self, context)
        deleteAll(MedicationLog.self, context)
        deleteAll(MealLog.self, context)
        deleteAll(Subscription.self, context)
        deleteAll(AuditLogEntry.self, context)
        deleteAll(PermissionGate.self, context)
        deleteAll(DayPlan.self, context)
        deleteAll(DayPlanAction.self, context)
        // Fitness & Journal
        deleteAll(Exercise.self, context)
        deleteAll(WorkoutTemplate.self, context)
        deleteAll(TemplateExercise.self, context)
        deleteAll(ExerciseSet.self, context)
        deleteAll(JournalDay.self, context)
        deleteAll(JournalMetricEntry.self, context)
        // AI knowledge base
        deleteAll(DailyLearning.self, context)
        context.saveOrLog("seed")
    }
    
    /// Builds a plausible hypnogram for a night, scaled to `total` minutes. The
    /// returned blocks carry a placeholder sessionId; callers re-key them to the
    /// real session when persisting.
    private static func stageBlocks(total: Int, start: Date) -> [SleepStageBlock] {
        // Reference pattern (sums to 455m); scaled to the requested total.
        let pattern: [(SleepStage, Int)] = [
            (.light, 58), (.deep, 46), (.light, 92), (.awake, 12),
            (.deep, 71), (.light, 126), (.awake, 10), (.light, 40)
        ]
        let referenceTotal = pattern.reduce(0) { $0 + $1.1 }
        let scale = Double(total) / Double(referenceTotal)
        let placeholder = UUID()
        var cursor = start
        var minute = 0
        var blocks: [SleepStageBlock] = []
        for (index, item) in pattern.enumerated() {
            let duration = index == pattern.count - 1
                ? max(1, total - minute) // absorb rounding into the last block
                : max(1, Int((Double(item.1) * scale).rounded()))
            blocks.append(SleepStageBlock(sessionId: placeholder, startAt: cursor, startMinute: minute, durationMinutes: duration, stage: item.0))
            cursor = Calendar.current.date(byAdding: .minute, value: duration, to: cursor) ?? cursor
            minute += duration
        }
        return blocks
    }
    
    /// Inserts a synthetic GPS loop (~60 points) around `origin` so the route map has data to draw
    /// in the Simulator. The path is a gently wobbling closed loop, not a real recording.
    private static func seedRoute(_ context: ModelContext, sessionId: UUID, start: Date, durationMinutes: Int, origin: (Double, Double)) {
        let count = 60
        let radius = 0.006 // ~600 m
        for i in 0..<count {
            let t = Double(i) / Double(count) * 2 * Double.pi
            let wobble = 0.0012 * sin(t * 5)
            let lat = origin.0 + (radius + wobble) * sin(t)
            let lon = origin.1 + (radius + wobble) * cos(t) * 1.3
            let ts = start.addingTimeInterval(Double(durationMinutes) * 60 * Double(i) / Double(count))
            context.insert(ActivityGpsPoint(sessionId: sessionId, latitude: lat, longitude: lon, horizontalAccuracy: 5, timestamp: ts))
        }
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) {
        let rows = (try? context.fetch(FetchDescriptor<T>())) ?? []
        for row in rows {
            context.delete(row)
        }
    }
}
