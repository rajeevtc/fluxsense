import SwiftUI
import WatchKit

// MARK: - Circular Progress View

struct CircularProgressView: View {
    let microtesla: Double
    let polarity: Polarity
    var minMicrotesla: Double = 0
    var maxMicrotesla: Double = 100

    private var progress: Double {
        MagneticReading.normalizedProgress(
            microtesla: microtesla,
            minMicrotesla: minMicrotesla,
            maxMicrotesla: maxMicrotesla
        )
    }

    private var polarityShortLabel: String {
        switch polarity {
        case .north: "N"
        case .south: "S"
        case .neutral: "-"
        }
    }

    private var polarityColor: Color {
        switch polarity {
        case .north: .red
        case .south: .blue
        case .neutral: .gray
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.25), lineWidth: 10)

            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.blue, .cyan, .green]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.15), value: progress)

            VStack(spacing: 2) {
                Text(MagneticReading.microteslaLabel(microtesla))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(polarityShortLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(polarityColor)
            }
            .padding(.horizontal, 20)
        }
        .accessibilityLabel("Magnetic intensity \(Int(microtesla.rounded())) microteslas")
    }
}

// MARK: - Content View

struct ContentView: View {
    @Environment(\.dismiss) private var dismiss
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
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.bold))
                }
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
            CircularProgressView(
                microtesla: magnetometer.currentReading.rawMagnitude,
                polarity: magnetometer.currentReading.polarity
            )
            .frame(width: 150, height: 150)

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
}

// MARK: - Previews

#Preview("Content View") {
    ContentView()
}

#Preview("Circular Progress") {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            CircularProgressView(microtesla: 0, polarity: .neutral)
                .frame(width: 120, height: 120)
            CircularProgressView(microtesla: 25, polarity: .south)
                .frame(width: 120, height: 120)
            CircularProgressView(microtesla: 50, polarity: .north)
                .frame(width: 120, height: 120)
        }
        HStack(spacing: 12) {
            CircularProgressView(microtesla: 100, polarity: .north)
                .frame(width: 120, height: 120)
            // 150 µT clamps visually to full ring
            CircularProgressView(microtesla: 150, polarity: .south)
                .frame(width: 120, height: 120)
        }
    }
    .padding()
}
