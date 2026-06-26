import SwiftUI

struct BreathingExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phase: BreathPhase = .inhale
    @State private var cycleCount = 0
    @State private var isActive = false
    @State private var circleScale: CGFloat = 0.5

    enum BreathPhase: String {
        case inhale = "Breathe in"
        case hold = "Hold"
        case exhale = "Breathe out"
        case rest = "Rest"
    }

    private let inhaleDuration: Double = 4
    private let holdDuration: Double = 4
    private let exhaleDuration: Double = 6
    private let restDuration: Double = 2
    private let totalCycles = 4

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PulseColors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(PulseColors.fillSubtle)
                        .clipShape(Circle())
                }
            }
            .padding(20)

            Spacer()

            ZStack {
                Circle()
                    .fill(PulseColors.accent.opacity(0.08))
                    .frame(width: 240, height: 240)

                Circle()
                    .fill(PulseColors.accent.opacity(0.15))
                    .frame(width: 240 * circleScale, height: 240 * circleScale)

                Circle()
                    .fill(PulseColors.accent.opacity(0.3))
                    .frame(width: 120 * circleScale, height: 120 * circleScale)

                VStack(spacing: 6) {
                    Text(phase.rawValue)
                        .font(PulseFont.title(22))
                        .foregroundStyle(PulseColors.textPrimary)
                    if isActive {
                        Text("Cycle \(cycleCount + 1) of \(totalCycles)")
                            .font(PulseFont.body(13))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                }
            }

            Spacer()

            if !isActive {
                VStack(spacing: 16) {
                    Text("4–4–6 breathing")
                        .font(PulseFont.bodySemibold(16))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text("Activates your parasympathetic nervous system to reduce stress and improve focus.")
                        .font(PulseFont.body(14))
                        .foregroundStyle(PulseColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Button { startBreathing() } label: {
                        Text("Start")
                            .font(PulseFont.bodySemibold(16))
                            .foregroundStyle(.white)
                            .frame(width: 180, height: 50)
                            .background(PulseColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    }
                    .padding(.top, 8)
                }
            } else if cycleCount >= totalCycles {
                VStack(spacing: 12) {
                    Text("Session complete")
                        .font(PulseFont.bodySemibold(18))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text("You completed \(totalCycles) cycles. Great job!")
                        .font(PulseFont.body(14))
                        .foregroundStyle(PulseColors.textSecondary)
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(PulseFont.bodySemibold(16))
                            .foregroundStyle(.white)
                            .frame(width: 140, height: 46)
                            .background(PulseColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                    }
                    .padding(.top, 8)
                }
            }

            Spacer()
                .frame(height: 60)
        }
        .background(PulseColors.background)
    }

    private func startBreathing() {
        HapticService.impact(.medium)
        isActive = true
        cycleCount = 0
        runCycle()
    }

    private func runCycle() {
        guard cycleCount < totalCycles else { return }

        phase = .inhale
        HapticService.impact(.soft)
        withAnimation(.easeInOut(duration: inhaleDuration)) { circleScale = 1.0 }

        DispatchQueue.main.asyncAfter(deadline: .now() + inhaleDuration) {
            phase = .hold
            HapticService.impact(.light)
            DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration) {
                phase = .exhale
                HapticService.impact(.soft)
                withAnimation(.easeInOut(duration: exhaleDuration)) { circleScale = 0.5 }
                DispatchQueue.main.asyncAfter(deadline: .now() + exhaleDuration) {
                    phase = .rest
                    DispatchQueue.main.asyncAfter(deadline: .now() + restDuration) {
                        cycleCount += 1
                        if cycleCount < totalCycles {
                            runCycle()
                        } else {
                            phase = .rest
                            HapticService.success()
                        }
                    }
                }
            }
        }
    }
}
