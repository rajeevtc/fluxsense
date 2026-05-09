import Testing
@testable import FluxSense_Watch_App

struct FluxSenseWatchAppTests {
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

        #expect(reading.rawMagnitude == 7)
        #expect(reading.strength == 0.7)
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

        #expect(reading.rawMagnitude == 5.024937810560445)
        #expect(reading.polarity == .neutral)
    }
}
