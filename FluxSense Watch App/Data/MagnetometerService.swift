import Combine
import CoreMotion
import Foundation

/// Bridges CoreMotion's CMMotionManager to provide calibrated magnetic field data.
@MainActor
final class MagnetometerService: ObservableObject {
    private let motionManager = CMMotionManager()
    private let useCase = MagnetometerUseCase()
    private let updateInterval: TimeInterval = 1.0 / 30.0
    private var latestRawField: CMMagneticField?

    private var magnitudeBuffer: [Double] = []
    private let smoothingWindowSize = 5

    @Published private(set) var currentReading = MagneticReading(strength: 0, polarity: .neutral, rawMagnitude: 0)
    @Published private(set) var isRunning = false
    @Published private(set) var isCalibrated = false

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
        motionManager.isMagnetometerAvailable || motionManager.isDeviceMotionAvailable
    }

    func start() {
        guard !isRunning else { return }

        if motionManager.isMagnetometerAvailable {
            motionManager.magnetometerUpdateInterval = updateInterval
            motionManager.startMagnetometerUpdates(to: .main) { [weak self] data, error in
                guard let self, let data, error == nil else { return }
                self.consume(field: data.magneticField)
            }
            isRunning = true
            return
        }

        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }
            self.consume(field: motion.magneticField.field)
        }
        isRunning = true
    }

    func stop() {
        motionManager.stopMagnetometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        isRunning = false
    }

    /// Captures the current ambient magnetic field as the zero-offset baseline.
    func calibrate() {
        guard let field = latestRawField else { return }
        useCase.calibrate(rawX: field.x, rawY: field.y, rawZ: field.z)
        magnitudeBuffer.removeAll()
        isCalibrated = true
    }

    private func consume(field: CMMagneticField) {
        latestRawField = field

        if !isCalibrated {
            useCase.calibrate(rawX: field.x, rawY: field.y, rawZ: field.z)
            isCalibrated = true
        }

        let reading = useCase.process(
            rawX: field.x,
            rawY: field.y,
            rawZ: field.z
        )

        magnitudeBuffer.append(reading.rawMagnitude)
        if magnitudeBuffer.count > smoothingWindowSize {
            magnitudeBuffer.removeFirst()
        }
        let smoothed = magnitudeBuffer.reduce(0.0, +) / Double(magnitudeBuffer.count)
        let smoothedStrength = min(max(smoothed / max(useCase.baselineMagnitude, 0.0001), 0), 1)

        currentReading = MagneticReading(
            strength: smoothedStrength,
            polarity: reading.polarity,
            rawMagnitude: smoothed
        )
    }
}
