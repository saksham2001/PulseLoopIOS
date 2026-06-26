import SwiftUI

struct WatchTabView: View {
    var body: some View {
        TabView {
            TodayGlanceView()
            ProtocolChecklistView()
            RingsView()
            BreatheView()
            BriefPlayerView()
        }
        .tabViewStyle(.verticalPage)
    }
}

// MARK: - Today Glance

struct TodayGlanceView: View {
    @Environment(WatchSessionManager.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.headline)
                .foregroundStyle(WatchColors.textPrimary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(session.steps)")
                        .font(.title2.bold())
                        .foregroundStyle(WatchColors.ring)
                    Text("steps")
                        .font(.caption2)
                        .foregroundStyle(WatchColors.textMuted)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(session.heartRate)")
                        .font(.title2.bold())
                        .foregroundStyle(WatchColors.alert)
                    Text("bpm")
                        .font(.caption2)
                        .foregroundStyle(WatchColors.textMuted)
                }
            }

            if !session.nextTask.isEmpty {
                Divider().background(WatchColors.textMuted)
                Text("Next")
                    .font(.caption2)
                    .foregroundStyle(WatchColors.textMuted)
                Text(session.nextTask)
                    .font(.caption)
                    .foregroundStyle(WatchColors.textPrimary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

// MARK: - Protocol Checklist

struct ProtocolChecklistView: View {
    @Environment(WatchSessionManager.self) private var session
    @State private var checked: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Protocol")
                    .font(.headline)
                    .foregroundStyle(WatchColors.textPrimary)

                ForEach(session.protocolDue.isEmpty ? demoProtocol : session.protocolDue, id: \.self) { item in
                    Button {
                        if checked.contains(item) { checked.remove(item) }
                        else { checked.insert(item) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: checked.contains(item) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(checked.contains(item) ? WatchColors.success : WatchColors.textMuted)
                            Text(item)
                                .font(.caption)
                                .foregroundStyle(WatchColors.textPrimary)
                                .strikethrough(checked.contains(item))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    private var demoProtocol: [String] {
        ["Vitamin D3", "Omega-3", "Creatine", "Magnesium", "BPC-157"]
    }
}

// MARK: - Activity Rings

struct RingsView: View {
    @Environment(WatchSessionManager.self) private var session

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(WatchColors.ring.opacity(0.2), lineWidth: 12)
                    .frame(width: 100, height: 100)
                Circle()
                    .trim(from: 0, to: min(CGFloat(session.steps) / 10000.0, 1.0))
                    .stroke(WatchColors.ring, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(session.steps)")
                        .font(.title3.bold())
                        .foregroundStyle(WatchColors.textPrimary)
                    Text("/ 10,000")
                        .font(.caption2)
                        .foregroundStyle(WatchColors.textMuted)
                }
            }
            Text("Steps")
                .font(.caption)
                .foregroundStyle(WatchColors.textSecondary)
        }
    }
}

// MARK: - Breathe / Grounding

struct BreatheView: View {
    @State private var phase: BreathePhase = .inhale
    @State private var scale: CGFloat = 0.6
    @State private var timer: Timer?

    enum BreathePhase: String {
        case inhale = "Breathe in"
        case hold = "Hold"
        case exhale = "Breathe out"
    }

    var body: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(WatchColors.success.opacity(0.3))
                .frame(width: 80, height: 80)
                .scaleEffect(scale)
                .animation(.easeInOut(duration: 4), value: scale)

            Text(phase.rawValue)
                .font(.headline)
                .foregroundStyle(WatchColors.textPrimary)

            Text("In for 4 · hold · out for 6")
                .font(.caption2)
                .foregroundStyle(WatchColors.textMuted)

            Button(isBreathing ? "Stop" : "Start") {
                if isBreathing { stopBreathing() }
                else { startBreathing() }
            }
            .tint(WatchColors.success)
        }
    }

    private var isBreathing: Bool { timer != nil }

    private func startBreathing() {
        phase = .inhale
        scale = 1.0
        var elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsed += 1
            let cycle = elapsed % 14
            if cycle < 4 {
                phase = .inhale
                scale = 0.6 + 0.4 * (CGFloat(cycle + 1) / 4.0)
            } else if cycle < 8 {
                phase = .hold
            } else {
                phase = .exhale
                scale = 1.0 - 0.4 * (CGFloat(cycle - 7) / 6.0)
            }
        }
    }

    private func stopBreathing() {
        timer?.invalidate()
        timer = nil
        scale = 0.6
    }
}

