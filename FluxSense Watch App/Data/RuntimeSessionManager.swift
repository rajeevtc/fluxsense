import Combine
import Foundation
import HealthKit
import WatchKit

/// Keeps the app alive and the screen active for as long as the caller needs.
///
/// Strategy:
///   1. HKWorkoutSession — shows the green workout dot and prevents auto-lock while wrist is raised.
///   2. WKExtendedRuntimeSession — keeps the app running when the screen turns off so readings
///      never stop; magnetometer data is live the moment the user raises their wrist again.
///
/// Both sessions run until `invalidateSession()` is called explicitly.
@MainActor
final class RuntimeSessionManager: NSObject, ObservableObject {
    @Published private(set) var isRunning = false

    private var extendedSession: WKExtendedRuntimeSession?
    private var workoutSession: HKWorkoutSession?
    private let healthStore = HKHealthStore()

    func startSessionIfNeeded() {
        guard !isRunning else { return }
        isRunning = true
        startExtendedRuntimeSession()
        requestAuthAndStartWorkout()
    }

    func invalidateSession() {
        guard isRunning else { return }
        isRunning = false
        extendedSession?.invalidate()
        extendedSession = nil
        workoutSession?.end()
        workoutSession = nil
    }

    // MARK: - Private

    private func startExtendedRuntimeSession() {
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        extendedSession = session
        session.start()
    }

    private func requestAuthAndStartWorkout() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKWorkoutType.workoutType()]
        healthStore.requestAuthorization(toShare: share, read: []) { [weak self] granted, _ in
            guard granted else { return }
            Task { @MainActor [weak self] in
                self?.startWorkoutSession()
            }
        }
    }

    private func startWorkoutSession() {
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .unknown
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            session.delegate = self
            workoutSession = session
            session.startActivity(with: Date())
        } catch {
            // No HealthKit capability — WKExtendedRuntimeSession handles background execution.
        }
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension RuntimeSessionManager: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor [weak self] in
            guard let self, isRunning else { return }
            extendedSession = nil
            startExtendedRuntimeSession()
        }
    }

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            extendedSession = nil
            if isRunning { startExtendedRuntimeSession() }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension RuntimeSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}
