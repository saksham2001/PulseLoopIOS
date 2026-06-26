import SwiftUI

// MARK: - Install Catalog (formerly ModulePickerView)
//
// The unified install catalog: PulseLoop behaves like a personal app store where
// **no module comes standard**. This view lists every registered sub-app (built-in
// modules, spec-driven sub-apps, and — via the registry — installable ones), and
// the user installs exactly what they want. In onboarding nothing is pre-selected;
// in manage mode the current installed set is reflected. Selection operates on
// `SubAppID` so built-ins and spec sub-apps flow through one model.

struct ModulePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let isOnboarding: Bool
    var onComplete: (() -> Void)?

    @State private var selected: Set<SubAppID> = []
    @State private var query: String = ""
    @State private var detailAppID: SubAppID?
    @State private var refreshTick = 0

    init(isOnboarding: Bool = false, onComplete: (() -> Void)? = nil) {
        self.isOnboarding = isOnboarding
        self.onComplete = onComplete
        // Onboarding starts empty (nothing installed). Manage mode reflects what's
        // currently installed so the user can install/uninstall from one place.
        if !isOnboarding {
            _selected = State(initialValue: SubAppRegistry.shared.installedIDs)
        }
    }

    private var allSubApps: [any SubApp] {
        SubAppRegistry.shared.subApps
    }

    private func matches(_ app: any SubApp) -> Bool {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        let q = query.lowercased()
        return app.displayName.lowercased().contains(q) || app.summary.lowercased().contains(q)
    }

    /// Sub-apps grouped for display.
    ///
    /// - **Onboarding:** nothing is installed yet, so group by origin (Core modules
    ///   first, then Sub-apps) to help the user discover what's on offer.
    /// - **Manage mode:** group by install state — *Updates available* first (so a
    ///   pending update is impossible to miss), then *Installed*, then *Available* —
    ///   so the catalog reads like an app store the user actually maintains.
    private var groups: [(title: String, apps: [any SubApp])] {
        _ = refreshTick
        let filtered = allSubApps.filter(matches)
        if isOnboarding {
            let builtIns = filtered.filter { $0.origin == .builtIn && !($0 is SpecSubApp) }
            let others = filtered.filter { $0.origin != .builtIn || $0 is SpecSubApp }
            var result: [(String, [any SubApp])] = []
            if !builtIns.isEmpty { result.append(("Core modules", builtIns)) }
            if !others.isEmpty { result.append(("Sub-apps", others)) }
            return result
        }

        let registry = SubAppRegistry.shared
        let updatable = filtered.filter { registry.isInstalled($0.id) && registry.availableUpdate(for: $0.id) != nil }
        let updatableIDs = Set(updatable.map(\.id))
        let installed = filtered.filter { registry.isInstalled($0.id) && !updatableIDs.contains($0.id) }
        let available = filtered.filter { !registry.isInstalled($0.id) }
        var result: [(String, [any SubApp])] = []
        if !updatable.isEmpty { result.append(("Updates available", updatable)) }
        if !installed.isEmpty { result.append(("Installed", installed)) }
        if !available.isEmpty { result.append(("Available", available)) }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            searchField

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.title)
                                .font(PulseFont.bodySemibold(13))
                                .foregroundStyle(PulseColors.textMuted)
                                .textCase(.uppercase)
                                .padding(.horizontal, 20)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(group.apps, id: \.id) { app in
                                    moduleCard(app)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 120)
            }

            confirmButton
        }
        .background(PulseColors.background)
        .onReceive(NotificationCenter.default.publisher(for: .installedModulesChanged)) { _ in
            // Keep both the staged selection and the section grouping in sync when an
            // install changes from elsewhere (e.g. the detail sheet's Install button).
            if !isOnboarding { selected = SubAppRegistry.shared.installedIDs }
            refreshTick += 1
        }
        .sheet(item: $detailAppID) { id in
            if let app = SubAppRegistry.shared.subApp(id: id) {
                NavigationStack {
                    ModuleDetailView(app: app)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { detailAppID = nil }
                            }
                        }
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isOnboarding {
                Text("Build your PulseLoop")
                    .font(PulseFont.title(28))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("Nothing comes pre-installed. Install the modules you want — add or remove more anytime.")
                    .font(PulseFont.body(15))
                    .foregroundStyle(PulseColors.textSecondary)
                    .lineSpacing(3)
            } else {
                Text("Modules")
                    .font(PulseFont.title(28))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("Install or remove modules. Changes take effect immediately.")
                    .font(PulseFont.body(15))
                    .foregroundStyle(PulseColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PulseColors.textMuted)
            TextField("Search modules", text: $query)
                .font(PulseFont.body(15))
                .foregroundStyle(PulseColors.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(PulseColors.textMuted)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(PulseColors.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    /// A per-sub-app accent. Built-in modules borrow their `AppModule.color`; spec /
    /// installed sub-apps fall back to the app accent.
    private func accent(for app: any SubApp) -> Color {
        if let module = AppModule(rawValue: app.id.rawValue) {
            return module.color
        }
        return PulseColors.accent
    }

    private func moduleCard(_ app: any SubApp) -> some View {
        let isSelected = selected.contains(app.id)
        let tint = accent(for: app)
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if isSelected { selected.remove(app.id) } else { selected.insert(app.id) }
            }
            if !isOnboarding {
                // Manage mode applies immediately so the section grouping (Installed /
                // Available / Updates) reflects reality live, app-store style.
                if isSelected {
                    SubAppRegistry.shared.uninstall(app.id)
                } else {
                    SubAppRegistry.shared.install(app.id)
                }
                SubAppRegistry.shared.registerAllRoutes()
                NotificationCenter.default.post(name: .installedModulesChanged, object: nil)
                refreshTick += 1
            }
            HapticService.impact(.light)
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? tint.opacity(0.12) : PulseColors.fillSubtle)
                        .frame(width: 44, height: 44)
                    Image(systemName: app.iconSystemName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isSelected ? tint : PulseColors.textMuted)
                }
                VStack(spacing: 3) {
                    Text(app.displayName)
                        .font(PulseFont.bodySemibold(14))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text(app.summary)
                        .font(PulseFont.body(11))
                        .foregroundStyle(PulseColors.textMuted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                Text(isSelected ? "Installed" : "Install")
                    .font(PulseFont.bodySemibold(11))
                    .foregroundStyle(isSelected ? tint : PulseColors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(isSelected ? tint.opacity(0.12) : PulseColors.fillSubtle)
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(isSelected ? tint.opacity(0.04) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.5) : PulseColors.borderHairline, lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button {
                detailAppID = app.id
                HapticService.impact(.light)
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(PulseColors.textMuted)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(app.displayName) details")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(app.displayName). \(app.summary)")
        .accessibilityValue(isSelected ? "Installed" : "Not installed")
        .accessibilityHint(isSelected ? "Double tap to uninstall" : "Double tap to install")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var confirmButton: some View {
        VStack(spacing: 0) {
            Rectangle().fill(PulseColors.borderHairline).frame(height: 1)
            Button {
                if isOnboarding {
                    SubAppRegistry.shared.setInitialInstalled(selected)
                    SubAppRegistry.shared.registerAllRoutes()
                    NotificationCenter.default.post(name: .installedModulesChanged, object: nil)
                }
                // Manage mode already applied each change immediately; just close.
                HapticService.success()
                onComplete?()
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Text(isOnboarding ? "Get Started" : "Done")
                        .font(PulseFont.bodySemibold(16))
                    if isOnboarding {
                        Text("(\(selected.count) installed)")
                            .font(PulseFont.body(14))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(selected.isEmpty ? PulseColors.fillMuted : PulseColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(selected.isEmpty && isOnboarding)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(PulseColors.background)
    }
}
