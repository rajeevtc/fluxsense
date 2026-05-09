import Combine
import CoreMotion
import Foundation

/// Bridges CoreMotion's CMMotionManager to provide calibrated magnetic field data.
@MainActor
final class MagnetometerService: ObservableObject {
    private let motionManager = CMMotionManager()
    private let useCase = MagnetometerUseCase()
    private let updateInterval: TimeInterval = 1.0 / 30.0

    @Published private(set) var currentReading = MagneticReading(strength: 0, polarity: .neutral, rawMagnitude: 0)
    @Published private(set) var isRunning = false
    @Published private(set) var isCalibrated = false
    @Published private(set) var calibrationAccuracy: CMMagneticFieldCalibrationAccuracy = .uncalibrated

    var baselineMagnitude: Double {
        get { useCase.baselineMagnitude }
        set { useCase.baselineMagnitude = newValue }
    }

    /// Shared amplification applied to all three axes.
    var gain: Double {
        get { useCase.gainX }
        set {
            let safeGain = max(newValue, 0.1)
            useCase.gainX = safeGain
            useCase.gainY = safeGain
            useCase.gainZ = safeGain
        }
    }

    var isAvailable: Bool {
        motionManager.isDeviceMotionAvailable
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable, !isRunning else { return }

        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(
            using: .xMagneticNorthZVertical,
            to: .main
        ) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }

            let field = motion.magneticField
            self.calibrationAccuracy = field.accuracy
            self.currentReading = self.useCase.process(
                rawX: field.field.x,
                rawY: field.field.y,
                rawZ: field.field.z
            )
        }
        isRunning = true
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        isRunning = false
    }

    /// Captures the current ambient magnetic field as the zero-offset baseline.
    func calibrate() {
        guard let motion = motionManager.deviceMotion else { return }
        let field = motion.magneticField.field
        useCase.calibrate(rawX: field.x, rawY: field.y, rawZ: field.z)
        isCalibrated = true
    }
}
