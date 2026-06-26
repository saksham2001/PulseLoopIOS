import SwiftUI

// MARK: - Credits / Paywall UI (roadmap E2)
//
// Shows the current AI-credit balance, recent usage from the ledger, and a paywall
// of consumable credit packs (StoreKit 2 via `CreditStore`). Reached from Settings
// and surfaced as a paywall when the balance can't cover an action (E2 enforcement).

struct CreditsView: View {
    @ObservedObject private var ledger = CreditsLedger.shared
    @State private var store = CreditStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                balanceCard
                packsSection
                if !ledger.entries.isEmpty {
                    historySection
                }
            }
            .padding(16)
        }
        .background(PulseColors.background)
        .navigationTitle("AI Credits")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadProducts() }
    }

    private var balanceCard: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Balance").font(PulseFont.bodyMedium(13)).foregroundStyle(PulseColors.textMuted)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(ledger.balance)")
                        .font(PulseFont.title(40)).foregroundStyle(PulseColors.textPrimary)
                    Text("credits").font(PulseFont.body(14)).foregroundStyle(PulseColors.textMuted)
                }
                Text("Credits power the AI assistant, summaries, and the Sub-App Builder.")
                    .font(PulseFont.body(12)).foregroundStyle(PulseColors.textFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var packsSection: some View {
        SectionHeader(title: "Top up", action: nil)
        if store.isLoading {
            PulseCard {
                HStack { ProgressView().controlSize(.small); Text("Loading packs…").font(PulseFont.body(13)).foregroundStyle(PulseColors.textMuted) }
            }
        } else if store.packs.isEmpty {
            PulseCard {
                InlineEmptyState(
                    title: "No packs available",
                    message: "Credit packs aren't configured on this build yet."
                )
            }
        } else {
            ForEach(store.packs) { pack in
                Button {
                    Task { await store.purchase(pack) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(pack.credits) credits").font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
                            Text(pack.title).font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
                        }
                        Spacer()
                        if store.purchaseInFlight == pack.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(pack.displayPrice)
                                .font(PulseFont.bodySemibold(14)).foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                    .padding(14)
                    .pulseCardSurface()
                }
                .buttonStyle(.plain)
                .disabled(store.purchaseInFlight != nil)
            }
        }
        if let error = store.lastError {
            Text(error).font(PulseFont.body(12)).foregroundStyle(PulseColors.heartRate)
        }
    }

    @ViewBuilder private var historySection: some View {
        SectionHeader(title: "Recent usage", action: nil)
        PulseCard {
            VStack(spacing: 10) {
                ForEach(ledger.entries.prefix(12)) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.kind.label).font(PulseFont.bodyMedium(13)).foregroundStyle(PulseColors.textPrimary)
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(PulseFont.body(11)).foregroundStyle(PulseColors.textFaint)
                        }
                        Spacer()
                        Text(entry.delta > 0 ? "+\(entry.delta)" : "\(entry.delta)")
                            .font(PulseFont.bodySemibold(14))
                            .foregroundStyle(entry.delta > 0 ? PulseColors.success : PulseColors.textMuted)
                    }
                }
            }
        }
    }
}
