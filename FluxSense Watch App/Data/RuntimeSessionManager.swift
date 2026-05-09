import Combine
import Foundation
import WatchKit

@MainActor
final class RuntimeSessionManager: NSObject, ObservableObject {
    enum SessionKind: String, CaseIterable {
        case physicalSmartCard
        case selfContainedTest
    }

    @Published private(set) var isRunning = false
    @Published private(set) var remainingSeconds: Int = 0
    @Published var sessionKind: SessionKind = .selfContainedTest

    var onSessionEnded: (() -> Void)?

    private var session: WKExtendedRuntimeSession?
    private var expirationTask: Task<Void, Never>?

    private let maxDurationSeconds = 20 * 60

    func startSessionIfNeeded() {
        guard !isRunning else { return }

        let session = WKExtendedRuntimeSession()
        session.delegate = self
        self.session = session
        session.start()

        isRunning = true
        remainingSeconds = maxDurationSeconds
        scheduleExpirationCountdown()
    }

    func invalidateSession() {
        expirationTask?.cancel()
        expirationTask = nil

        session?.invalidate()
        session = nil

        if isRunning {
            isRunning = false
            remainingSeconds = 0
            onSessionEnded?()
        }
    }

    private func scheduleExpirationCountdown() {
        expirationTask?.cancel()

        expirationTask = Task {
            for second in stride(from: maxDurationSeconds, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                remainingSeconds = second
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }

            guard !Task.isCancelled else { return }
            invalidateSession()
        }
    }
}

extension RuntimeSessionManager: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            invalidateSession()
        }
    }

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        Task { @MainActor in
            expirationTask?.cancel()
            expirationTask = nil
            session = nil

            if isRunning {
                isRunning = false
                remainingSeconds = 0
                onSessionEnded?()
            }
        }
    }
}
