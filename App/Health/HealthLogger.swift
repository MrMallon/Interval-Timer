import Foundation
import HealthKit

/// Saves finished iPhone workouts to Apple Health when the user turns it on.
/// Writes workouts only; never reads anything from Health.
/// (Workouts run on Apple Watch are saved by the Watch app, with heart rate.)
enum HealthLogger {
    private static let store = HKHealthStore()

    /// Workouts shorter than this aren't worth a Health entry.
    static let minimumSeconds: Double = 30

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// True when the user has refused Interval Timer in the Health app.
    static var isDenied: Bool {
        isAvailable && store.authorizationStatus(for: .workoutType()) == .sharingDenied
    }

    /// Shows Health's permission sheet if it hasn't been answered yet.
    /// Returns true when saving workouts is allowed.
    @discardableResult
    static func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [.workoutType()], read: [])
        } catch {
            return false
        }
        return store.authorizationStatus(for: .workoutType()) == .sharingAuthorized
    }

    static func save(_ record: WorkoutRecord) {
        guard isAvailable,
              record.totalSeconds >= minimumSeconds,
              store.authorizationStatus(for: .workoutType()) == .sharingAuthorized else { return }
        let start = record.startedAt
        let end = max(record.endedAt, start.addingTimeInterval(record.totalSeconds))
        Task.detached {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .highIntensityIntervalTraining
            configuration.locationType = .unknown
            let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
            do {
                try await builder.beginCollection(at: start)
                try await builder.endCollection(at: end)
                _ = try await builder.finishWorkout()
            } catch {
                print("Saving to Health failed: \(error)")
            }
        }
    }
}
