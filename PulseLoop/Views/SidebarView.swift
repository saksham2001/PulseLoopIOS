import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var path: NavigationPath
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<InboxItem> { !$0.isHandled }) private var inboxItems: [InboxItem]
    @AppStorage("sidebarNavCounts") private var navCountsData: Data = Data()

    private var unreadCount: Int { inboxItems.count }
    private var userName: String { profiles.first?.name ?? "My Brain" }

    private var navCounts: [String: Int] {
        (try? JSONDecoder().decode([String: Int].self, from: navCountsData)) ?? [:]
    }

    private func trackNav(_ key: String) {
        var counts = navCounts
        counts[key, default: 0] += 1
        navCountsData = (try? JSONEncoder().encode(counts)) ?? Data()
    }

    private struct NavItem: Identifiable {
        let id: String
        let icon: String
        let label: String
        let route: AppRoute?
        var trailing: TrailingType = .none
    }

    private var sortedCollections: [NavItem] {
        let modules = ModuleManager.shared
        var items: [NavItem] = []
        if modules.isEnabled(.notes) {
            items.append(NavItem(id: "notes", icon: "doc.text", label: "Notes", route: .notesList))
        }
        if modules.isEnabled(.tasks) {
            items.append(NavItem(id: "tasks", icon: "checklist", label: "Tasks", route: .tasksList))
        }
        if modules.isEnabled(.protocol_) {
            items.append(NavItem(id: "protocol", icon: "pills.fill", label: "Protocol", route: nil))
        }
        // Journal is a built-in extra sub-app (no AppModule); gate it by its SubAppID.
        if SubAppRegistry.shared.isInstalled(SubAppID("journal")) {
            items.append(NavItem(id: "journal", icon: "book.closed", label: "Journal", route: .journal))
        }
        if modules.isEnabled(.workouts) {
            items.append(NavItem(id: "fitness", icon: "dumbbell", label: "Fitness", route: .fitness))
        }
        let counts = navCounts
        return items.sorted { (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) }
    }

    private var insightsItems: [NavItem] {
        let items: [NavItem] = [
            NavItem(id: "knowledgeBase", icon: "sparkles", label: "AI Insights", route: .knowledgeBase),
            NavItem(id: "insights", icon: "chart.line.uptrend.xyaxis", label: "Insights", route: .insights),
        ]
        let counts = navCounts
        return items.sorted { (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) }
    }

    private var sortedSocial: [NavItem] {
        var items: [NavItem] = []
        if ModuleManager.shared.isEnabled(.accountability) {
            items.append(NavItem(id: "friends", icon: "flame.fill", label: "Accountability", route: .friends))
        }
        // Profile is core (always available).
        items.append(NavItem(id: "profile", icon: "person.crop.circle", label: "Profile", route: .profile))
        let counts = navCounts
        return items.sorted { (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                workspaceHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        sidebarRow("house", "Home", isActive: true) { dismiss() }
                        if ModuleManager.shared.isEnabled(.dayPlan) {
                            sidebarRow("checkmark.square", "Today's plan", trailing: .plus) { trackNav("dayplan"); navigate(.dayPlan) }
                        }
                        if ModuleManager.shared.isEnabled(.aiCapture) {
                            sidebarRow("tray", "AI Capture", trailing: .badge(unreadCount)) { trackNav("inbox"); navigate(.inbox) }
                        }

                        sectionLabel("COLLECTIONS")
                        ForEach(sortedCollections) { item in
                            sidebarRow(item.icon, item.label, trailing: item.trailing) {
                                trackNav(item.id)
                                if let route = item.route {
                                    navigate(route)
                                } else if item.id == "protocol" {
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        NotificationCenter.default.post(name: .switchTab, object: MainTab.tracker)
                                    }
                                } else {
                                    dismiss()
                                }
                            }
                        }

                        sectionLabel("INSIGHTS")
                        ForEach(insightsItems) { item in
                            sidebarRow(item.icon, item.label, trailing: item.trailing) {
                                trackNav(item.id)
                                if let route = item.route { navigate(route) } else { dismiss() }
                            }
                        }

                        sectionLabel("YOU")
                        ForEach(sortedSocial) { item in
                            sidebarRow(item.icon, item.label, trailing: item.trailing) {
                                trackNav(item.id)
                                if let route = item.route { navigate(route) } else { dismiss() }
                            }
                        }

                        sectionLabel("SETTINGS")
                        sidebarRow("square.grid.2x2", "Modules") { navigate(.modulePicker) }
                        sidebarRow("link", "Connect accounts") { navigate(.connectAccounts) }
                        sidebarRow("shield", "Privacy & permissions") { navigate(.privacyPermissions) }
                        sidebarRow("gearshape", "Settings") { navigate(.settings) }
                    }
                    .padding(.horizontal, 14)
                }
            }
            .background(PulseColors.background)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(PulseColors.textPrimary)
                .frame(width: 36, height: 36)
                .overlay {
                    Text(String(userName.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(userName)'s Brain")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("Personal workspace")
                    .font(.system(size: 12))
                    .foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12))
                .foregroundStyle(PulseColors.textMuted)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(PulseColors.textMuted)
            .tracking(0.5)
            .padding(.leading, 16)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }

    private enum TrailingType {
        case none, plus, badge(Int)
    }

    private func sidebarRow(_ icon: String, _ label: String, isActive: Bool = false, trailing: TrailingType = .none, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(PulseColors.textPrimary)
                    .frame(width: 22)
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                switch trailing {
                case .none: EmptyView()
                case .plus:
                    Image(systemName: "plus")
                        .font(.system(size: 13))
                        .foregroundStyle(PulseColors.textMuted)
                case .badge(let count):
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(PulseColors.textPrimary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(isActive ? PulseColors.fillSubtle : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func navigate(_ route: AppRoute) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            path.append(route)
        }
    }
}

struct SidebarNavItem: View {
    let icon: String
    let title: String
    var badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(PulseColors.textSecondary)
                    .frame(width: 22)
                Text(title)
                    .font(PulseFont.bodyMedium(14))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(PulseFont.bodySemibold(11))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(PulseColors.textPrimary)
                        .clipShape(Circle())
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ComfortRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .font(PulseFont.bodyMedium(14))
            .foregroundStyle(PulseColors.textPrimary)
            .tint(PulseColors.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }
}
