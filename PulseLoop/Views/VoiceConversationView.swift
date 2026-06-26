import SwiftUI
import SwiftData

/// The voice-native surface: a full-screen, hands-free conversation where the user
/// just talks and the assistant organizes their life out loud. It owns a
/// `VoiceSessionController` that runs the listen → think → act → speak loop on top
/// of the existing Coach pipeline, so every spoken request can create tasks/notes,
/// log mood/meals/habits, save memories, and more — then confirm by voice.
struct VoiceConversationView: View {
    let conversationId: UUID
    var onClose: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(RingSyncCoordinator.self) private var coordinator

    @State private var voice = VoiceServices()
    @State private var controller: VoiceSessionController?

    private var phase: VoiceSessionController.Phase { controller?.phase ?? .idle }

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 8)
                orbSection
                Spacer(minLength: 8)
                transcriptArea
                controls
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .task {
            let c = VoiceSessionController(
                voice: voice,
                conversationId: conversationId,
                context: modelContext,
                coordinator: coordinator
            )
            controller = c
            await c.start()
        }
        .onDisappear { controller?.stop() }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.05, blue: 0.08), Color.black],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [accent.opacity(0.18 + Double(min(voice.audioLevel, 1)) * 0.25), .clear],
                center: .center, startRadius: 10, endRadius: 360
            )
            .animation(.easeOut(duration: 0.15), value: voice.audioLevel)
        }
        .ignoresSafeArea()
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.08), in: Circle())
            }
            Spacer()
            VStack(spacing: 2) {
                Text("VOICE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.45))
                Text("\(controller?.engineLabel ?? "…") · hands-free")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer()
            Button { controller?.togglePause() } label: {
                Image(systemName: phase == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .disabled(phase == .denied)
        }
    }

    // MARK: - Orb

    private var orbSection: some View {
        VStack(spacing: 22) {
            Button { controller?.tapOrb() } label: {
                VoiceOrb(level: CGFloat(min(voice.audioLevel, 1)), phase: phase, accent: accent)
                    .frame(width: 200, height: 200)
            }
            .buttonStyle(.plain)

            Text(caption)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: caption)

            VoiceWaveform(level: CGFloat(min(voice.audioLevel, 1)),
                          active: phase == .listening,
                          accent: accent)
                .frame(height: 28)
                .opacity(phase == .listening ? 1 : 0.25)
                .animation(.easeInOut(duration: 0.3), value: phase)
                .padding(.horizontal, 48)

            if phase == .denied {
                Text("Enable microphone & speech access in Settings to talk hands-free.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private var caption: String {
        switch phase {
        case .idle: return "Getting ready…"
        case .listening:
            let live = controller?.partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return live.isEmpty ? "Listening…" : "“\(live)”"
        case .thinking: return "Organizing…"
        case .speaking: return "Speaking… tap to jump in"
        case .paused: return "Paused · tap the orb to resume"
        case .denied: return "Microphone access needed"
        }
    }

    // MARK: - Transcript / session turns

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    if (controller?.turns.isEmpty ?? true) && phase != .denied {
                        hint
                    }
                    ForEach(controller?.turns ?? []) { turn in
                        TurnCard(turn: turn).id(turn.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 240)
            .onChange(of: controller?.turns.count ?? 0) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var hint: some View {
        VStack(spacing: 6) {
            Text("Try saying…")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            ForEach(["“Remind me to call mom tomorrow at 6”",
                     "“Log that I had eggs and coffee for breakfast”",
                     "“I'm feeling a 4 today, low energy”",
                     "“Take a note: ideas for the weekend trip”"], id: \.self) { ex in
                Text(ex)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 28) {
            controlButton(
                icon: phase == .listening ? "waveform" : "mic.fill",
                label: phase == .listening ? "Send" : "Talk"
            ) { controller?.tapOrb() }

            controlButton(icon: "xmark", label: "Done") { onClose() }
        }
        .padding(.top, 14)
    }

    private func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.1), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .buttonStyle(.plain)
    }

    private var accent: Color { Color(red: 0.45, green: 0.62, blue: 1.0) }
}

// MARK: - Animated orb

/// A breathing gradient orb whose rings react to the live audio level and whose
/// motion changes with the session phase: a calm idle breath, reactive listening
/// rings, an orbiting "thinking" dot, and a steady speaking pulse. Driven by
/// springs and a continuous phase clock so transitions feel fluid and modern.
private struct VoiceOrb: View {
    let level: CGFloat
    let phase: VoiceSessionController.Phase
    let accent: Color

    @State private var pulse = false
    @State private var spin = 0.0

    var body: some View {
        ZStack {
            // Reactive listening rings.
            ForEach(0..<3) { i in
                Circle()
                    .stroke(accent.opacity(0.28 - Double(i) * 0.07), lineWidth: 1.5)
                    .scaleEffect(ringScale(i))
                    .opacity(phase == .listening || phase == .speaking ? 1 : 0.45)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: level)
            }

            // Glowing core.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(0.95), accent.opacity(0.35), .clear],
                        center: .center, startRadius: 2, endRadius: 110
                    )
                )
                .scaleEffect(coreScale)
                .blur(radius: 2)
                .animation(.spring(response: 0.28, dampingFraction: 0.62), value: level)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: phase)

            // Specular highlight.
            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: 22, height: 22)
                .offset(x: -10, y: -10)
                .blur(radius: 1)
                .opacity(0.6)

            // Thinking: an orbiting dot to show work is happening.
            if phase == .thinking {
                Circle()
                    .fill(.white.opacity(0.95))
                    .frame(width: 10, height: 10)
                    .offset(y: -64)
                    .rotationEffect(.degrees(spin))
                    .blur(radius: 0.5)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulse)
        .onAppear {
            pulse = true
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                spin = 360
            }
        }
    }

    private var coreScale: CGFloat {
        switch phase {
        case .listening: return 0.66 + level * 0.55
        case .thinking: return pulse ? 0.9 : 0.74
        case .speaking: return pulse ? 0.94 : 0.8
        case .paused, .idle, .denied: return pulse ? 0.72 : 0.66
        }
    }

    private func ringScale(_ i: Int) -> CGFloat {
        let base = 1.0 + CGFloat(i) * 0.22
        let reactive = (phase == .listening || phase == .speaking) ? level * 0.45 : 0
        return base + reactive + (pulse ? 0.05 : 0)
    }
}

