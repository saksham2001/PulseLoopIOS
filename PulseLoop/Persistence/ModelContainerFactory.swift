import SwiftData
import Foundation
import os

enum ModelContainerFactory {
    /// Models owned by the platform core (ring/health, coach storage, and the
    /// life-OS models not yet migrated to `SubApp` conformers). As features migrate
    /// in Phase B, their models move out of here and into the owning `SubApp` so
    /// the schema below shrinks while `SubAppRegistry.allModels` grows.
    static var coreModels: [any PersistentModel.Type] {
        [
            // Existing health/ring models
            Device.self,
            ActivityDaily.self,
            Measurement.self,
            SleepSession.self,
            SleepStageBlock.self,
            RawPacketRow.self,
            DerivedUpdateRow.self,
            UserProfile.self,
            UserGoal.self,
            ActivitySession.self,
            ActivitySample.self,
            ActivityGpsPoint.self,
            ActivityEvent.self,
            ActivitySensorPollEvent.self,
            CoachConversation.self,
            CoachMessage.self,
            CoachMemory.self,
            CoachToolCall.self,
            CoachFeedback.self,
            TurnTelemetry.self,
            CoachNotificationRecord.self,
            CoachSummary.self,
            // Life OS models
            Note.self,
            NoteBlock.self,
            TaskItem.self,
            TaskBoard.self,
            Collection.self,
            InboxItem.self,
            ConnectedAccount.self,
            Routine.self,
            RoutineStep.self,
            Medication.self,
            MedicationLog.self,
            MealLog.self,
            CustomProductInfo.self,
            Subscription.self,
            AuditLogEntry.self,
            PermissionGate.self,
            DayPlan.self,
            DayPlanAction.self,
            AIMemory.self,
            AIConversationLog.self,
            SleepLog.self,
            MoodEntry.self,
            WorkoutLog.self,
            BodyMetric.self,
            Habit.self,
            HabitLog.self,
            SymptomLog.self,
            LabResult.self,
            StressLog.self,
            MeditationLog.self,
            // Friends & Social
            Friend.self,
            FriendActivity.self,
            Wishlist.self,
            WishlistItem.self,
            FriendEvent.self,
            TravelPlan.self,
            // Vices / Quit Program
            Vice.self,
            ViceLog.self,
            // Travel module
            Trip.self,
            TripItem.self,
            RewardCard.self,
            // Fitness & Journal
            Exercise.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            ExerciseSet.self,
            JournalDay.self,
            JournalMetricEntry.self,
            // AI knowledge base
            DailyLearning.self,
            // Spec-driven sub-app dynamic records (one generic table for all
            // user-created / installed sub-apps; see SubAppPersistence.swift)
            DynamicSubAppRecord.self
        ]
    }

    /// The full model list: core models plus any contributed by registered sub-apps,
    /// de-duplicated by type so a model registered in both places is included once.
    static var allModels: [any PersistentModel.Type] {
        var seen = Set<ObjectIdentifier>()
        var result: [any PersistentModel.Type] = []
        for model in coreModels + SubAppRegistry.shared.allModels {
            let key = ObjectIdentifier(model)
            if seen.insert(key).inserted {
                result.append(model)
            }
        }
        return result
    }

    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(allModels)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: PulseLoopMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            AppLog.persistence.error("ModelContainer creation failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }
}

// MARK: - Versioned schema + migration plan
//
// Establishes the migration seam so future model changes add a `VersionedSchema` +
// `MigrationStage` instead of risking a store-load crash. `SchemaV1` snapshots the
// CURRENT model set; the plan currently has a single version (identity), so existing
// on-disk stores load unchanged. When a non-additive change is needed, add `SchemaV2`
// and a `.custom`/`.lightweight` stage between V1 and V2 here.
//
// Note: the dynamic sub-app data lives in the single generic `DynamicSubAppRecord`
// table (JSON payload), which is migration-tolerant by design — sub-app schema
// changes don't alter the SwiftData schema, so they never require a stage here.

enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        ModelContainerFactory.allModels
    }
}

enum PulseLoopMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // No migrations yet — V1 is the baseline. Add stages here as the schema evolves.
        []
    }
}
