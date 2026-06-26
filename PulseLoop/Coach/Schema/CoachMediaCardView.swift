import SwiftUI
import AVKit

/// Renders one `CoachMedia` (image / edited image / video) as a card in the
/// assistant bubble — mirrors `CoachChartView`'s role for charts. Images use
/// `AsyncImage`; video uses a `VideoPlayer`. A long-press menu offers share/save.
struct CoachMediaCardView: View {
    let media: CoachMedia

    private var primaryURL: URL? { media.resolvedURLs.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
                .frame(maxWidth: .infinity)
                .frame(height: media.isVideo ? 220 : 240)
                .background(PulseColors.cardSoft)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if media.sandbox { sandboxBadge }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityDescription)

            if !media.prompt.isEmpty {
                Text(media.prompt)
                    .font(.system(size: 11))
                    .foregroundStyle(PulseColors.textMuted)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                Image(systemName: kindIcon)
                    .font(.system(size: 9))
                Text(media.model)
                    .font(.system(size: 9, weight: .medium))
                if let url = primaryURL {
                    Spacer()
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 11))
                    }
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                    }
                }
            }
            .foregroundStyle(PulseColors.textMuted)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let url = primaryURL {
            if media.isVideo {
                VideoPlayer(player: AVPlayer(url: url))
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().aspectRatio(contentMode: .fit)
                    case .failure:
                        failureState
                    case .empty:
                        ProgressView().tint(PulseColors.accent)
                    @unknown default:
                        failureState
                    }
                }
            }
        } else {
            failureState
        }
    }

    private var failureState: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 22))
                .foregroundStyle(PulseColors.textMuted)
            Text("Media unavailable")
                .font(.system(size: 11))
                .foregroundStyle(PulseColors.textMuted)
        }
    }

    private var sandboxBadge: some View {
        Text("SANDBOX")
            .font(.system(size: 8, weight: .bold)).tracking(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(PulseColors.accent.opacity(0.85), in: Capsule())
            .padding(8)
    }

    private var kindIcon: String {
        switch media.kind {
        case .image: return "photo"
        case .edit: return "wand.and.stars"
        case .video: return "video"
        }
    }

    private var accessibilityDescription: String {
        let noun: String
        switch media.kind {
        case .image: noun = "Generated image"
        case .edit: noun = "Edited image"
        case .video: noun = "Generated video"
        }
        let sandboxSuffix = media.sandbox ? ", sandbox example" : ""
        let promptPart = media.prompt.isEmpty ? "" : " of \(media.prompt)"
        return "\(noun)\(promptPart), by \(media.model)\(sandboxSuffix)"
    }
}
