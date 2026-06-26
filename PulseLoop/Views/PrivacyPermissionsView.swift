import SwiftUI

struct PrivacyPermissionsView: View {
    @State private var gmailOn = true
    @State private var calendarOn = true
    @State private var messagesOn = false
    @State private var bankOn = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                VStack(spacing: 20) {
                    sourcesSection
                    aiPermissionsSection
                    actionsSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
        }
        .background(PulseColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Privacy")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Privacy & permissions")
                .font(PulseFont.title(28))
                .foregroundStyle(PulseColors.textPrimary)
            Text("Everything runs on-device. PulseLoop only reads what you allow, and asks before it acts.")
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textSecondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SOURCES IT CAN READ")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            VStack(spacing: 8) {
                PermissionRow(icon: "✉︎", name: "Gmail", detail: "Receipts, bills, invites only", isOn: $gmailOn)
                PermissionRow(icon: "📅", name: "Calendar", detail: "Events & invitations", isOn: $calendarOn)
                PermissionRow(icon: "💬", name: "Messages", detail: "Limited · codes & deliveries", isOn: $messagesOn)
                PermissionRow(icon: "🏦", name: "Bank", detail: "Read-only · subscriptions", isOn: $bankOn)
            }
        }
    }

    private var aiPermissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT AI MAY DO")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            VStack(spacing: 8) {
                AIPermissionRow(action: "Draft replies", permission: "Allowed", style: .success)
                AIPermissionRow(action: "Send & reschedule", permission: "Ask each time", style: .warning)
                AIPermissionRow(action: "Pay bills", permission: "Ask each time", style: .warning)
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 0) {
            Button { } label: {
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 14))
                        .foregroundStyle(PulseColors.textMuted)
                    Text("View activity log")
                        .font(PulseFont.bodyMedium(14))
                        .foregroundStyle(PulseColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PulseColors.textFaint)
                }
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(PulseColors.borderHairline).frame(height: 1)
                }
            }
            .buttonStyle(.plain)

            Button { } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(PulseColors.alert)
                    Text("Export / delete all data")
                        .font(PulseFont.bodyMedium(14))
                        .foregroundStyle(PulseColors.alert)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PulseColors.textFaint)
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let name: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.system(size: 14))
                .frame(width: 30, height: 30)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(PulseFont.bodyMedium(14)).foregroundStyle(PulseColors.textPrimary)
                Text(detail).font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(PulseColors.accent)
        }
        .padding(12)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }
}

struct AIPermissionRow: View {
    let action: String
    let permission: String
    let style: ChipStyle

    var body: some View {
        HStack {
            Text(action)
                .font(PulseFont.bodyMedium(14))
                .foregroundStyle(PulseColors.textPrimary)
            Spacer()
            StatusChip(label: permission, style: style)
        }
        .padding(14)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }
}
