import SwiftUI
import SwiftData

struct VoiceCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    /// Optional so the global mic (Command Palette / Root) can present this without a nav stack.
    /// When provided, the freshly created note is opened after saving.
    var path: Binding<NavigationPath>?
    /// Alternative navigation hook for contexts that route via a callback instead of a path
    /// (e.g. the Command Palette). Called with the new note's route after saving.
    var onSaved: ((AppRoute) -> Void)?

    @State private var voiceServices = VoiceServices()
    @State private var barLevels: [CGFloat] = Array(repeating: 0.1, count: 15)
    @State private var animationTimer: Timer?

    @State private var isProcessing = false
    @State private var plan: VoiceCaptureRouter.CapturePlan?
    @State private var showResult = false
    @State private var showTranscript = false
    @State private var capturedDuration = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                if showResult, let result = plan {
                    resultCard(result)
                } else {
                    captureCard
                }
            }
            .padding(8)
            .ignoresSafeArea(edges: .bottom)
        }
        .onAppear {
            Task {
                let authorized = await voiceServices.requestSpeechAuthorization()
                if authorized {
                    voiceServices.startListening()
                    startWaveformAnimation()
                }
            }
        }
        .onDisappear {
            voiceServices.stopListening()
            animationTimer?.invalidate()
        }
    }

    // MARK: - Capture Card

    private var captureCard: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            if isProcessing {
                processingIndicator
            } else {
                listeningIndicator
                transcriptText
                waveformBars
            }
            Spacer()
            if !isProcessing {
                stopButton
                footerLabel
            }
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity, minHeight: 500)
        .background(Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 55, style: .continuous))
    }

    private var header: some View {
        HStack {
            Text("VOICE CAPTURE")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Color(UIColor.systemBackground).opacity(0.5))
            Spacer()
            Button { stopAndDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(UIColor.systemBackground).opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Color(UIColor.systemBackground).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
    }

    private var processingIndicator: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Color(UIColor.systemBackground))
                .controlSize(.large)
            Text("Organizing your note…")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(UIColor.systemBackground))
            Text("Turning what you said into a clean note and tasks")
                .font(.system(size: 13))
                .foregroundStyle(Color(UIColor.systemBackground).opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var listeningIndicator: some View {
        Text("Listening... \(formattedTime)")
            .font(.system(size: 14))
            .foregroundStyle(Color(UIColor.systemBackground).opacity(0.5))
            .padding(.bottom, 16)
    }

    private var transcriptText: some View {
        Group {
            if voiceServices.transcribedText.isEmpty {
                Text("\u{201C}...\u{201D}")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color(UIColor.systemBackground).opacity(0.3))
            } else {
                Text("\u{201C}\(voiceServices.transcribedText)\u{201D}")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color(UIColor.systemBackground))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
    }

    private var waveformBars: some View {
        HStack(spacing: 4) {
            ForEach(0..<barLevels.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(UIColor.systemBackground))
                    .frame(width: 4, height: barLevels[i])
            }
        }
        .frame(height: 60)
        .padding(.bottom, 40)
    }

    private var stopButton: some View {
        Button { stopAndProcess() } label: {
            ZStack {
                Circle()
                    .fill(Color(UIColor.systemBackground))
                    .frame(width: 72, height: 72)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary)
                    .frame(width: 22, height: 22)
            }
        }
        .padding(.bottom, 12)
    }

    private var footerLabel: some View {
        Text("Tap to stop \u{00B7} AI will sort it")
            .font(.system(size: 13))
            .foregroundStyle(Color(UIColor.systemBackground).opacity(0.5))
    }

    // MARK: - Result Card

    private func resultCard(_ result: VoiceCaptureRouter.CapturePlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AI ORGANIZED")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color(UIColor.systemBackground).opacity(0.45))
                Spacer()
                Button { showTranscript.toggle() } label: {
                    Text(showTranscript ? "Hide transcript" : "Original")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(UIColor.systemBackground).opacity(0.6))
                }
            }
            .padding(.top, 22)
            .padding(.horizontal, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(result.title)
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(Color(UIColor.systemBackground))

                    if showTranscript {
                        Text(result.transcript)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(UIColor.systemBackground).opacity(0.55))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(UIColor.systemBackground).opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    ForEach(Array(result.sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.heading)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color(UIColor.systemBackground))
                            ForEach(section.bullets, id: \.self) { bullet in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(Color(UIColor.systemBackground).opacity(0.5))
                                    Text(bullet)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color(UIColor.systemBackground).opacity(0.85))
                                }
                            }
                        }
                    }

                    if !result.tasks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Text("Tasks")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Color(UIColor.systemBackground))
                                if result.scheduledCount > 0 {
                                    Text("· scheduled this week")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color(UIColor.systemBackground).opacity(0.5))
                                }
                            }
                            ForEach(Array(result.tasks.enumerated()), id: \.offset) { _, task in
                                HStack(spacing: 10) {
                                    Circle()
                                        .stroke(Color(UIColor.systemBackground).opacity(0.4), lineWidth: 1.5)
                                        .frame(width: 16, height: 16)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(task.title)
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color(UIColor.systemBackground).opacity(0.9))
                                        if task.group != "Inbox" || task.dayOffset != nil {
                                            Text(taskSubtitle(task))
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color(UIColor.systemBackground).opacity(0.45))
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }

            Button { saveEverywhere(result) } label: {
                Text(saveButtonLabel(result))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(UIColor.systemBackground))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .background(Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 55, style: .continuous))
    }

    private func taskSubtitle(_ task: VoiceCaptureRouter.CapturePlan.PlannedTask) -> String {
        var parts: [String] = []
        if task.group != "Inbox" { parts.append(task.group) }
        if let offset = task.dayOffset { parts.append(dayLabel(offset)) }
        return parts.joined(separator: " · ")
    }

    private func dayLabel(_ offset: Int) -> String {
        let cal = Calendar.current
        guard cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date())) != nil else { return "" }
        if offset == 0 { return "Today" }
        if offset == 1 { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        let date = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date()))!
        return f.string(from: date)
    }

    private func saveButtonLabel(_ result: VoiceCaptureRouter.CapturePlan) -> String {
        if result.tasks.isEmpty { return "Save note" }
        return "Save note + \(result.taskCount) task\(result.taskCount == 1 ? "" : "s")"
    }

    // MARK: - Logic

    private var formattedTime: String {
        let m = voiceServices.elapsedSeconds / 60
        let s = voiceServices.elapsedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func startWaveformAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            Task { @MainActor in
                let level = CGFloat(voiceServices.audioLevel)
                withAnimation(.easeInOut(duration: 0.08)) {
                    for i in 0..<barLevels.count {
                        let base: CGFloat = 8
                        let maxHeight: CGFloat = 50
                        let randomFactor = CGFloat.random(in: 0.4...1.0)
                        barLevels[i] = base + (maxHeight * level * randomFactor)
                    }
                }
            }
        }
    }

    /// Stops listening and regenerates the transcript into a structured plan.
    private func stopAndProcess() {
        capturedDuration = voiceServices.elapsedSeconds
        let captured = voiceServices.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        voiceServices.stopListening()
        animationTimer?.invalidate()
        HapticService.success()

        guard !captured.isEmpty else {
            dismiss()
            return
        }

        isProcessing = true
        Task {
            let router = VoiceCaptureRouter()
            let result = await router.plan(from: captured)
            await MainActor.run {
                plan = result
                showResult = true
                isProcessing = false
                HapticService.success()
            }
        }
    }

    private func stopAndDismiss() {
        voiceServices.stopListening()
        animationTimer?.invalidate()
        dismiss()
    }

    /// Creates a polished note AND files every classified task into the app
    /// (with due dates when scheduled this week), then opens the note if a path exists.
    private func saveEverywhere(_ result: VoiceCaptureRouter.CapturePlan) {
        let router = VoiceCaptureRouter()
        let applied = router.apply(result, in: modelContext,
                                   summaryPrefix: "Voice capture · \(formattedDuration)")
        HapticService.success()
        dismiss()
        let route = AppRoute.noteEditor(applied.note.id)
        path?.wrappedValue.append(route)
        onSaved?(route)
    }

    private var formattedDuration: String {
        let m = capturedDuration / 60
        let s = capturedDuration % 60
        return String(format: "%d:%02d", m, s)
    }
}

#Preview {
    VoiceCaptureView()
}
