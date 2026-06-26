import Foundation

/// Assembles the enabled tool set + OpenAI tool specs for a turn. Milestone A
/// exposes read-only tools (retrieval, charting, analysis); write/action and
/// live-measurement tools are layered in Milestone B behind `flags`.
@MainActor
struct ToolRegistry {
    let flags: CoachFeatureFlags
    private let tools: [String: AnyCoachTool]

    init(flags: CoachFeatureFlags) {
        self.flags = flags
        var all = RetrievalTools.all + ChartTools.all + DiagramTools.all + AnalysisTools.all
        all += TaskTools.readTools
        all += ProtocolTools.readTools
        all += DailyLifeTools.readTools
        all += NoteTools.readTools
        if flags.writeToolsEnabled {
            all += MemoryTools.all + ActionTools.writeTools
            all += TaskTools.writeTools
            all += ProtocolTools.writeTools
            all += DailyLifeTools.writeTools
            all += NoteTools.writeTools
        }
        if flags.liveMeasurementsEnabled {
            all += ActionTools.measurementTools
        }
        if flags.webSearchEnabled {
            all += SearchTools.all
        }
        if flags.subAppBuilderEnabled {
            all += SubAppBuilderTools.all
        }
        if flags.platformControlEnabled {
            all += PlatformControlTools.all
            all += SpecEntityTools.readTools
            if flags.writeToolsEnabled {
                all += SpecEntityTools.writeTools
            }
            // Platform control implies designing sub-apps to install them.
            if !flags.subAppBuilderEnabled {
                all += SubAppBuilderTools.all
            }
        }
        if flags.mediaGenerationEnabled {
            all += MediaTools.all
            all += ModelDelegationTools.all
        }
        // Tools contributed by registered sub-apps (none yet for built-ins; this is
        // the seam Phase B features use). Built-in/core tools win on name collisions.
        let core = Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var merged = core
        for tool in SubAppRegistry.shared.aiTools(flags: flags) where merged[tool.name] == nil {
            merged[tool.name] = tool
        }
        self.tools = merged
    }

    func tool(named name: String) -> AnyCoachTool? { tools[name] }

    var labels: [String: String] {
        Dictionary(uniqueKeysWithValues: tools.map { ($0.key, $0.value.publicLabel) })
    }

    /// Full `tools` array for a Responses API request (function specs). Live web
    /// search is the `search_web` *function* tool (provider-agnostic; added above
    /// when enabled) — not the hosted `web_search` tool, which only runs on the
    /// OpenAI Responses API and is stripped by the OpenRouter bridge, so on the
    /// shipping default (OpenRouter) it gave the model NO search at all.
    var toolSpecs: [[String: Any]] {
        var specs = tools.values.map(\.toolSpec)
        // Stable order helps caching and trace readability.
        specs.sort { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
        return specs
    }
}
