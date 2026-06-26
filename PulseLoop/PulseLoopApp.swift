//
//  PulseLoopApp.swift
//  PulseLoop
//
//  Created by Saksham Bhutani on 5/31/26.
//

import SwiftUI
import SwiftData
import UserNotifications
import os

@main
struct PulseLoopApp: App {
    @Environment(\.scenePhase) private var scenePhase
    let container: ModelContainer
    /// Non-nil when the on-disk store failed to load and we fell back to a temporary
    /// in-memory store. Drives a recovery banner so the failure is visible instead of
    /// crashing at launch (the old `fatalError`).
    private let launchError: String?
    @State private var bleClient: RingBLEClient
    @State private var coordinator: RingSyncCoordinator
    @State private var gpsRecorder: GpsRouteRecorder
    @State private var liveWorkout: LiveWorkoutManager
    /// Retained for app lifetime so it keeps draining the event bus into SwiftData.
    private let persistence: EventPersistenceSubscriber
    /// Retained so it keeps regenerating Today/Sleep coach summaries on new data.
    private let summaryCoordinator: CoachSummaryCoordinator
    /// Retained so the UNUserNotificationCenter delegate stays alive.
    private let notificationDelegate = CoachNotificationDelegate()

    init() {
        let container: ModelContainer
        var launchError: String?
        do {
            container = try ModelContainerFactory.make()
        } catch {
            // Do NOT crash existing users on a store-load failure. Log it and fall back
            // to a temporary in-memory store so the app launches into a recovery state
            // (the UI surfaces a banner) rather than dying at the old `fatalError`.
            AppLog.persistence.fault("On-disk store failed to load, falling back to in-memory: \(String(describing: error), privacy: .public)")
            launchError = "Your data couldn't be opened. Running in temporary mode — recent changes may not be saved. Reinstalling or updating the app may resolve this."
            do {
                container = try ModelContainerFactory.make(inMemory: true)
            } catch {
                // In-memory creation should never fail; if it does we truly cannot run.
                AppLog.persistence.fault("In-memory fallback store also failed: \(String(describing: error), privacy: .public)")
                fatalError("Unable to create any SwiftData container: \(error)")
            }
        }
        self.container = container
        self.launchError = launchError

        let client = RingBLEClient()
        let coordinator = RingSyncCoordinator(client: client, context: container.mainContext)
        client.onConnected = { [weak coordinator] in coordinator?.runStartupSequence() }
        let gps = GpsRouteRecorder()
        _bleClient = State(initialValue: client)
        _coordinator = State(initialValue: coordinator)
        _gpsRecorder = State(initialValue: gps)
        _liveWorkout = State(initialValue: LiveWorkoutManager(coordinator: coordinator, gps: gps, context: container.mainContext))

        let subscriber = EventPersistenceSubscriber(context: container.mainContext)
        self.persistence = subscriber
        self.summaryCoordinator = CoachSummaryCoordinator(context: container.mainContext)

        // Start persistence + coordinator draining the bus; auto-reconnect happens when
        // CoreBluetooth reports poweredOn (see RingBLEClient.centralManagerDidUpdateState).
        subscriber.start()
        coordinator.start()
        summaryCoordinator.start()

        // Daily check-in notifications: route taps + register the background wake.
        UNUserNotificationCenter.current().delegate = notificationDelegate
        let ctx = container.mainContext
        CoachNotificationScheduler.shared.register {
            CoachNotificationService(modelContext: ctx, coordinator: coordinator)
        }

        // Opt-in, content-free crash/hang diagnostics via MetricKit (roadmap F1).
        // No-op unless the user has granted diagnostics consent in Settings.
        DiagnosticsService.shared.startIfEnabled()
    }

    var body: some Scene {
        WindowGroup {
            RootAppView()
                .environment(bleClient)
                .environment(coordinator)
                .environment(gpsRecorder)
                .environment(liveWorkout)
                .errorToast()
                .safeAreaInset(edge: .top) {
                    if let launchError {
                        LaunchRecoveryBanner(message: launchError)
                    }
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            CoachNotificationScheduler.shared.scheduleNext()
            guard CoachSettingsStore.shared.settings.coachMasterEnabled else { return }
            let ctx = container.mainContext
            let coordinator = coordinator
            Task {
                await CoachNotificationService(modelContext: ctx, coordinator: coordinator).runDueSlot()
                await MedicationReminderService.shared.rescheduleAll(modelContext: ctx)
            }
        }
    }
}

/// Top banner shown when the on-disk SwiftData store failed to load and we fell back
/// to a temporary in-memory store. Honest, non-blocking surfacing of a serious error
/// instead of crashing at launch. Dismissible (the underlying failure is already
/// logged via `AppLog.persistence`).
private struct LaunchRecoveryBanner: View {
    let message: String
    @State private var dismissed = false

    var body: some View {
        if !dismissed {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(PulseColors.alert)
                    .font(.system(size: 16, weight: .semibold))
                Text(message)
                    .font(PulseFont.bodySmall)
                    .foregroundStyle(PulseColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    dismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PulseColors.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(PulseColors.alertBackground)
            .overlay(alignment: .bottom) {
                Rectangle().fill(PulseColors.borderHairline).frame(height: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Data warning. \(message)")
        }
    }
}
