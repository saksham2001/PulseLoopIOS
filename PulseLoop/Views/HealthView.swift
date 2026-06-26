import SwiftUI
import SwiftData

struct HealthView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RingSyncCoordinator.self) private var coordinator
    @Environment(RingBLEClient.self) private var ble
    @Query private var devices: [Device]
    @Binding var path: NavigationPath
    @State private var measuring: MeasurementSheet.Kind?

    private var summary: TodaySummary {
        MetricsService.buildTodaySummary(context: modelContext)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                healthHeader
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                VStack(spacing: 20) {
                    deviceStatusBanner
                    vitalCards
                    sleepCard
                    activityCard
                    workoutsSection
                    recordButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
        }
        .background(PulseColors.background)
        .refreshable { await coordinator.pullToRefresh() }
        .sheet(item: Binding(
            get: { measuring.map(HealthMeasuringItem.init) },
            set: { measuring = $0?.kind }
        )) { item in
            MeasurementSheet(kind: item.kind)
        }
    }

    // MARK: - Header

    private var healthHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Health")
                    .font(PulseFont.title(27))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                Button { path.append(AppRoute.settings) } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                        .foregroundStyle(PulseColors.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(PulseColors.fillSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(PulseColors.borderHairline, lineWidth: 1)
                        }
                }
            }
            .padding(.top, 8)
            Text("Ring synced · real-time vitals")
                .font(PulseFont.body(13))
                .foregroundStyle(PulseColors.textMuted)
        }
    }

    // MARK: - Device Status

    private var deviceStatusBanner: some View {
        let device = devices.first
        let state = device?.state ?? .disconnected
        let liveActive = [RingConnectionState.connected, .connecting, .reconnecting, .scanning].contains(ble.state)

        return HStack(spacing: 9) {
            Image(systemName: "wave.3.right")
                .font(.system(size: 13))
                .foregroundStyle(PulseColors.textPrimary)

            if let d = device {
                Text(d.name)
                    .font(PulseFont.body(12.5))
                    .foregroundStyle(PulseColors.textSecondary)
            } else {
                Text("No device connected")
                    .font(PulseFont.body(12.5))
                    .foregroundStyle(PulseColors.textSecondary)
            }

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(state == .connected ? Color.green : PulseColors.textMuted)
                    .frame(width: 6, height: 6)
                Text(state == .connected ? "Connected" : state.rawValue.capitalized)
                    .font(PulseFont.bodySemibold(11))
                    .foregroundStyle(state == .connected ? Color.green : PulseColors.textMuted)
            }

            if let battery = device?.batteryPercent, battery > 0 {
                Text("\(battery)%")
                    .font(PulseFont.bodySemibold(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .padding(.leading, 4)
            }
        }
        .padding(12)
        .background(PulseColors.fillMuted)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    // MARK: - Vital Cards

    private var vitalCards: some View {
        let s = summary
        let hrSamples = MetricsService.metricRange(metric: .heartRate, range: .twentyFourHours, context: modelContext)
        let spo2Samples = MetricsService.metricRange(metric: .spo2, range: .twentyFourHours, context: modelContext)

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                VitalStatCard(
                    icon: "heart.fill",
                    iconColor: PulseColors.heartRate,
                    title: "Heart Rate",
                    value: s.latestHeartRate.map { "\(Int($0.value))" } ?? "--",
                    unit: "bpm",
                    subtitle: "Resting: \(s.restingHeartRateEstimate.map { "\(Int($0))" } ?? " - ")",
                    onTap: { measuring = .hr }
                )

                VitalStatCard(
                    icon: "drop.fill",
                    iconColor: PulseColors.spo2,
                    title: "SpO₂",
                    value: s.latestSpO2.map { "\(Int($0.value))" } ?? "--",
                    unit: "%",
                    subtitle: spo2Samples.isEmpty ? "No readings" : "Normal range",
                    onTap: { measuring = .spo2 }
                )
            }

            // HR Chart
            if hrSamples.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("HEART RATE · 24H")
                            .font(PulseFont.bodySemibold(11))
                            .foregroundStyle(PulseColors.textMuted)
                            .tracking(0.6)
                        Spacer()
                        Button { path.append(AppRoute.vitals) } label: {
                            Text("Details →")
                                .font(PulseFont.body(12.5))
                                .foregroundStyle(PulseColors.textSecondary)
                        }
                    }
                    HRLineChart(samples: hrSamples)
                        .frame(height: 120)
                }
                .padding(15)
                .background(PulseColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PulseColors.borderHairline, lineWidth: 1)
                }
                .shadow(color: Color.primary.opacity(0.03), radius: 1, x: 0, y: 1)
            }

            // SpO2 Chart
            if spo2Samples.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("BLOOD OXYGEN · 24H")
                            .font(PulseFont.bodySemibold(11))
                            .foregroundStyle(PulseColors.textMuted)
                            .tracking(0.6)
                        Spacer()
                        Button { path.append(AppRoute.vitals) } label: {
                            Text("Details →")
                                .font(PulseFont.body(12.5))
                                .foregroundStyle(PulseColors.textSecondary)
                        }
                    }
                    SpO2DotsChart(samples: spo2Samples)
                        .frame(height: 100)
                }
                .padding(15)
                .background(PulseColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PulseColors.borderHairline, lineWidth: 1)
                }
                .shadow(color: Color.primary.opacity(0.03), radius: 1, x: 0, y: 1)
            }
        }
    }

    // MARK: - Sleep Card

    private var sleepCard: some View {
        let sleepSummary = SleepService.sleepRange(.day, context: modelContext)
        let lastNight = SleepInsights.validSessions(sleepSummary.sessions).last
        let score = lastNight.map { SleepScore.calculate($0) }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SLEEP")
                    .font(PulseFont.bodySemibold(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.6)
                Spacer()
                Button { path.append(AppRoute.sleep) } label: {
                    Text("Details →")
                        .font(PulseFont.body(12.5))
                        .foregroundStyle(PulseColors.textSecondary)
                }
            }

            if let night = lastNight, let score = score {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(night.session.totalMinutes / 60)h \(night.session.totalMinutes % 60)m")
                            .font(PulseFont.title(24))
                            .foregroundStyle(PulseColors.textPrimary)
                        Text(score.label.rawValue)
                            .font(PulseFont.bodySemibold(12))
                            .foregroundStyle(scoreColor(score.score))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Score")
                            .font(PulseFont.body(11))
                            .foregroundStyle(PulseColors.textMuted)
                        Text("\(score.score)")
                            .font(PulseFont.title(28))
                            .foregroundStyle(PulseColors.textPrimary)
                    }
                }

                HStack(spacing: 8) {
                    SleepStageChip(stage: "Deep", pct: Double(score.deepPct), color: Color(hex: "#3F2DD8"))
                    SleepStageChip(stage: "Light", pct: Double(score.lightPct), color: Color(hex: "#7C5CFF"))
                    if let awake = score.awakePct {
                        SleepStageChip(stage: "Awake", pct: Double(awake), color: Color(hex: "#FFB86B"))
                    }
                }

                if !night.blocks.isEmpty {
                    SleepHypnogramView(blocks: night.blocks, totalMin: night.session.totalMinutes, startTs: night.session.startAt, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 16))
                        .foregroundStyle(PulseColors.textMuted)
                    Text("No sleep data yet  -  wear your ring tonight")
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.textMuted)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(15)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
        .shadow(color: Color.primary.opacity(0.03), radius: 1, x: 0, y: 1)
    }

    // MARK: - Activity Card

    private var activityCard: some View {
        let s = summary
        let stepGoal = s.goals.stepsDaily
        let activeGoal = s.goals.activeMinutesDaily
        let stepPct = stepGoal > 0 ? min(1.0, Double(s.steps ?? 0) / Double(stepGoal)) : 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ACTIVITY")
                    .font(PulseFont.bodySemibold(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.6)
                Spacer()
                Button { path.append(AppRoute.activity) } label: {
                    Text("Details →")
                        .font(PulseFont.body(12.5))
                        .foregroundStyle(PulseColors.textSecondary)
                }
            }

            HStack(spacing: 16) {
                ActivityRing(progress: stepPct, size: 70)

                VStack(alignment: .leading, spacing: 8) {
                    ActivityMetricRow(icon: "figure.walk", label: "Steps", value: "\(s.steps ?? 0)", goal: "\(stepGoal)")
                    ActivityMetricRow(icon: "flame.fill", label: "Calories", value: "\(Int(s.calories ?? 0))", goal: nil)
                    ActivityMetricRow(icon: "timer", label: "Active min", value: "\(s.activeMinutes ?? 0)", goal: "\(activeGoal)")
                }
            }

            let weekSteps = MetricsService.metricRange(metric: .steps, range: .sevenDays, context: modelContext)
            if weekSteps.count > 1 {
                StepBarsChart(values: weekSteps.map(\.value), goal: Double(stepGoal))
                    .frame(height: 100)
            }
        }
        .padding(15)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
        .shadow(color: Color.primary.opacity(0.03), radius: 1, x: 0, y: 1)
    }

    // MARK: - Workouts Section

    @Query(sort: \ActivitySession.startedAt, order: .reverse) private var sessions: [ActivitySession]

    private var workoutsSection: some View {
        let todayWorkouts = sessions.filter { $0.status == .finished && Calendar.current.isDateInToday($0.startedAt) }

        return VStack(alignment: .leading, spacing: 10) {
            Text("WORKOUTS · TODAY")
                .font(PulseFont.bodySemibold(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.6)

            if todayWorkouts.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 15))
                        .foregroundStyle(PulseColors.textMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No workouts today")
                            .font(PulseFont.bodyMedium(13.5))
                            .foregroundStyle(PulseColors.textPrimary)
                        Text("Record one to track HR, route & stats")
                            .font(PulseFont.body(11.5))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(PulseColors.fillMuted)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(todayWorkouts) { session in
                        Button { path.append(AppRoute.activityDetail(session.id)) } label: {
                            WorkoutListRow(session: session)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PulseColors.borderHairline, lineWidth: 1)
                }
            }
        }
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button { path.append(AppRoute.recordSelect) } label: {
            HStack(spacing: 11) {
                Image(systemName: "record.circle")
                    .font(.system(size: 16, weight: .semibold))
                Text("Record Activity")
                    .font(PulseFont.bodySemibold(14.5))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(PulseColors.accent)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func scoreColor(_ score: Int) -> Color {
        if score >= 85 { return Color.green }
        if score >= 70 { return Color.primary }
        if score >= 55 { return Color.secondary }
        return PulseColors.alert
    }
}

// MARK: - Supporting Components

struct VitalStatCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let unit: String
    let subtitle: String
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(iconColor)
                        .frame(width: 28, height: 28)
                        .background(iconColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    Text(title)
                        .font(PulseFont.bodySemibold(12))
                        .foregroundStyle(PulseColors.textSecondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(PulseFont.title(26))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text(unit)
                        .font(PulseFont.body(12))
                        .foregroundStyle(PulseColors.textMuted)
                }

                Text(subtitle)
                    .font(PulseFont.body(11))
                    .foregroundStyle(PulseColors.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(PulseColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PulseColors.borderHairline, lineWidth: 1)
            }
            .shadow(color: Color.primary.opacity(0.03), radius: 1, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

struct SleepStageChip: View {
    let stage: String
    let pct: Double
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(stage) \(Int(pct))%")
                .font(PulseFont.bodySemibold(11))
                .foregroundStyle(PulseColors.textSecondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(PulseColors.fillSubtle)
        .clipShape(Capsule())
    }
}

struct ActivityRing: View {
    let progress: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(PulseColors.fillSubtle, lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(PulseColors.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(progress * 100))%")
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(PulseColors.textPrimary)
            }
        }
        .frame(width: size, height: size)
    }
}

struct ActivityMetricRow: View {
    let icon: String
    let label: String
    let value: String
    let goal: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(PulseColors.textMuted)
                .frame(width: 16)
            Text(label)
                .font(PulseFont.body(12))
                .foregroundStyle(PulseColors.textMuted)
            Spacer()
            Text(value)
                .font(PulseFont.bodySemibold(13))
                .foregroundStyle(PulseColors.textPrimary)
            if let goal = goal {
                Text("/ \(goal)")
                    .font(PulseFont.body(11))
                    .foregroundStyle(PulseColors.textFaint)
            }
        }
    }
}

