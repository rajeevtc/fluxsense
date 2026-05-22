#if canImport(CoreHaptics)
import CoreHaptics
#endif
import Foundation
import WatchKit

/// Delivers haptic feedback patterns on watchOS.
/// Uses Core Haptics when available and falls back to WatchKit haptics.
@MainActor
final class HapticService {
    private let device = WKInterfaceDevice.current()
#if canImport(CoreHaptics)
    private var engine: CHHapticEngine?
#endif
    private var hapticTask: Task<Void, Never>?

    /// Maximum interval between haptic bursts (seconds) at minimum strength.
    private let maxInterval: TimeInterval = 1.0
    /// Minimum interval between haptic bursts (seconds) at maximum strength.
    private let minInterval: TimeInterval = 0.15

    init() {
#if canImport(CoreHaptics)
        setupEngineIfNeeded()
#endif
    }

    /// Starts a repeating haptic pattern based on the current reading.
    /// - South Pole: Steady Pulse — single rhythmic beat
    /// - North Pole: Double Tap — rapid heartbeat-style double beat (100ms apart)
    /// Intensity scales dynamically with 0–100% magnetic strength.
    func play(for reading: MagneticReading) {
        stop()

        guard reading.rawMagnitude > 1470, reading.polarity != .neutral else { return }

        let polarity = reading.polarity
        let strength = reading.strength

        // Interval decreases as strength increases (stronger = faster pulses).
        let interval = maxInterval - (maxInterval - minInterval) * strength

        hapticTask = Task {
            while !Task.isCancelled {
                await playBurst(polarity: polarity, strength: strength)
                let nanos = UInt64(interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    func stop() {
        hapticTask?.cancel()
        hapticTask = nil
#if canImport(CoreHaptics)
        engine?.stop(completionHandler: nil)
#endif
    }

    private func playBurst(polarity: Polarity, strength: Double) async {
#if canImport(CoreHaptics)
        await playCoreHapticsBurst(polarity: polarity, strength: strength)
#else
        playFallback(polarity: polarity, strength: strength)
#endif
    }

#if canImport(CoreHaptics)
    private func setupEngineIfNeeded() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            engine = nil
            return
        }

        do {
            let engine = try CHHapticEngine()
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.restartEngineIfPossible()
                }
            }
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    self?.restartEngineIfPossible()
                }
            }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    private func restartEngineIfPossible() {
        guard let engine else {
            setupEngineIfNeeded()
            return
        }

        do {
            try engine.start()
        } catch {
            self.engine = nil
        }
    }

    private func playCoreHapticsBurst(polarity: Polarity, strength: Double) async {
        let clampedStrength = max(0.0, min(1.0, strength))
        
        // Max out haptic output for both North and South pulses.
        let intensity: Float = 1.0
        let sharpness: Float = 1.0

        guard let engine else {
            playFallback(polarity: polarity, strength: clampedStrength)
            return
        }

        let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)

        let events: [CHHapticEvent]
        switch polarity {
        case .south:
            events = [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensityParam, sharpnessParam],
                    relativeTime: 0
                )
            ]

        case .north:
            events = [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensityParam, sharpnessParam],
                    relativeTime: 0
                ),
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensityParam, sharpnessParam],
                    relativeTime: 0.08
                ),
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensityParam, sharpnessParam],
                    relativeTime: 0.16
                )
            ]

        case .neutral:
            return
        }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            playFallback(polarity: polarity, strength: clampedStrength)
        }
    }
#endif

    private func playFallback(polarity: Polarity, strength: Double) {
        switch polarity {
        case .south:
            // South Pole: Single downward directional haptic.
            device.play(.directionDown)

        case .north:
            // North Pole: Triple upward directional haptic, 80ms apart.
            device.play(.directionUp)
            Task {
                try? await Task.sleep(nanoseconds: 80_000_000)
                device.play(.directionUp)
                try? await Task.sleep(nanoseconds: 80_000_000)
                device.play(.directionUp)
            }
            
        case .neutral:
            break
        }
    }
}
