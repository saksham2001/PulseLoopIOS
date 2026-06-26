import SwiftUI
import WebKit

/// Renders one `CoachDiagram` (Mermaid markup or raw SVG) as a card in the
/// assistant bubble — mirrors `CoachChartView`/`CoachMediaCardView`. Rendering is
/// local and free: Mermaid is drawn by a bundled mermaid.js in a sandboxed
/// `WKWebView`; SVG is dropped into a minimal HTML shell. The web view reports its
/// content height back so the card sizes to fit.
struct CoachDiagramView: View {
    let diagram: CoachDiagram
    @State private var contentHeight: CGFloat = 120
    @State private var didFail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !diagram.title.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 11))
                        .foregroundStyle(PulseColors.textMuted)
                    Text(diagram.title)
                        .font(PulseFont.bodySemibold(13))
                        .foregroundStyle(PulseColors.textPrimary)
                }
            }

            if diagram.isEmpty || didFail {
                failureState
            } else {
                DiagramWebView(diagram: diagram, contentHeight: $contentHeight, didFail: $didFail)
                    .frame(height: contentHeight)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#0F141F"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(diagram.title.isEmpty ? "Diagram" : "Diagram: \(diagram.title)")
    }

    private var failureState: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 22))
                .foregroundStyle(PulseColors.textMuted)
            Text("Couldn't render diagram")
                .font(.system(size: 11))
                .foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
    }
}

/// `WKWebView` wrapper that renders Mermaid markup or raw SVG on a transparent
/// dark background and posts its rendered height back to SwiftUI.
private struct DiagramWebView: UIViewRepresentable {
    let diagram: CoachDiagram
    @Binding var contentHeight: CGFloat
    @Binding var didFail: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight, didFail: $didFail)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "sizing")
        userContent.add(context.coordinator, name: "failure")
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(Self.html(for: diagram), baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastSource != diagram.source {
            context.coordinator.lastSource = diagram.source
            webView.loadHTMLString(Self.html(for: diagram), baseURL: nil)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "sizing")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "failure")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var contentHeight: CGFloat
        @Binding var didFail: Bool
        var lastSource: String = ""

        init(contentHeight: Binding<CGFloat>, didFail: Binding<Bool>) {
            _contentHeight = contentHeight
            _didFail = didFail
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "sizing":
                if let number = message.body as? NSNumber {
                    let clamped = max(60, min(CGFloat(number.doubleValue), 600))
                    DispatchQueue.main.async { self.contentHeight = clamped }
                }
            case "failure":
                DispatchQueue.main.async { self.didFail = true }
            default:
                break
            }
        }
    }

    /// Builds a self-contained HTML document. The diagram source is JSON-encoded so
    /// arbitrary markup can't break out of the string or inject markup.
    static func html(for diagram: CoachDiagram) -> String {
        let encodedSource = jsonString(diagram.source)
        let body: String
        switch diagram.kind {
        case .mermaid:
            body = """
            <pre class="mermaid" id="d"></pre>
            <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
            <script>
              const src = \(encodedSource);
              try {
                document.getElementById('d').textContent = src;
                mermaid.initialize({ startOnLoad: false, theme: 'dark', securityLevel: 'strict' });
                mermaid.run().then(reportSize).catch(() => fail());
              } catch (e) { fail(); }
            </script>
            """
        case .svg:
            body = """
            <div id="d"></div>
            <script>
              const src = \(encodedSource);
              try {
                document.getElementById('d').innerHTML = src;
                reportSize();
              } catch (e) { fail(); }
            </script>
            """
        }

        return """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
          html, body { margin: 0; padding: 0; background: transparent; }
          body { color: #E6EAF2; font-family: -apple-system, sans-serif; overflow: hidden; }
          #d { width: 100%; }
          #d svg { max-width: 100%; height: auto; display: block; margin: 0 auto; }
        </style>
        </head>
        <body>
        \(body)
        <script>
          function reportSize() {
            requestAnimationFrame(function() {
              const h = document.body.scrollHeight || document.getElementById('d').scrollHeight || 120;
              window.webkit.messageHandlers.sizing.postMessage(h);
            });
          }
          function fail() { window.webkit.messageHandlers.failure.postMessage(true); }
          // Fallback timeout: if mermaid never loads (e.g. offline), report failure.
          setTimeout(function() {
            if (!document.querySelector('#d svg')) {
              if (window.webkit && window.webkit.messageHandlers.failure) { fail(); }
            }
          }, 6000);
        </script>
        </body>
        </html>
        """
    }

    /// JSON-encodes a string (with surrounding quotes) for safe JS embedding.
    private static func jsonString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return json
    }
}
