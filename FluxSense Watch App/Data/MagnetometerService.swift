import Combine
import CoreMotion
import Foundation

// MARK: - Background Processor

/// Runs all sensor computation off the main thread using Swift's actor isolation.
private actor MagnetometerProcessor {
    private var useCase = MagnetometerUseCase()
    private var magnitudeBuffer: [Double] = []
    private let smoothingWindowSize = 5
    private var latestField: (x: Double, y: Double, z: Double)?
    private var calibrated = false

    func setBaseline(_ value: Double) {
        useCase.baselineMagnitude = value
    }

    func setGain(_ value: Double) {
        let safe = max(value, 0.1)
        useCase.gainX = safe
        useCase.gainY = safe
        useCase.gainZ = safe
    }

    /// Calibrates using the most recently received field. Returns false if no field has arrived yet.
    func calibrateFromLatest() -> Bool {
        guard let field = latestField else { return false }
        useCase.calibrate(rawX: field.x, rawY: field.y, rawZ: field.z)
        magnitudeBuffer.removeAll()
        calibrated = true
        return true
    }

    func process(rawX: Double, rawY: Double, rawZ: Double) -> (reading: MagneticReading, isCalibrated: Bool) {
        latestField = (rawX, rawY, rawZ)

        if !calibrated {
            useCase.calibrate(rawX: rawX, rawY: rawY, rawZ: rawZ)
            calibrated = true
        }

        let reading = useCase.process(rawX: rawX, rawY: rawY, rawZ: rawZ)

        magnitudeBuffer.append(reading.rawMagnitude)
        if magnitudeBuffer.count > smoothingWindowSize {
            magnitudeBuffer.removeFirst()
        }
        let smoothed = magnitudeBuffer.reduce(0.0, +) / Double(magnitudeBuffer.count)
        let smoothedStrength = min(max(smoothed / max(useCase.baselineMagnitude, 0.0001), 0), 1)

        return (
            MagneticReading(strength: smoothedStrength, polarity: reading.polarity, rawMagnitude: smoothed),
            calibrated
        )
    }
}

// MARK: - Service

/// Bridges CoreMotion's CMMotionManager to provide calibrated magnetic field data.
@MainActor
final class MagnetometerService: ObservableObject {
    private let motionManager = CMMotionManager()
    private let processor = MagnetometerProcessor()
    private let processingQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.fluxsense.magnetometer"
        q.qualityOfService = .userInteractive
        return q
    }()
    private let updateInterval: TimeInterval = 1.0 / 30.0

    @Published private(set) var currentReading = MagneticReading(strength: 0, polarity: .neutral, rawMagnitude: 0)
    @Published private(set) var isRunning = false
    @Published private(set) var isCalibrated = false

    // Local copies kept in sync with the actor so callers can read them synchronously.
    private var _baselineMagnitude: Double = 40.0
    var baselineMagnitude: Double {
        get { _baselineMagnitude }
        set {
            _baselineMagnitude = newValue
            let p = processor
            Task { await p.setBaseline(newValue) }
        }
    }

    private var _gain: Double = 1.0
    var gain: Double {
        get { _gain }
        set {
            _gain = newValue
            let p = processor
            Task { await p.setGain(newValue) }
        }
    }

    var isAvailable: Bool {
        motionManager.isMagnetometerAvailable || motionManager.isDeviceMotionAvailable
    }

    func start() {
        guard !isRunning else { return }

        // Capture actor reference here (on main actor) so the background callbacks
        // can use it without crossing the @MainActor boundary.
        let processor = self.processor

        if motionManager.isMagnetometerAvailable {
            motionManager.magnetometerUpdateInterval = updateInterval
            motionManager.startMagnetometerUpdates(to: processingQueue) { [weak self] data, error in
                guard let data, error == nil else { return }
                let (x, y, z) = (data.magneticField.x, data.magneticField.y, data.magneticField.z)
                Task {
                    let result = await processor.process(rawX: x, rawY: y, rawZ: z)
                    await MainActor.run {
                        self?.currentReading = result.reading
                        self?.isCalibrated = result.isCalibrated
                    }
                }
            }
            isRunning = true
            return
        }

        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: processingQueue) { [weak self] motion, error in
            guard let motion, error == nil else { return }
            let field = motion.magneticField.field
            let (x, y, z) = (field.x, field.y, field.z)
            Task {
                let result = await processor.process(rawX: x, rawY: y, rawZ: z)
                await MainActor.run {
                    self?.currentReading = result.reading
                    self?.isCalibrated = result.isCalibrated
                }
            }
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
        let p = processor
        Task {
            let success = await p.calibrateFromLatest()
            await MainActor.run { [weak self] in
                if success { self?.isCalibrated = true }
            }
        }
    }
}
