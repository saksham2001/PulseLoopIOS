import Foundation
import SwiftData

/// Composes the `CoachContextPacket` from the app's existing derived summaries
/// and repositories  -  the Swift analogue of `build_coach_context`. Runs on the
/// main actor because it reads SwiftData via the `@MainActor` services.
@MainActor
enum CoachContextBuilder {
    static func build(
        context: ModelContext,
        conversationSummary: String? = nil,
        now: Date = Date()
    ) -> CoachContextPacket {
        let summary = MetricsService.buildTodaySummary(context: context)
        let profile = ProfileRepository.profile(context: context)
        let device = DeviceRepository.current(context: context)

        let completeness = profileCompleteness(profile)
        let stepsPoints = summary.trends.steps7d
        let daysAvailable = stepsPoints.filter { $0.value > 0 }.count
        let weekSteps = stepsPoints.map { Int($0.value) }
        let mostActive = stepsPoints.max(by: { $0.value < $1.value })

        let profileContext = CoachContextPacket.ProfileContext(
            name: profile?.name, age: profile?.age, sex: profile?.sex,
            heightCm: profile?.heightCm, weightKg: profile?.weightKg,
            completeness: completeness
        )

        let deviceContext = CoachContextPacket.DeviceContext(
            name: device?.name,
            batteryPercent: device?.batteryPercent,
            state: (device?.state ?? .idle).rawValue,
            lastConnectedAt: device?.lastConnectedAt.map(iso),
            lastSyncAt: device?.lastSyncAt.map(iso)
        )

        let goals = CoachContextPacket.GoalContext(
            stepsDaily: summary.goals.stepsDaily,
            activeMinutesDaily: summary.goals.activeMinutesDaily,
            sleepHours: summary.goals.sleepHours,
            exerciseDaysWeekly: summary.goals.exerciseDaysWeekly
        )

        let today = CoachContextPacket.DayContext(
            localDate: localDate(summary.date),
            steps: summary.steps,
            calories: summary.calories,
            distanceKm: summary.distanceMeters.map { ($0 / 1000).rounded(toPlaces: 2) },
            activeMinutes: summary.activeMinutes,
            dataConfidence: dataConfidence(summary)
        )

        let week = CoachContextPacket.WeekContext(
            daysAvailable: daysAvailable,
            avgSteps: weekSteps.isEmpty ? nil : weekSteps.reduce(0, +) / weekSteps.count,
            totalSteps: weekSteps.isEmpty ? nil : weekSteps.reduce(0, +),
            activeMinutesTotal: nil,
            exerciseDays: daysAvailable,
            mostActiveDay: mostActive.flatMap { $0.value > 0 ? "\(localDate($0.date)) (\(Int($0.value)) steps)" : nil }
        )

        let vitals = CoachContextPacket.VitalsContext(
            latestHr: summary.latestHeartRate?.value,
            latestHrAt: summary.latestHeartRate.map { iso($0.timestamp) },
            latestSpo2: summary.latestSpO2?.value,
            latestSpo2At: summary.latestSpO2.map { iso($0.timestamp) },
            restingHrEstimate: summary.restingHeartRateEstimate,
            peakHrToday: summary.peakHeartRateToday
        )

        let sleep = summary.sleep.map { s -> CoachContextPacket.SleepContext in
            CoachContextPacket.SleepContext(
                date: localDate(s.session.date),
                totalMin: s.session.totalMinutes,
                deepMin: s.deepMinutes,
                lightMin: s.lightMinutes,
                awakeMin: s.awakeMinutes,
                score: s.session.score,
                confidence: "medium",
                decoderNote: DataQualityAnalyzer.sleepDecoderNote
            )
        }

        let warnings = DataQualityAnalyzer.warnings(
            .init(
                profileCompleteness: completeness,
                daysAvailable: daysAvailable,
                hasSleep: sleep != nil,
                lastSyncAt: device?.lastSyncAt,
                isDemo: summary.isDemo
            ),
            now: now
        )

        return CoachContextPacket(
            generatedAt: iso(now),
            timezone: TimeZone.current.identifier,
            profile: profileContext,
            device: deviceContext,
            goals: goals,
            today: today,
            lastSevenDays: week,
            latestVitals: vitals,
            latestSleep: sleep,
            recentWorkouts: recentWorkouts(context: context),
            memories: memories(context: context),
            learnings: learnings(context: context),
            conversationSummary: conversationSummary,
            dataQualityWarnings: warnings,
            modules: modulesContext(),
            trips: tripsContext(context: context, now: now),
            connectedWearables: connectedWearables()
        )
    }

    /// Display names of any connected third-party wearable accounts. Reads the
    /// Keychain-backed token store directly (no main-actor hop), so the coach is
    /// aware of Fitbit/Google Fit links without a tool call.
    private static func connectedWearables() -> [String] {
        WearableProvider.allCases
            .filter { WearableTokenStore(provider: $0).isConnected }
            .map(\.displayName)
    }

    // MARK: - Travel awareness (X5)

