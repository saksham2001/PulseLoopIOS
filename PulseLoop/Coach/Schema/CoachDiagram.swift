import Foundation

/// A text-defined diagram (mind map, flowchart, sequence, etc.) produced by the
/// `prepare_diagram` tool and copied verbatim by the model into
/// `CoachResponse.diagram`. Unlike media, this is rendered locally and for free —
/// the `source` is Mermaid markup or raw SVG, never an image URL.
///
/// Mirrors the `CoachChart` contract: the payload is self-contained so the view
/// never has to refetch anything to render.
struct CoachDiagram: Codable, Equatable {
    var kind: CoachDiagramKind
    var title: String
    /// Diagram source. For `.mermaid` this is Mermaid markup (e.g. `graph TD; A-->B`).
    /// For `.svg` this is a complete `<svg>…</svg>` document.
    var source: String

    enum CodingKeys: String, CodingKey {
        case kind, title, source
    }

    init(kind: CoachDiagramKind, title: String, source: String) {
        self.kind = kind
        self.title = title
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(CoachDiagramKind.self, forKey: .kind) ?? .mermaid
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
    }

    /// Trimmed source with no surrounding whitespace, used by the renderer.
    var trimmedSource: String { source.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isEmpty: Bool { trimmedSource.isEmpty }
}

/// Diagram source format. `mermaid` covers flowcharts, mind maps, sequence, and
/// class diagrams via mermaid.js; `svg` renders an arbitrary vector document.
enum CoachDiagramKind: String, Codable, Equatable {
    case mermaid
    case svg
}
