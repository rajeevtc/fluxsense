import SwiftUI
import WatchKit

struct ContentView: View {
    @StateObject private var magnetometer = MagnetometerService()
    @StateObject private var runtimeSession = RuntimeSessionManager()
    @StateObject private var stealthManager = StealthManager()
    @State private var haptics = HapticService()
    @State private var gain = 1.0

    var body: some View {
        ZStack {
            TabView {
                sensingScreen
                settingsScreen
            }
            .tabViewStyle(.page)

            if stealthManager.isStealthModeEnabled {
                stealthOverlay
            }
        }
        .onAppear {
            gain = magnetometer.gain
            runtimeSession.onSessionEnded = {
                stealthManager.exitStealthMode()
                updateHaptics()
            }

            magnetometer.start()
        }
        .onDisappear {
            runtimeSession.invalidateSession()
            magnetometer.stop()
            haptics.stop()
        }
        .onChange(of: magnetometer.currentReading.strengthPercentage) { _ in
            updateHaptics()
        }
        .onChange(of: magnetometer.currentReading.polarity) { _ in
            updateHaptics()
        }
        .onChange(of: gain) { value in
            magnetometer.gain = value
        }
    }

    private var sensingScreen: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 10)

                Circle()
                    .trim(from: 0, to: CGFloat(magnetometer.currentReading.strength))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.blue, .cyan, .green]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(magnetometer.currentReading.strengthPercentage)%")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    Text(polarityShortLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(polarityColor)
                }
            }
            .frame(width: 150, height: 150)

            Text(String(format: "%.1f µT", magnetometer.currentReading.rawMagnitude))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(runtimeLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var settingsScreen: some View {
        VStack(spacing: 10) {
            Text("Calibration")
                .font(.headline)

            Button("Zero Sensor") {
                magnetometer.calibrate()
            }
            .buttonStyle(.borderedProminent)

            VStack(spacing: 4) {
                HStack {
                    Text("Gain")
                    Spacer()
                    Text(String(format: "%.1fx", gain))
                        .monospacedDigit()
                }
                Slider(value: $gain, in: 0.5 ... 4.0, step: 0.1)
            }

            Toggle("Stealth Mode", isOn: stealthBinding)
                .toggleStyle(.switch)

        }
        .padding(.horizontal, 8)
    }

    private var stealthOverlay: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .onTapGesture(count: 2) {
                    stealthManager.exitStealthMode()
                }

            Circle()
                .stroke(Color.white.opacity(0.06 + (0.25 * stealthManager.unlockCompletion)), lineWidth: 2)
                .frame(
                    width: 30 + (90 * stealthManager.unlockCompletion),
                    height: 30 + (90 * stealthManager.unlockCompletion)
                )
                .blur(radius: 0.4)

        }
    }

    private var stealthBinding: Binding<Bool> {
        Binding(
            get: { stealthManager.isStealthModeEnabled },
            set: { isEnabled in
                if isEnabled {
                    stealthManager.enterStealthMode()
                    runtimeSession.startSessionIfNeeded()
                    WKInterfaceDevice.current().play(.success)
                } else {
                    stealthManager.exitStealthMode()
                    runtimeSession.invalidateSession()
                    updateHaptics()
                }
            }
        )
    }

    private var runtimeLabel: String {
        guard stealthManager.isStealthModeEnabled, runtimeSession.isRunning else {
            return "Stealth: Off"
        }
        let minutes = runtimeSession.remainingSeconds / 60
        let seconds = runtimeSession.remainingSeconds % 60
        return String(format: "Stealth: %02d:%02d", minutes, seconds)
    }

    private func updateHaptics() {
        guard !stealthManager.isStealthModeEnabled else { return }

        let reading = magnetometer.currentReading
        if reading.polarity == .neutral || reading.strength < 0.08 {
            haptics.stop()
            return
        }
        haptics.play(for: reading)
    }

    private var polarityShortLabel: String {
        switch magnetometer.currentReading.polarity {
        case .north: "N"
        case .south: "S"
        case .neutral: "-"
        }
    }

    private var polarityColor: Color {
        switch magnetometer.currentReading.polarity {
        case .north: .red
        case .south: .blue
        case .neutral: .gray
        }
    }
}

#Preview {
    ContentView()
}
