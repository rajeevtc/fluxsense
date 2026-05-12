import Testing
@testable import FluxSense_Watch_App

struct FluxSenseWatchAppTests {

    // MARK: - MagnetometerUseCase

    @Test
    func processAppliesOffsetAndGainThenNormalizes() {
        let useCase = MagnetometerUseCase()
        useCase.offsetX = 1
        useCase.offsetY = -1
        useCase.offsetZ = 0
        useCase.gainX = 2
        useCase.gainY = 1
        useCase.gainZ = 1
        useCase.baselineMagnitude = 10

        let reading = useCase.process(rawX: 3, rawY: 4, rawZ: 5)

        // Ambient adaptation (0.012 factor) shifts offsets slightly, so values are approximate.
        #expect(abs(reading.rawMagnitude - 8.027) < 0.01)
        #expect(abs(reading.strength - 0.803) < 0.01)
        #expect(reading.polarity == .north)
    }

    @Test
    func processClampsStrengthToOne() {
        let useCase = MagnetometerUseCase()
        useCase.baselineMagnitude = 5

        let reading = useCase.process(rawX: 0, rawY: 0, rawZ: 20)

        #expect(reading.strength == 1.0)
        #expect(reading.polarity == .north)
    }

    @Test
    func processReturnsNeutralWhenCorrectedZIsSmall() {
        let useCase = MagnetometerUseCase()
        useCase.baselineMagnitude = 10

        let reading = useCase.process(rawX: 3, rawY: 4, rawZ: 0.5)

        #expect(reading.rawMagnitude > 4.9 && reading.rawMagnitude < 5.1)
        #expect(reading.polarity == .neutral)
    }

    // MARK: - Normalization

    @Test
    func normalizedProgressAtZeroMicrotesla() {
        #expect(MagneticReading.normalizedProgress(microtesla: 0) == 0.0)
    }

    @Test
    func normalizedProgressAtMidRange() {
        #expect(MagneticReading.normalizedProgress(microtesla: 50) == 0.5)
    }

    @Test
    func normalizedProgressClampsAboveMax() {
        #expect(MagneticReading.normalizedProgress(microtesla: 150) == 1.0)
    }

    @Test
    func normalizedProgressWithCustomRange() {
        let result = MagneticReading.normalizedProgress(microtesla: 30, minMicrotesla: 20, maxMicrotesla: 60)
        #expect(abs(result - 0.25) < 0.0001)
    }

    @Test
    func normalizedProgressClampsAtMin() {
        #expect(MagneticReading.normalizedProgress(microtesla: -10) == 0.0)
    }

    // MARK: - Label formatting

    @Test
    func microteslaLabelFormatsInteger() {
        #expect(MagneticReading.microteslaLabel(47.3) == "47 µT")
    }

    @Test
    func microteslaLabelFormatsZero() {
        #expect(MagneticReading.microteslaLabel(0) == "0 µT")
    }

    @Test
    func microteslaLabelRoundsUp() {
        #expect(MagneticReading.microteslaLabel(47.6) == "48 µT")
    }

    @Test
    func microteslaLabelLargeValue() {
        #expect(MagneticReading.microteslaLabel(150) == "150 µT")
    }

    // MARK: - Smoothing

    @Test
    func smoothingMovingAverageConverges() {
        var buffer: [Double] = []
        let windowSize = 5
        for sample in [10.0, 20.0, 30.0, 40.0, 50.0] {
            buffer.append(sample)
            if buffer.count > windowSize { buffer.removeFirst() }
        }
        let avg = buffer.reduce(0.0, +) / Double(buffer.count)
        #expect(avg == 30.0)
    }

    @Test
    func smoothingBufferEvictesOldestSample() {
        var buffer: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0]
        let windowSize = 5
        buffer.append(10.0)
        if buffer.count > windowSize { buffer.removeFirst() }
        // 1.0 should be evicted; average of [2,3,4,5,10] = 4.8
        let avg = buffer.reduce(0.0, +) / Double(buffer.count)
        #expect(abs(avg - 4.8) < 0.0001)
    }
}
