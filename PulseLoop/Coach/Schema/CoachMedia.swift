import Foundation

/// Media produced by the `generate_image` / `generate_video` / `edit_image` tools
/// and copied verbatim by the model into `CoachResponse.media`. Mirrors the
/// `CoachChart` contract (data embedded, no refetch on render).
struct CoachMedia: Codable, Equatable, Identifiable {
    var kind: CoachMediaKind
    /// Hosted URL(s) of the generated media on muapi's CDN.
    var urls: [String]
    /// The prompt that produced it (shown as a caption).
    var prompt: String
    /// Model slug used (e.g. `flux-schnell`).
    var model: String
    /// True when produced in sandbox mode (example media, no spend).
    var sandbox: Bool

    var id: String { (urls.first ?? prompt) + model }

    enum CodingKeys: String, CodingKey {
        case kind, urls, prompt, model, sandbox
    }

    init(
        kind: CoachMediaKind,
        urls: [String],
        prompt: String,
        model: String,
        sandbox: Bool = false
    ) {
        self.kind = kind
        self.urls = urls
        self.prompt = prompt
        self.model = model
        self.sandbox = sandbox
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(CoachMediaKind.self, forKey: .kind) ?? .image
        urls = try c.decodeIfPresent([String].self, forKey: .urls) ?? []
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        sandbox = try c.decodeIfPresent(Bool.self, forKey: .sandbox) ?? false
    }

    /// Resolved `URL`s, dropping any that don't parse.
    var resolvedURLs: [URL] { urls.compactMap { URL(string: $0) } }

    /// Whether the primary output should render as a video player.
    var isVideo: Bool { kind == .video }
}

/// Media modality. Reuses the same names as `MuapiMediaKind` on the wire but is a
/// distinct schema type so the Coach layer doesn't depend on the muapi client.
enum CoachMediaKind: String, Codable, Equatable {
    case image
    case edit
    case video
}
