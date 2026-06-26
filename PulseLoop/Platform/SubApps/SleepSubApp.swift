import SwiftUI
import SwiftData

// MARK: - Sleep SubApp (first migrated built-in)
//
// First feature migrated to the `SubApp` protocol (roadmap B1). It owns the Sleep
// domain: its SwiftData models, its navigation destination, and (later) its Coach
// tools. The legacy `AppRoute.sleep` keeps working — `HomeView`/`HealthView` still
// push it — but new navigation can use `SleepRoute` resolved through `SubAppRouter`.

/// Sub-app navigation destination for Sleep.
enum SleepRoute: SubAppRoute {
    case dashboard
}

struct SleepSubApp: SubApp {
    var id: SubAppID { SubAppID(AppModule.sleep.rawValue) }
    var displayName: String { AppModule.sleep.name }
    var iconSystemName: String { AppModule.sleep.icon }
    var summary: String { AppModule.sleep.description }
    var origin: SubAppOrigin { .builtIn }

    /// Sleep owns the sleep session/stage models and the manual sleep log. These
    /// are de-duplicated against `ModelContainerFactory.coreModels`, so contributing
    /// them here is safe during the incremental migration.
    var models: [any PersistentModel.Type] {
        [SleepSession.self, SleepStageBlock.self, SleepLog.self]
    }

    var permissions: Set<SubAppPermission> { [.healthRead] }

    @MainActor
    func registerRoutes(with router: SubAppRouter) {
        router.registerDestination(for: SleepRoute.self) { route, _ in
            switch route {
            case .dashboard:
                SleepView()
            }
        }
    }

    @MainActor
    func dashboardCard(context: RouteContext) -> AnyView? {
        AnyView(SleepDashboardCard(path: context.path))
    }
}

/// Compact Home dashboard card summarizing last night's sleep. Tapping opens the
/// Sleep dashboard. Uses design-system tokens only.
private struct SleepDashboardCard: View {
    let path: Binding<NavigationPath>
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let summary = SleepService.sleepRange(.day, context: modelContext)
        let night = SleepInsights.validSessions(summary.sessions).last

        Button {
            path.wrappedValue.append(AppRoute.sleep)
        } label: {
            PulseCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PulseColors.sleep)
                        Text("SLEEP")
                            .font(PulseFont.bodyMedium(11))
                            .tracking(0.8)
                            .foregroundStyle(PulseColors.textMuted)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(PulseColors.textFaint)
                    }

                    if let night {
                        let score = SleepScore.calculate(night)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(SleepFormat.duration(night.session.totalMinutes))
                                .font(PulseFont.titleSemibold(28))
                                .foregroundStyle(PulseColors.textPrimary)
                            Text("\(score.score)")
                                .font(PulseFont.bodySemibold(15))
                                .foregroundStyle(PulseColors.sleep)
                            Text(score.label.rawValue)
                                .font(PulseFont.body(13))
                                .foregroundStyle(PulseColors.textSecondary)
                        }
                        Text("\(SleepFormat.clockTime(night.session.startAt)) – \(SleepFormat.clockTime(night.session.endAt))")
                            .font(PulseFont.body(13))
                            .foregroundStyle(PulseColors.textMuted)
                    } else {
                        Text("No sleep recorded")
                            .font(PulseFont.bodySemibold(17))
                            .foregroundStyle(PulseColors.textPrimary)
                        Text("Wear your ring overnight to see your sleep recap here.")
                            .font(PulseFont.body(13))
                            .foregroundStyle(PulseColors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sleep summary. Opens the sleep dashboard.")
    }
}
