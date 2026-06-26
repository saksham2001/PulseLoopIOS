import Foundation

/// muapi-backed media generation tools. `generate_image` (M-N1) submits a
/// text-to-image job, polls to completion, and returns a `media` object the model
/// copies verbatim into the final response's `media` array — same contract as
/// `prepare_chart` → `chart`. Gated by `flags.mediaGenerationEnabled`.
///
/// Sandbox mode (from `CoachSettings.muapiSandbox`) makes muapi return example media
/// for free, so first-run + tests never spend real credits.
@MainActor
enum MediaTools {
    static var all: [AnyCoachTool] { [generateImage, generateVideo, editImage] }

    // MARK: generate_image

    private struct ImageArgs: Decodable {
        let prompt: String
        let model: String?
        let aspectRatio: String?
        enum CodingKeys: String, CodingKey {
            case prompt, model
            case aspectRatio = "aspect_ratio"
        }
    }

    struct MediaToolOutput: Encodable {
        let media: CoachMedia
        let note: String
    }

    private static var generateImage: AnyCoachTool {
        .make(
            name: "generate_image",
            label: "Generating an image",
            description: "Generate an image from a text prompt via muapi.ai. Returns a `media` object to copy verbatim into the final response's `media` array. Use a vivid, specific prompt. Defaults to Nano Banana (Gemini Flash Image) for fast, hyper-real results; pick nano-banana-2 / nano-banana-pro for 4K or complex text, or flux-schnell for the cheapest draft.",
            parameters: JSONSchema.object([
                "prompt": JSONSchema.string,
                "model": JSONSchema.enumString(MuapiCatalog.image.map(\.name)),
                "aspect_ratio": JSONSchema.enumString(["1:1", "16:9", "9:16", "4:3", "3:4"]),
            ], required: ["prompt", "model", "aspect_ratio"]),
            argsType: ImageArgs.self
        ) { args, ctx in
            let model = args.model ?? MuapiCatalog.defaultModel(for: .image)
            var params: [String: Any] = ["prompt": args.prompt]
            if let ar = args.aspectRatio { params["aspect_ratio"] = ar }
            return await runGeneration(kind: .image, model: model, prompt: args.prompt, params: params, flags: ctx.flags)
        }
    }

    // MARK: generate_video

    private struct VideoArgs: Decodable {
        let prompt: String
        let model: String?
        let imageURL: String?
        enum CodingKeys: String, CodingKey {
            case prompt, model
            case imageURL = "image_url"
        }
    }

    private static var generateVideo: AnyCoachTool {
        .make(
            name: "generate_video",
            label: "Generating a video",
            description: "Generate a short video from a text prompt (and optionally a starting image URL) via muapi.ai. Defaults to OpenAI Sora 2 (cinematic, with synced audio). Video is expensive and slow (can take minutes); only use when the user explicitly asks for a video. Returns a `media` object to copy into the response's `media` array.",
            parameters: JSONSchema.object([
                "prompt": JSONSchema.string,
                "model": JSONSchema.enumString(MuapiCatalog.video.map(\.name)),
                "image_url": JSONSchema.string,
            ], required: ["prompt", "model", "image_url"]),
            argsType: VideoArgs.self
        ) { args, ctx in
            let model = args.model ?? MuapiCatalog.defaultModel(for: .video)
            var params: [String: Any] = ["prompt": args.prompt]
            if let img = args.imageURL, !img.isEmpty { params["image_url"] = img }
            return await runGeneration(kind: .video, model: model, prompt: args.prompt, params: params, flags: ctx.flags)
        }
    }

    // MARK: edit_image

    private struct EditArgs: Decodable {
        let prompt: String
        let imageURL: String
        let model: String?
        enum CodingKeys: String, CodingKey {
            case prompt, model
            case imageURL = "image_url"
        }
    }

    private static var editImage: AnyCoachTool {
        .make(
            name: "edit_image",
            label: "Editing an image",
            description: "Edit an existing image (image-to-image) given a source image URL and an instruction, via muapi.ai. Returns a `media` object to copy into the response's `media` array.",
            parameters: JSONSchema.object([
                "prompt": JSONSchema.string,
                "image_url": JSONSchema.string,
                "model": JSONSchema.enumString(MuapiCatalog.edit.map(\.name)),
            ], required: ["prompt", "image_url", "model"]),
            argsType: EditArgs.self
        ) { args, ctx in
            let model = args.model ?? MuapiCatalog.defaultModel(for: .edit)
            let params: [String: Any] = ["prompt": args.prompt, "image_url": args.imageURL]
            return await runGeneration(kind: .edit, model: model, prompt: args.prompt, params: params, flags: ctx.flags)
        }
    }

    // MARK: Shared run

    private static func runGeneration(
        kind: CoachMediaKind,
        model: String,
        prompt: String,
        params: [String: Any],
        flags: CoachFeatureFlags
    ) async -> ToolResult {
        guard flags.mediaGenerationEnabled else {
            return .error("Media generation is off. Enable it and add a muapi key in Settings → AI Assistant.")
        }
        let verdict = MediaModerator.moderate(prompt: prompt)
        if case let .rejected(reasons) = verdict {
            return .error("Can't generate that: \(reasons.joined(separator: " "))")
        }
        let sandbox = flags.settings.muapiSandbox
        let timeout: TimeInterval = kind == .video ? 600 : 180
        let client = MuapiClient(sandbox: sandbox, pollTimeout: timeout)
        do {
            let result = try await client.generate(model: model, params: params)
            let media = CoachMedia(
                kind: kind,
                urls: result.outputs.map(\.absoluteString),
                prompt: prompt,
                model: model,
                sandbox: sandbox
            )
            // Meter credits for the real (non-sandbox) generation. Sandbox is free.
            if !sandbox {
                CreditsLedger.shared.meter(.mediaGeneration)
            }
            let note = sandbox
                ? "Sandbox example media (no spend). Copy this `media` object verbatim into the response's `media` array."
                : "Copy this `media` object verbatim into the response's `media` array."
            let finalNote: String
            if case let .flagged(reasons) = verdict {
                finalNote = note + " Note for the user: " + reasons.joined(separator: " ")
            } else {
                finalNote = note
            }
            return .encoding(MediaToolOutput(media: media, note: finalNote))
        } catch {
            return .error((error as? LocalizedError)?.errorDescription ?? "Media generation failed: \(error.localizedDescription)")
        }
    }
}