// MARK: - Waveform

/// A live equalizer bar strip that mirrors the mic level while listening. Each
/// bar has its own phase offset so the strip ripples organically instead of all
/// bars moving in lockstep, giving the listening state a modern, lively feel.
private struct VoiceWaveform: View {
    let level: CGFloat
    let active: Bool
    let accent: Color

    private let barCount = 21

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(accent.opacity(active ? 0.85 : 0.3))
                        .frame(width: 3, height: barHeight(index: i, time: t))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func barHeight(index i: Int, time t: Double) -> CGFloat {
        let minH: CGFloat = 4
        let maxH: CGFloat = 28
        guard active else { return minH }
        // Bell-shaped envelope so the center bars are tallest, plus a per-bar
        // sine ripple, scaled by the live audio level.
        let center = Double(barCount - 1) / 2
        let dist = abs(Double(i) - center) / center
        let envelope = cos(dist * .pi / 2)
        let ripple = (sin(t * 6 + Double(i) * 0.6) + 1) / 2
        let amplitude = max(0.12, Double(level)) * (0.55 + 0.45 * ripple)
        let h = minH + (maxH - minH) * CGFloat(envelope * amplitude)
        return max(minH, min(maxH, h))
    }
}

// MARK: - Turn card

/// One spoken exchange: what the user said and what got organized.
private struct TurnCard: View {
    let turn: VoiceSessionController.Turn

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turn.userText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            if turn.isPending {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini).tint(.white)
                    Text("organizing…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                }
            } else {
                if !turn.actionsTaken.isEmpty {
                    FlowChips(items: turn.actionsTaken, systemImage: "checkmark.circle.fill")
                }
                if !turn.assistantSummary.isEmpty {
                    Text(turn.assistantSummary)
                        .font(.system(size: 13))
                        .foregroundStyle(turn.isError ? Color.orange.opacity(0.9) : .white.opacity(0.65))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

/// Wrapping chips for the "what got organized" confirmations.
private struct FlowChips: View {
    let items: [String]
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.green.opacity(0.85))
                    Text(item)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }
}
