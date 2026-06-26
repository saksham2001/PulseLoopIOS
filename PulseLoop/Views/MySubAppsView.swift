import SwiftUI
import UniformTypeIdentifiers

// MARK: - My Sub-Apps (roadmap F1)
//
// Lists the user's saved (`.userCreated`) sub-apps and lets them **export** a signed
// `SubAppPackage` (share sheet / file) or **import** one someone shared. Sharing moves
// the declarative spec only — never executable code — and every import is signature-
// verified + strictly validated + guard-railed before it's installed.

struct MySubAppsView: View {
    @ObservedObject private var store = UserSubAppStore.shared
    @Binding var path: NavigationPath

    @State private var exportItem: ExportItem?
    @State private var showingImporter = false
    @State private var importError: String?
    @State private var importedConfirmation: String?
    @State private var pendingImport: SubAppSpec?

    init(path: Binding<NavigationPath>) {
        self._path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let importError {
                    notice(importError, color: PulseColors.heartRate)
                }
                if let importedConfirmation {
                    notice(importedConfirmation, color: PulseColors.success)
                }

                importButton

                buildFromScratchButton

                if store.specs.isEmpty {
                    PulseCard {
                        InlineEmptyState(
                            title: "No sub-apps yet",
                            message: "Build one in the Sub-App Builder, or import a shared sub-app."
                        )
                    }
                } else {
                    ForEach(store.specs, id: \.id) { spec in
                        row(spec)
                    }
                }
            }
            .padding(16)
        }
        .background(PulseColors.background)
        .navigationTitle("My Sub-Apps")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.url])
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json, UTType(filenameExtension: "pulseapp") ?? .json],
            allowsMultipleSelection: false
        ) { handleImportResult($0) }
        .sheet(item: importBinding) { item in
            ImportReviewSheet(
                spec: item.spec,
                onConfirm: { confirmImport(item.spec) },
                onCancel: { pendingImport = nil }
            )
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your sub-apps")
                .font(PulseFont.title(22)).foregroundStyle(PulseColors.textPrimary)
            Text("Export a sub-app to share it, or import one someone sent you. Shared files are signed and verified before installing.")
                .font(PulseFont.body(14)).foregroundStyle(PulseColors.textMuted)
        }
    }

    private var importButton: some View {
        Button {
            importError = nil
            importedConfirmation = nil
            showingImporter = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                Text("Import a sub-app")
            }
            .font(PulseFont.bodySemibold(15))
            .foregroundStyle(PulseColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .pulseCardSurface(stroke: PulseColors.borderStrong)
        }
    }

    private var buildFromScratchButton: some View {
        Button {
            path.append(AppRoute.subAppEditor(nil))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                Text("Build from scratch")
            }
            .font(PulseFont.bodySemibold(15))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func row(_ spec: SubAppSpec) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: spec.icon).foregroundStyle(PulseColors.textPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(spec.displayName)
                            .font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
                        Text("v\(spec.version.description) · \(spec.entities.count) entity · \(spec.screens.count) screens")
                            .font(PulseFont.body(11)).foregroundStyle(PulseColors.textFaint)
                    }
                    Spacer()
                }
                if !spec.summary.isEmpty {
                    Text(spec.summary)
                        .font(PulseFont.body(13)).foregroundStyle(PulseColors.textMuted)
                }
                usageLine(spec)
                HStack(spacing: 10) {
                    Button { open(spec) } label: {
                        Label("Open", systemImage: "arrow.up.right.square")
                            .font(PulseFont.bodySemibold(13)).foregroundStyle(.white)
                            .padding(.vertical, 8).padding(.horizontal, 16)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    Button { path.append(AppRoute.subAppEditor(spec.id)) } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                            .font(PulseFont.bodySemibold(13)).foregroundStyle(PulseColors.textPrimary)
                            .padding(.vertical, 8).padding(.horizontal, 14)
                            .pulseCardSurface(stroke: PulseColors.borderStrong)
                    }
                    Menu {
                        Button { export(spec) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                        Button(role: .destructive) {
                            store.delete(id: spec.id)
                            SubAppRegistry.shared.uninstall(SubAppID(spec.id))
                            SubAppRegistry.shared.loadUserSpecs()
                        } label: { Label("Delete", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
                            .frame(width: 38, height: 34)
                            .pulseCardSurface(stroke: PulseColors.borderStrong)
                    }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func notice(_ text: String, color: Color) -> some View {
        Text(text).font(PulseFont.body(13)).foregroundStyle(color)
    }

    @ViewBuilder
    private func usageLine(_ spec: SubAppSpec) -> some View {
        let stat = SubAppAnalytics.shared.stat(for: spec.id)
        if stat.opens > 0 || stat.recordsCreated > 0 {
            HStack(spacing: 12) {
                Label("\(stat.opens)", systemImage: "eye")
                Label("\(stat.recordsCreated)", systemImage: "square.and.pencil")
                if let last = stat.lastUsed {
                    Text("· \(last.formatted(.relative(presentation: .named)))")
                }
            }
            .font(PulseFont.body(11)).foregroundStyle(PulseColors.textFaint)
            .accessibilityLabel("\(stat.opens) opens, \(stat.recordsCreated) records created")
        }
    }

    // MARK: Open

    /// Push the spec runtime onto the navigation stack so the user can actually
    /// use the sub-app they created. The `SpecSubAppRoute` destination is registered
    /// on the root nav stack by `SubAppRegistry.registerAllRoutes()`; make sure the
    /// spec is in the catalog + the route is installed before navigating.
    private func open(_ spec: SubAppSpec) {
        SpecSubAppCatalog.shared.register(spec)
        // Ensure it's installed (so the route resolves + the host doesn't show the
        // "not installed" prompt) before pushing.
        SubAppRegistry.shared.loadUserSpecs()
        SubAppRegistry.shared.install(SubAppID(spec.id))
        path.append(SpecSubAppRoute(specID: spec.id))
    }

    // MARK: Export

    private func export(_ spec: SubAppSpec) {
        importError = nil
        do {
            let data = try SubAppPackager.exportData(for: spec)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(spec.id).pulseapp")
            try data.write(to: url, options: .atomic)
            exportItem = ExportItem(url: url)
        } catch {
            importError = "Couldn't export: \(error.localizedDescription)"
        }
    }

    // MARK: Import

    private var importBinding: Binding<PendingImport?> {
        Binding(
            get: { pendingImport.map(PendingImport.init) },
            set: { if $0 == nil { pendingImport = nil } }
        )
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        importError = nil
        importedConfirmation = nil
        switch result {
        case .failure(let error):
            importError = "Import failed: \(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let spec = try SubAppPackager.importSpec(from: data)
                let verdict = SubAppModerator.moderate(spec)
                guard verdict.isInstallable else {
                    importError = "Can't import: " + verdict.reasons.joined(separator: " ")
                    return
                }
                pendingImport = spec
            } catch {
                importError = "Can't import: \(error.localizedDescription)"
            }
        }
    }

    private func confirmImport(_ spec: SubAppSpec) {
        pendingImport = nil
        // Imported specs come from elsewhere → tracked as `.installed` for attribution.
        UserSubAppStore.shared.save(spec, origin: .installed)
        SubAppRegistry.shared.loadUserSpecs()
        SubAppRegistry.shared.install(SubAppID(spec.id))
        importedConfirmation = "Installed \"\(spec.displayName)\"."
    }
}

private struct ExportItem: Identifiable {
    let url: URL
    var id: String { url.lastPathComponent }
}

private struct PendingImport: Identifiable {
    let spec: SubAppSpec
    var id: String { spec.id }
}

/// Confirmation sheet shown before an imported sub-app is installed, surfacing the
/// author + requested permissions so the user can make an informed choice.
private struct ImportReviewSheet: View {
    let spec: SubAppSpec
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Install sub-app")
                    .font(PulseFont.title(20)).foregroundStyle(PulseColors.textPrimary)
                Text("\"\(spec.displayName)\" by \(spec.author)")
                    .font(PulseFont.body(14)).foregroundStyle(PulseColors.textMuted)
            }

            PulseCard {
                VStack(alignment: .leading, spacing: 8) {
                    if !spec.summary.isEmpty {
                        Text(spec.summary)
                            .font(PulseFont.body(13)).foregroundStyle(PulseColors.textPrimary)
                    }
                    Text("\(spec.entities.count) entity · \(spec.screens.count) screens · v\(spec.version.description)")
                        .font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
                    if spec.permissions.isEmpty {
                        Text("Requests no special permissions.")
                            .font(PulseFont.body(12)).foregroundStyle(PulseColors.textFaint)
                    } else {
                        Text("Permissions:")
                            .font(PulseFont.bodySemibold(12)).foregroundStyle(PulseColors.textPrimary)
                        ForEach(spec.permissions.sorted { $0.rawValue < $1.rawValue }, id: \.self) { permission in
                            Text("• \(SubAppGuardrails.explain(permission))")
                                .font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            Button(action: onConfirm) {
                Text("Install")
                    .font(PulseFont.bodySemibold(15)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Button(action: onCancel) {
                Text("Cancel")
                    .font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .pulseCardSurface(stroke: PulseColors.borderStrong)
            }
        }
        .padding(20)
        .presentationDetents([.medium, .large])
    }
}
