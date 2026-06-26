import Foundation

/// `prepare_diagram` — turns a textual description into a renderable diagram
/// (Mermaid markup or raw SVG). Rendering is local and free, so there is no
/// feature flag, no API key, and no credit metering. The model authors the
/// Mermaid/SVG source itself and passes it here; the tool validates and echoes a
/// `diagram` object to copy verbatim into the final response's `diagram` field.
@MainActor
enum DiagramTools {
    static var all: [AnyCoachTool] { [prepareDiagram] }

    private struct Args: Decodable {
        let kind: String
        let title: String
        let source: String
    }

    struct PreparedDiagram: Encodable {
        let diagram: CoachDiagram
        let note: String
    }

    private static var prepareDiagram: AnyCoachTool {
        .make(
            name: "prepare_diagram",
            label: "Drawing a diagram",
            description: """
            Render a diagram from text you author. Use this for flowcharts, mind maps, \
            sequence diagrams, decision trees, org/relationship maps, timelines, and \
            "how X works" explainers — anything structural rather than numeric. For \
            numeric time-series use prepare_chart instead. \
            Provide `kind` = "mermaid" with valid Mermaid markup (e.g. "graph TD; A[Start] --> B{Choice}; B -->|Yes| C; B -->|No| D"), \
            or `kind` = "svg" with a complete <svg>…</svg> document for fully custom drawings. \
            Prefer Mermaid for most diagrams; it's more reliable. Keep node labels short. \
            Returns a `diagram` object to copy verbatim into the final response's `diagram` field, \
            and set response_type to "insight".
            """,
            parameters: JSONSchema.object([
                "kind": JSONSchema.enumString(["mermaid", "svg"]),
                "title": JSONSchema.string,
                "source": JSONSchema.string,
            ], required: ["kind", "title", "source"]),
            argsType: Args.self
        ) { args, _ in
            guard let kind = CoachDiagramKind(rawValue: args.kind) else {
                return .error("unknown diagram kind '\(args.kind)'. Use 'mermaid' or 'svg'.")
            }
            let source = args.source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else {
                return .error("diagram source is empty — provide Mermaid markup or an <svg> document.")
            }
            if kind == .svg, !source.lowercased().contains("<svg") {
                return .error("svg source must contain an <svg> element. For non-SVG, use kind 'mermaid'.")
            }

            let diagram = CoachDiagram(kind: kind, title: args.title, source: source)
            return .encoding(PreparedDiagram(
                diagram: diagram,
                note: "Copy this diagram object verbatim into the final response's `diagram` field. Do not alter the source."
            ))
        }
    }
}
