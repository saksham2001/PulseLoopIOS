import SwiftUI
import Observation

/// App-wide, lightweight error surfacing. The persistence safe-save helper and other
/// critical paths can call `ErrorPresenter.shared.present(...)` so a failure becomes a
/// brief, non-blocking toast instead of a silent loss. Rendered by the `.errorToast()`
/// modifier attached once at the app root.
@MainActor
@Observable
final class ErrorPresenter {
    static let shared = ErrorPresenter()

    private(set) var message: String?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// Show a transient error message. Auto-dismisses after a few seconds; a newer
    /// message replaces an older one.
    func present(_ message: String) {
        self.message = message
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        message = nil
    }
}

private struct ErrorToastModifier: ViewModifier {
    @State private var presenter = ErrorPresenter.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = presenter.message {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(PulseColors.alert)
                        .font(.system(size: 16, weight: .semibold))
                    Text(message)
                        .font(PulseFont.bodySmall)
                        .foregroundStyle(PulseColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button { presenter.dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(PulseColors.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Dismiss")
                }
                .padding(.leading, 14)
                .padding(.vertical, 6)
                .background(PulseColors.alertBackground, in: RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous)
                        .strokeBorder(PulseColors.borderHairline, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Error. \(message)")
            }
        }
        .animation(.snappy(duration: 0.25), value: presenter.message)
    }
}

extension View {
    /// Attach once at the app root to render transient errors from `ErrorPresenter`.
    func errorToast() -> some View {
        modifier(ErrorToastModifier())
    }
}
