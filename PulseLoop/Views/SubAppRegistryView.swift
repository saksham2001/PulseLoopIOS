import SwiftUI

// MARK: - Sub-App Registry browser (roadmap F2)
//
// Browse, search, rate, and install shared sub-apps. Installing runs the same
// trusted path as a file import (F1): the registry serves a signed package, which is
// signature-verified, strictly validated, guardrail-reviewed, and shown in a
// permission-review sheet before it's added. Ratings are stored locally for now
// (server-backed with E3/F3).

struct SubAppRegistryView: View {
    private let service: SubAppRegistryService = HTTPModuleGalleryProvider()
    @ObservedObject private var store = SubAppRegistryStore.shared

    @State private var query = ""
    @State private var listings: [RegistryListing] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var pendingInstall: RegistryListing?
    @State private var banner: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                searchField

                if let banner {
                    Text(banner).font(PulseFont.body(13)).foregroundStyle(PulseColors.success)
                }
                if let loadError {
                    Text(loadError).font(PulseFont.body(13)).foregroundStyle(PulseColors.heartRate)
                }

                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if listings.isEmpty {
                    PulseCard {
                        InlineEmptyState(title: "Nothing found", message: "Try a different search.")
                    }
                } else {
                    ForEach(listings) { listing in
                        listingRow(listing)
                    }
                }
            }
            .padding(16)
        }
        .background(PulseColors.background)
        .navigationTitle("Sub-App Store")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .sheet(item: $pendingInstall) { listing in
            RegistryInstallSheet(
                listing: listing,
                onInstall: { install(listing) },
                onCancel: { pendingInstall = nil }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Discover sub-apps")
                .font(PulseFont.title(22)).foregroundStyle(PulseColors.textPrimary)
            Text("Install community-built trackers. Every sub-app is signed, verified, and permission-reviewed before it runs.")
                .font(PulseFont.body(14)).foregroundStyle(PulseColors.textMuted)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(PulseColors.textMuted)
            TextField("Search sub-apps", text: $query)
                .font(PulseFont.body(15))
                .autocorrectionDisabled()
                .onSubmit { Task { await reload() } }
            if !query.isEmpty {
                Button { query = ""; Task { await reload() } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(PulseColors.textFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .pulseCardSurface()
    }

    private func listingRow(_ listing: RegistryListing) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: listing.spec.icon).foregroundStyle(PulseColors.textPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(listing.spec.displayName)
                            .font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
                        Text("\(listing.category) · by \(listing.spec.author)")
                            .font(PulseFont.body(11)).foregroundStyle(PulseColors.textFaint)
                    }
                    Spacer()
                }
                Text(listing.spec.summary)
                    .font(PulseFont.body(13)).foregroundStyle(PulseColors.textMuted)

                HStack(spacing: 6) {
                    StarRow(rating: listing.communityRating)
                    Text(String(format: "%.1f", listing.communityRating))
                        .font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
                    Text("(\(listing.communityRatingCount))")
                        .font(PulseFont.body(11)).foregroundStyle(PulseColors.textFaint)
                    Spacer()
                }

                if store.isInstalled(listing.id) {
                    if store.updateAvailable(for: listing) {
                        Button { pendingInstall = listing } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Update to v\(listing.spec.version.description)")
                            }
                            .font(PulseFont.bodySemibold(14)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    HStack(spacing: 10) {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .font(PulseFont.bodySemibold(13)).foregroundStyle(PulseColors.success)
                        Spacer()
                        myRatingControl(listing)
                    }
                } else {
                    Button { pendingInstall = listing } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Get")
                        }
                        .font(PulseFont.bodySemibold(14)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func myRatingControl(_ listing: RegistryListing) -> some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    store.rate(listing.id, stars: star)
                } label: {
                    Image(systemName: (store.rating(for: listing.id) ?? 0) >= star ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundStyle(PulseColors.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rate \(star) star\(star == 1 ? "" : "s")")
            }
        }
    }

    // MARK: Actions

    private func reload() async {
        loading = true
        loadError = nil
        do {
            listings = try await query.isEmpty ? service.featured() : service.search(query)
        } catch {
            loadError = "Couldn't load the store: \(error.localizedDescription)"
            listings = []
        }
        loading = false
    }

    private func install(_ listing: RegistryListing) {
        pendingInstall = nil
        banner = nil
        do {
            // Re-verify from the package bytes — never trust the in-memory listing.
            let data = try encode(listing.package)
            let spec = try SubAppPackager.importSpec(from: data)
            // Moderation gate (F3): reject disallowed content even if it passed the
            // builder guardrails when authored.
            let verdict = SubAppModerator.moderate(spec)
            guard verdict.isInstallable else {
                loadError = "Can't install: " + verdict.reasons.joined(separator: " ")
                return
            }
            UserSubAppStore.shared.save(spec, origin: .installed)
            store.markInstalled(listing.id, version: spec.version)
            SubAppRegistry.shared.loadUserSpecs()
            // Surface the installed sub-app in the unified install model so it appears
            // everywhere (Home, catalog, Coach tools) — not just the registry ledger.
            SubAppRegistry.shared.install(SubAppID(spec.id))
            if case .flagged(let reasons) = verdict {
                banner = "Installed \"\(spec.displayName)\" — note: \(reasons.joined(separator: " "))"
            } else {
                banner = "Installed \"\(spec.displayName)\"."
            }
        } catch {
            loadError = "Can't install: \(error.localizedDescription)"
        }
    }

    private func encode(_ package: SubAppPackage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(package)
    }
}

/// Static star bar for a community rating (0...5, supports halves visually rounded).
private struct StarRow: View {
    let rating: Double
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: Double(star) <= rating.rounded() ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(PulseColors.accent)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(String(format: "%.1f", rating)) out of 5")
    }
}

/// Permission-review + confirmation sheet before installing from the registry.
private struct RegistryInstallSheet: View {
    let listing: RegistryListing
    let onInstall: () -> Void
    let onCancel: () -> Void

    private var spec: SubAppSpec { listing.spec }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Install \"\(spec.displayName)\"")
                    .font(PulseFont.title(20)).foregroundStyle(PulseColors.textPrimary)
                Text("by \(spec.author) · \(listing.category)")
                    .font(PulseFont.body(14)).foregroundStyle(PulseColors.textMuted)
            }

            PulseCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(spec.summary)
                        .font(PulseFont.body(13)).foregroundStyle(PulseColors.textPrimary)
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

            Button(action: onInstall) {
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