struct WorkoutListRow: View {
    let session: ActivitySession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: emojiForType(session.type))
                .font(.system(size: 15))
                .foregroundStyle(PulseColors.textPrimary)
                .frame(width: 34, height: 34)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(session.type.capitalized)
                    .font(PulseFont.bodyMedium(14))
                    .foregroundStyle(PulseColors.textPrimary)
                Text(workoutSubtitle)
                    .font(PulseFont.body(11.5))
                    .foregroundStyle(PulseColors.textMuted)
            }

            Spacer()

            if let hr = session.avgHeartRate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(hr))")
                        .font(PulseFont.bodySemibold(14))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text("avg bpm")
                        .font(PulseFont.body(10))
                        .foregroundStyle(PulseColors.textMuted)
                }
            }
        }
        .padding(13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PulseColors.borderHairline).frame(height: 1)
        }
    }

    private var workoutSubtitle: String {
        var parts: [String] = []
        if let end = session.endedAt {
            let secs = end.timeIntervalSince(session.startedAt) - session.totalPauseSeconds
            let m = Int(max(0, secs)) / 60
            parts.append("\(m)m")
        }
        if let dist = session.distanceMeters, dist > 0 {
            let km = dist / 1000
            parts.append(String(format: "%.1f km", km))
        }
        if let cal = session.calories, cal > 0 {
            parts.append("\(Int(cal)) kcal")
        }
        return parts.joined(separator: " · ")
    }

    private func emojiForType(_ type: String) -> String {
        switch type.lowercased() {
        case "run": return "figure.run"
        case "walk": return "figure.walk"
        case "cycle": return "figure.outdoor.cycle"
        case "gym", "strength": return "figure.strengthtraining.traditional"
        case "hike": return "figure.hiking"
        case "yoga": return "figure.yoga"
        case "swim": return "figure.pool.swim"
        default: return "bolt.fill"
        }
    }
}

private struct HealthMeasuringItem: Identifiable {
    let kind: MeasurementSheet.Kind
    var id: Int { kind == .hr ? 0 : 1 }
}

