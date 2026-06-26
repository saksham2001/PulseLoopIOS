import Foundation

/// `chat_with_model` (multifunction roadmap O2) — lets the Coach delegate a focused
/// sub-question to a *different* model (via muapi's text/LLM models) and fold the
/// answer back into its structured response. Useful for second opinions, specialized
/// reasoning, or comparing models. Gated by `flags.mediaGenerationEnabled` (needs a
/// muapi key) and honors sandbox mode.
@MainActor
enum ModelDelegationTools {
    static var all: [AnyCoachTool] { [chatWithModel] }

    private struct Args: Decodable {
        let model: String
        let question: String
    }

    struct Output: Encodable {
        let model: String
        let answer: String
        let note: String
    }

    private static var chatWithModel: AnyCoachTool {
        .make(
            name: "chat_with_model",
            label: "Asking another model",
            description: "Delegate a single focused question to a different LLM (e.g. for a second opinion or specialized reasoning) and get its answer back as text. Use sparingly — only when another model would genuinely add value. Summarize/attribute the answer in your final response; do not paste it verbatim without noting the source model.",
            parameters: JSONSchema.object([
                "model": JSONSchema.enumString(MuapiCatalog.text.map(\.name)),
                "question": JSONSchema.string,
            ], required: ["model", "question"]),
            argsType: Args.self
        ) { args, ctx in
            guard ctx.flags.mediaGenerationEnabled else {
                return .error("Multi-model chat needs a muapi key. Add one in Settings → AI Assistant.")
            }
            let sandbox = ctx.flags.settings.muapiSandbox
            let client = MuapiClient(sandbox: sandbox, pollTimeout: 120)
            do {
                let answer = try await client.generateText(model: args.model, prompt: args.question)
                if !sandbox { CreditsLedger.shared.meter(.coachTurn) }
                return .encoding(Output(
                    model: args.model,
                    answer: answer,
                    note: sandbox
                        ? "Sandbox response (example text, no spend). Attribute the source model when you use this."
                        : "Attribute the source model (\(args.model)) when you fold this into your answer."
                ))
            } catch {
                return .error((error as? LocalizedError)?.errorDescription ?? "Delegation failed: \(error.localizedDescription)")
            }
        }
    }
}
