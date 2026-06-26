import SwiftUI

struct PrivacyPermissionsView: View {
    @State private var gmailOn = true
    @State private var calendarOn = true
    @State private var messagesOn = false
    @State private var bankOn = false
    @State private var showDataSettings = false
    @State private var showActivityLog = false

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
        .sheet(isPresented: $showDataSettings) {
            NavigationStack {
                ScrollView { PrivacyDataSettingsSection().padding(16) }
                    .background(PulseColors.canvas)
                    .navigationTitle("Your data")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showDataSettings = false } } }
            }
        }
        .sheet(isPresented: $showActivityLog) {
            NavigationStack {
                PrivacyActivityLogView()
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showActivityLog = false } } }
            }
        }
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
                PermissionRow(icon: "envelope.fill", name: "Gmail", detail: "Receipts, bills, invites only", isOn: $gmailOn)
                PermissionRow(icon: "calendar", name: "Calendar", detail: "Events & invitations", isOn: $calendarOn)
                PermissionRow(icon: "message.fill", name: "Messages", detail: "Limited · codes & deliveries", isOn: $messagesOn)
                PermissionRow(icon: "building.columns.fill", name: "Bank", detail: "Read-only · subscriptions", isOn: $bankOn)
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
            Button { showActivityLog = true } label: {
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

            Button { showDataSettings = true } label: {
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
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PulseColors.textPrimary)
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

// MARK: - Activity Log

/// On-device privacy activity log. PulseLoop keeps data on-device and asks before
/// it acts, so this surface lists what the assistant is currently allowed to read
/// and do. Until a persisted action ledger ships, recent actions show an honest
/// empty state rather than a fabricated history.
struct PrivacyActivityLogView: View {
    private let allowed: [(String, String)] = [
        ("Read Gmail receipts & invites", "envelope.fill"),
        ("Read Calendar events", "calendar"),
        ("Draft replies (with approval)", "square.and.pencil"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Activity log")
                        .font(PulseFont.title(28))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text("Everything PulseLoop reads or does is on-device. Nothing leaves your phone without an explicit action.")
                        .font(PulseFont.body(14))
                        .foregroundStyle(PulseColors.textSecondary)
                        .lineSpacing(3)
                }

                EyebrowLabel("CURRENTLY ALLOWED")
                PulseCard {
                    VStack(spacing: 0) {
                        ForEach(Array(allowed.enumerated()), id: \.offset) { index, item in
                            IconTileRow(icon: item.1, title: item.0, showsChevron: false)
                            if index < allowed.count - 1 { IconTileRow.divider }
                        }
                    }
                }

                EyebrowLabel("RECENT ACTIONS")
                EmptyStateCard(
                    icon: "list.bullet.rectangle",
                    title: "No actions yet",
                    message: "When the assistant reads a source or takes an action on your behalf, it will appear here so you can review it."
                )
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(PulseColors.canvas)
        .navigationTitle("Activity log")
        .navigationBarTitleDisplayMode(.inline)
    }
}
