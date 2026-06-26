import SwiftUI

struct MorningBriefView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var voiceServices = VoiceServices()
    @State private var showTranscript = false
    @State private var protectTapped = false

    /// The spoken brief. Single source of truth for both the play button (TTS)
    /// and the transcript card.
    private let briefText = "Good morning. You slept 6h 10m  -  lighter than usual. Three things today: standup at 9:30, lunch with Maya, dentist moved to Thursday. I cleared your inbox to 2 tasks and drafted both replies. Take your morning stack  -  and I'd protect tonight's sleep."

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                VStack(spacing: 14) {
                    playerCard
                    if showTranscript { transcriptCard }
                    predictiveAlertCard
                    scheduleCard
                    recapCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
        }
        .background(PulseColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Morning brief")
        .onDisappear { voiceServices.stopSpeaking() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dayString())
                .font(PulseFont.body(13))
                .foregroundStyle(PulseColors.textMuted)
            Text("Your morning brief")
                .font(PulseFont.title(28))
                .foregroundStyle(PulseColors.textPrimary)
            HStack(spacing: 6) {
                Circle().fill(PulseColors.success).frame(width: 7, height: 7)
                Text("Calm mode on  -  your HRV is low")
                    .font(PulseFont.bodyMedium(12))
                    .foregroundStyle(PulseColors.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(PulseColors.fillSubtle)
            .clipShape(Capsule())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var playerCard: some View {
        HStack(spacing: 14) {
            Button {
                voiceServices.toggleSpeaking(briefText)
            } label: {
                Circle()
                    .fill(PulseColors.accent)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: voiceServices.isSpeaking ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
            }
            .accessibilityLabel(voiceServices.isSpeaking ? "Pause brief" : "Play brief")
            VStack(alignment: .leading, spacing: 3) {
                Text("Brief me")
                    .font(PulseFont.bodySemibold(15))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("30-sec spoken rundown")
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
            Button { showTranscript.toggle() } label: {
                Text(showTranscript ? "Hide" : "Read")
                    .font(PulseFont.bodyMedium(12))
                    .foregroundStyle(PulseColors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PulseColors.fillSubtle)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private var transcriptCard: some View {
        Text("\"\(briefText)\"")
            .font(PulseFont.body(14))
            .foregroundStyle(PulseColors.textSecondary)
            .italic()
            .lineSpacing(3)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseColors.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var predictiveAlertCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(PulseColors.warning)
                Text("HEADS UP")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.6)
                Spacer()
                Text("Predictive · sleep")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PulseColors.warningBackground)
                    .clipShape(Capsule())
            }
            Text("You tend to get sick after 3 short-sleep nights. This is night 2  -  want me to clear tonight and set a wind-down at 9:30?")
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textSecondary)
                .lineSpacing(3)
            Button { withAnimation { protectTapped = true } } label: {
                Text(protectTapped ? "Wind-down reminder set ✓" : "Protect tonight")
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(.white)
                    .frame(width: 200, height: 44)
                    .background(protectTapped ? PulseColors.success : PulseColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(protectTapped)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REBALANCED FOR YOUR ENERGY")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            PlanBlock(time: "9–11am", title: "Deep work · moved earlier", note: "", emoji: "bolt.fill")
            PlanBlock(time: "2–3pm", title: "Admin & replies · low-energy dip", note: "", emoji: "battery.50percent")
            PlanBlock(time: "9:30pm", title: "Wind-down · protect sleep", note: "", emoji: "moon.fill")
        }
    }

    private var recapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PULSELOOP · 2026 SO FAR")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            Text("Your year in review")
                .font(PulseFont.bodySemibold(16))
                .foregroundStyle(PulseColors.textPrimary)

            HStack(spacing: 0) {
                RecapStat(value: "94%", label: "meds taken")
                Spacer()
                RecapStat(value: "186", label: "workouts")
                Spacer()
                RecapStat(value: "7h12", label: "avg sleep")
            }

            Button { dismiss() } label: {
                Text("See your recap →")
                    .font(PulseFont.bodyMedium(13))
                    .foregroundStyle(PulseColors.textSecondary)
            }
        }
        .padding(16)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private func dayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }
}

struct RecapStat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(PulseFont.titleMedium(22))
                .foregroundStyle(PulseColors.textPrimary)
            Text(label)
                .font(PulseFont.body(11))
                .foregroundStyle(PulseColors.textMuted)
        }
    }
}
