import Combine
import Foundation
import WatchKit

@MainActor
final class StealthManager: ObservableObject {
    @Published private(set) var isStealthModeEnabled = false
    @Published private(set) var unlockProgress = 0.0

    private let unlockTarget = 2.0
    private let progressHapticStep = 0.1

    private var lastCrownValue = 0.0
    private var lastHapticProgressStep = 0

    func enterStealthMode() {
        isStealthModeEnabled = true
        unlockProgress = 0
        lastCrownValue = 0
        lastHapticProgressStep = 0
    }

    func exitStealthMode() {
        isStealthModeEnabled = false
        unlockProgress = 0
        lastCrownValue = 0
        lastHapticProgressStep = 0
    }

    func processCrownValue(_ value: Double) {
        guard isStealthModeEnabled else {
            lastCrownValue = value
            return
        }

        let delta = abs(value - lastCrownValue)
        lastCrownValue = value

        unlockProgress = min(unlockProgress + delta, unlockTarget)

        let currentStep = Int((unlockProgress / progressHapticStep).rounded(.down))
        if currentStep > lastHapticProgressStep {
            WKInterfaceDevice.current().play(.click)
            lastHapticProgressStep = currentStep
        }

        if unlockProgress >= unlockTarget {
            WKInterfaceDevice.current().play(.success)
            exitStealthMode()
        }
    }

    var unlockCompletion: Double {
        min(max(unlockProgress / unlockTarget, 0), 1)
    }
}