// MARK: - Brief Player

struct BriefPlayerView: View {
    @Environment(WatchSessionManager.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Morning Brief")
                    .font(.headline)
                    .foregroundStyle(WatchColors.textPrimary)

                let text = session.briefText.isEmpty
                    ? "You slept 6h 10m. Three things today: standup at 9:30, lunch with Maya, dentist moved to Thursday."
                    : session.briefText

                Text(text)
                    .font(.caption)
                    .foregroundStyle(WatchColors.textSecondary)
                    .lineSpacing(3)
            }
            .padding()
        }
    }
}

// MARK: - Today's Plan

struct WatchPlanView: View {
    @State private var completed: Set<Int> = []

    private let actions = ["Morning stack", "30 min workout", "Team standup"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Today's Plan")
                    .font(.headline)
                    .foregroundStyle(WatchColors.textPrimary)

                ForEach(Array(actions.enumerated()), id: \.offset) { index, item in
                    Button {
                        if completed.contains(index) { completed.remove(index) }
                        else { completed.insert(index) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: completed.contains(index) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(completed.contains(index) ? WatchColors.success : WatchColors.textMuted)
                            Text(item)
                                .font(.caption)
                                .foregroundStyle(WatchColors.textPrimary)
                                .strikethrough(completed.contains(index))
                        }
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Button("Approve All") {
                        completed = Set(0..<actions.count)
                    }
                    .font(.caption2)
                    .tint(WatchColors.success)

                    Button("Skip") {}
                    .font(.caption2)
                    .tint(WatchColors.textMuted)
                }
                .padding(.top, 4)
            }
            .padding()
        }
    }
}

// MARK: - Inbox

struct WatchInboxView: View {
    private let items: [(icon: String, title: String, time: String)] = [
        ("envelope.fill", "Maya: lunch spot?", "2m"),
        ("calendar", "Standup moved to 10am", "18m"),
        ("bell.fill", "Ring sync complete", "1h"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Inbox")
                        .font(.headline)
                        .foregroundStyle(WatchColors.textPrimary)
                    Text("\(items.count)")
                        .font(.caption2.bold())
                        .foregroundStyle(WatchColors.background)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(WatchColors.textPrimary, in: Capsule())
                }

                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.caption)
                            .foregroundStyle(WatchColors.success)
                            .frame(width: 18)
                        Text(item.title)
                            .font(.caption)
                            .foregroundStyle(WatchColors.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(item.time)
                            .font(.caption2)
                            .foregroundStyle(WatchColors.textMuted)
                    }
                }

                Text("← swipe to act")
                    .font(.caption2)
                    .foregroundStyle(WatchColors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding()
        }
    }
}

// MARK: - Voice Log

struct WatchLogView: View {
    @State private var isRecording = false
    @State private var lastLog: String?

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Button {
                isRecording.toggle()
                if !isRecording { lastLog = "Logged at \(timeString)" }
            } label: {
                Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(isRecording ? WatchColors.alert : WatchColors.success)
            }
            .buttonStyle(.plain)

            Text(isRecording ? "Recording…" : "Tap to log")
                .font(.caption)
                .foregroundStyle(WatchColors.textSecondary)

            if let lastLog {
                Text(lastLog)
                    .font(.caption2)
                    .foregroundStyle(WatchColors.textMuted)
                    .transition(.opacity)
            }

            Spacer()
        }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: Date())
    }
}