    /// Compact active/upcoming trip snapshot so the assistant knows the user is
    /// (or is about to be) traveling without a `list_trips` round-trip. Limited to
    /// the most relevant few; cancelled/old past trips are dropped.
    private static func tripsContext(context: ModelContext, now: Date, limit: Int = 4) -> [CoachContextPacket.TripContext] {
        guard SubAppRegistry.shared.isInstalled(SubAppID(AppModule.travel.rawValue)) else { return [] }
        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        func phase(_ trip: Trip) -> (String, Int?) {
            guard let start = trip.startDate else { return ("upcoming", nil) }
            let startDay = cal.startOfDay(for: start)
            let endDay = trip.endDate.map { cal.startOfDay(for: $0) } ?? startDay
            if today >= startDay && today <= endDay { return ("active today", 0) }
            if today < startDay {
                return ("upcoming", cal.dateComponents([.day], from: today, to: startDay).day)
            }
            return ("past", nil)
        }

        let openChecklists = openChecklistCounts(context: context)

        return trips
            .filter { $0.status != .cancelled }
            .map { trip -> (CoachContextPacket.TripContext, Date) in
                let (ph, days) = phase(trip)
                let ctx = CoachContextPacket.TripContext(
                    id: trip.id.uuidString,
                    destination: trip.destination,
                    status: trip.status.rawValue,
                    startDate: trip.startDate.map(localDate),
                    endDate: trip.endDate.map(localDate),
                    phase: ph,
                    daysUntil: days,
                    itemCount: trip.items.count,
                    openChecklistCount: openChecklists[trip.id] ?? 0
                )
                return (ctx, trip.startDate ?? trip.createdAt)
            }
            // Keep active + soonest-upcoming first; drop trips that ended.
            .filter { $0.0.phase != "past" }
            .sorted { ($0.1) < ($1.1) }
            .prefix(limit)
            .map { $0.0 }
    }

    private static func openChecklistCounts(context: ModelContext) -> [UUID: Int] {
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        var counts: [UUID: Int] = [:]
        for task in tasks where task.status != .done {
            guard let tripId = task.tripId else { continue }
            counts[tripId, default: 0] += 1
        }
        return counts
    }

    // MARK: - Module awareness (M3)

    /// Compact installed-vs-available module snapshot so the assistant can route
    /// to the right module or offer to install one without a `list_modules` round-trip.
    private static func modulesContext() -> CoachContextPacket.ModulesContext {
        let registry = SubAppRegistry.shared
        func summarize(_ app: any SubApp) -> CoachContextPacket.ModulesContext.ModuleSummary {
            .init(id: app.id.rawValue, name: app.displayName, summary: app.summary)
        }
        let installed = registry.subApps.filter { registry.isInstalled($0.id) }.map(summarize)
        let available = registry.subApps.filter { !registry.isInstalled($0.id) }.map(summarize)
        let updates = registry.modulesWithUpdates.map { $0.id.rawValue }
        return .init(installed: installed, available: available, updatesAvailable: updates)
    }

    // MARK: - Helpers

    private static func recentWorkouts(context: ModelContext, limit: Int = 8) -> [CoachContextPacket.WorkoutContext] {
        ActivityRepository.sessions(context: context)
            .filter { $0.status == .finished }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(limit)
            .map { s in
                let duration = s.endedAt.map {
                    (($0.timeIntervalSince(s.startedAt) - s.totalPauseSeconds) / 60).rounded(toPlaces: 1)
                }
                return CoachContextPacket.WorkoutContext(
                    id: s.id.uuidString,
                    type: s.type,
                    startTime: iso(s.startedAt),
                    durationMin: duration,
                    distanceKm: s.distanceMeters.map { ($0 / 1000).rounded(toPlaces: 2) },
                    avgHr: s.avgHeartRate,
                    status: s.status.rawValue
                )
            }
    }

    private static func memories(context: ModelContext, limit: Int = 8, now: Date = Date()) -> [CoachContextPacket.MemoryContext] {
        let descriptor = FetchDescriptor<CoachMemory>(
            sortBy: [SortDescriptor(\.importance, order: .reverse), SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows
            .filter { $0.expiresAt == nil || $0.expiresAt! > now }  // drop expired
            .prefix(limit)
            .map { .init(type: $0.memoryType, key: $0.key, value: $0.value, importance: $0.importance) }
    }

    private static func learnings(context: ModelContext, limit: Int = 10) -> [CoachContextPacket.LearningContext] {
        let descriptor = FetchDescriptor<DailyLearning>(
            sortBy: [SortDescriptor(\.importance, order: .reverse), SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows
            .filter { $0.isActive }
            .prefix(limit)
            .map { .init(category: $0.category.rawValue, title: $0.title, detail: $0.detail, importance: $0.importance) }
    }

    private static func profileCompleteness(_ profile: UserProfile?) -> String {
        guard let profile else { return "empty" }
        let filled = [profile.name as Any?, profile.age as Any?, profile.heightCm as Any?, profile.weightKg as Any?]
        let have = filled.compactMap { $0 }.count
        if have == 0 { return "empty" }
        return have == filled.count ? "complete" : "partial"
    }

    private static func dataConfidence(_ summary: TodaySummary) -> String {
        let hrCount = summary.trends.hrSamples24h.count
        let hasActivity = summary.steps != nil
        if !hasActivity && hrCount == 0 { return "none" }
        if hrCount >= 30 && hasActivity { return "high" }
        if hasActivity || hrCount > 0 { return "medium" }
        return "low"
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }

    private static func localDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let p = pow(10.0, Double(places))
        return (self * p).rounded() / p
    }
}
