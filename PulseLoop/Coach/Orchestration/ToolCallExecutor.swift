import Foundation

/// Runs one model-requested function call: looks it up, executes (the tool
/// validates its own args), and never throws  -  failures come back as an
/// `{"error": …}` `ToolResult` so a bad tool can't crash the turn.
@MainActor
enum ToolCallExecutor {
    static func execute(
        _ call: ResponseFunctionCall,
        registry: ToolRegistry,
        context: ToolExecutionContext
    ) async -> ToolResult {
        guard let tool = registry.tool(named: call.name) else {
            return .error("unknown tool '\(call.name)'")
        }
        let data = Data(call.arguments.utf8)
        do {
            return try await tool.run(data, context)
        } catch {
            return .error("tool '\(call.name)' failed: \(error.localizedDescription)")
        }
    }

    /// Compact, bounded arg string for the trace (drops verbose free-text).
    static func redactArgs(_ arguments: String) -> String {
        guard let data = arguments.data(using: .utf8),
              var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        for key in ["content", "notes", "reason", "python_code"] where obj[key] != nil {
            obj[key] = "…"
        }
        guard let out = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: out, encoding: .utf8) else { return "" }
        return String(str.prefix(500))
    }
}
