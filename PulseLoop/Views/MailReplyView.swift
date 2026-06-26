import SwiftUI
import SwiftData

struct MailReplyView: View {
    let itemId: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isRecording = false
    @State private var styleMode: StyleMode = .yours
    @State private var draftText = ""
    @State private var showDraft = false
    @State private var isEditing = false
    @State private var isSent = false
    @State private var inboxItem: InboxItem?
    @State private var isGenerating = false

    enum StyleMode: String, CaseIterable, CustomStringConvertible {
        case yours = "Your style"
        case ai = "AI style"
        var description: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                emailHeader
                emailBody
                Divider().foregroundStyle(PulseColors.borderHairline)
                if isSent {
                    sentConfirmation
                } else {
                    replySection
                    if showDraft { draftSection }
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(PulseColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Reply")
        .onAppear { loadItem() }
    }

    private var emailHeader: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(PulseColors.fillSubtle)
                .frame(width: 36, height: 36)
                .overlay {
                    Text(String((inboxItem?.title.first(where: { $0.isLetter }) ?? "M").uppercased()))
                        .font(PulseFont.bodySemibold(14))
                        .foregroundStyle(PulseColors.textSecondary)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(senderName)
                    .font(PulseFont.bodySemibold(15))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("\(inboxItem?.source.rawValue.capitalized ?? "Gmail") · to me")
                    .font(PulseFont.body(12))
                    .foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
        }
    }

    private var emailBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(inboxItem?.title ?? "Message")
                .font(PulseFont.bodySemibold(16))
                .foregroundStyle(PulseColors.textPrimary)
            Text(inboxItem?.subtitle ?? "")
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textSecondary)
                .lineSpacing(4)
        }
    }

    private var replySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("REPLY BY VOICE")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            HStack {
                PillToggle(selection: $styleMode, options: StyleMode.allCases)
                Spacer()
            }

            Button {
                isRecording.toggle()
                if !isRecording { generateDraft() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.system(size: 18))
                    Text(isRecording ? "Stop recording" : "Tap and just talk")
                        .font(PulseFont.bodyMedium(15))
                }
                .foregroundStyle(isRecording ? .white : PulseColors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(isRecording ? PulseColors.accent : PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text("e.g. \"tell her I'll review it tonight and send notes by 9\"")
                .font(PulseFont.body(12))
                .foregroundStyle(PulseColors.textFaint)
                .italic()

            Button { generateDraft() } label: {
                Text("Or tap to generate a draft reply →")
                    .font(PulseFont.bodyMedium(13))
                    .foregroundStyle(PulseColors.textSecondary)
            }
        }
    }

    private var draftSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(PulseColors.textMuted)
                Text("AI DRAFT")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.6)
            }

            if isEditing {
                TextEditor(text: $draftText)
                    .font(PulseFont.body(14))
                    .foregroundStyle(PulseColors.textPrimary)
                    .frame(minHeight: 100)
                    .padding(10)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(PulseColors.accent.opacity(0.4), lineWidth: 1)
                    }
            } else {
                Text(draftText)
                    .font(PulseFont.body(14))
                    .foregroundStyle(PulseColors.textPrimary)
                    .lineSpacing(4)
                    .padding(14)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 12) {
                Button { sendReply() } label: {
                    Text("Send reply")
                        .font(PulseFont.bodySemibold(14))
                        .foregroundStyle(.white)
                        .frame(width: 140, height: 44)
                        .background(PulseColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Button { isEditing.toggle() } label: {
                    Text(isEditing ? "Done" : "Edit")
                        .font(PulseFont.bodyMedium(14))
                        .foregroundStyle(PulseColors.textSecondary)
                }
            }
        }
    }

    private var sentConfirmation: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(PulseColors.success)
            Text("Reply sent!")
                .font(PulseFont.bodySemibold(17))
                .foregroundStyle(PulseColors.textPrimary)
            Text("Item marked as handled")
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var senderName: String {
        guard let title = inboxItem?.title else { return "Unknown" }
        if title.contains(":") {
            return String(title.split(separator: ":").first ?? "Unknown")
        }
        return "Sender"
    }

    private func loadItem() {
        let descriptor = FetchDescriptor<InboxItem>(predicate: #Predicate { $0.id == itemId })
        inboxItem = try? modelContext.fetch(descriptor).first
    }

    private func generateDraft() {
        isGenerating = true
        showDraft = true
        draftText = "Generating AI reply…"

        Task {
            let subject = inboxItem?.title ?? "Message"
            let body = inboxItem?.subtitle ?? ""
            let from = senderName

            if let aiReply = await AIService.shared.suggestReply(subject: subject, body: body, from: from) {
                draftText = aiReply
            } else {
                let name = senderName.components(separatedBy: " ").first ?? "there"
                draftText = "Hey \(name)! I'll carve out time tonight to go through this  -  will drop my notes by end of day. Talk tomorrow!"
            }
            isGenerating = false
        }
    }

    private func sendReply() {
        withAnimation {
            inboxItem?.isHandled = true
            try? modelContext.save()
            isSent = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }
}
