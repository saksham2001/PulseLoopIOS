import Foundation

/// Structured coach reply, ported from the web app's `CoachResponseBody`
/// (`backend/app/schemas/coach.py`). The model is constrained to emit exactly
/// this shape via OpenAI Structured Outputs (see `CoachResponseSchema`).
///
/// Keys are snake_case on the wire (matching the web contract); explicit
/// `CodingKeys` keep that mapping self-contained rather than relying on a global
/// decoder strategy.
struct CoachResponse: Codable, Equatable {
    var responseType: CoachResponseType
    var title: String
    var summary: String
    var bullets: [String]
    var chart: CoachChart?
    var safetyNote: String?
    var dataQualityNote: String?
    var sources: [CoachSource]
    var followUpChips: [String]
    var actionsTaken: [String]
    var confidence: CoachConfidence
    /// Forward-compatible structured cards. Not part of the v1 strict schema, so
    /// the model does not emit these yet; decoded leniently when present.
    var cards: [CoachCard]
    /// Generated media (images/video) from the muapi tools. Copied verbatim by the
    /// model from a `generate_*` tool result. Lenient like `cards`.
    var media: [CoachMedia]
    /// A text-defined diagram (Mermaid/SVG) from the `prepare_diagram` tool, copied
    /// verbatim by the model. Optional and rendered locally; nil when absent.
    var diagram: CoachDiagram?
    /// Inline travel result cards (flights/stays/activities/restaurants) from the
    /// `prepare_travel_cards` tool, copied verbatim by the model. Lenient, rendered
    /// in chat and savable to a trip ("one shape, two surfaces").
    var travelCards: [CoachTravelCard]
    /// An optional proposed day-by-day itinerary outline accompanying travel cards.
    var itinerary: [CoachItineraryDay]

    enum CodingKeys: String, CodingKey {
        case responseType = "response_type"
        case title
        case summary
        case bullets
        case chart
        case safetyNote = "safety_note"
        case dataQualityNote = "data_quality_note"
        case sources
        case followUpChips = "follow_up_chips"
        case actionsTaken = "actions_taken"
        case confidence
        case cards
        case media
        case diagram
        case travelCards = "travel_cards"
        case itinerary
    }

    init(
        responseType: CoachResponseType,
        title: String,
        summary: String,
        bullets: [String] = [],
        chart: CoachChart? = nil,
        safetyNote: String? = nil,
        dataQualityNote: String? = nil,
        sources: [CoachSource] = [],
        followUpChips: [String] = [],
        actionsTaken: [String] = [],
        confidence: CoachConfidence = .medium,
        cards: [CoachCard] = [],
        media: [CoachMedia] = [],
        diagram: CoachDiagram? = nil,
        travelCards: [CoachTravelCard] = [],
        itinerary: [CoachItineraryDay] = []
    ) {
        self.responseType = responseType
        self.title = title
        self.summary = summary
        self.bullets = bullets
        self.chart = chart
        self.safetyNote = safetyNote
        self.dataQualityNote = dataQualityNote
        self.sources = sources
        self.followUpChips = followUpChips
        self.actionsTaken = actionsTaken
        self.confidence = confidence
        self.cards = cards
        self.media = media
        self.diagram = diagram
        self.travelCards = travelCards
        self.itinerary = itinerary
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        responseType = try c.decode(CoachResponseType.self, forKey: .responseType)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        bullets = try c.decodeIfPresent([String].self, forKey: .bullets) ?? []
        chart = try c.decodeIfPresent(CoachChart.self, forKey: .chart)
        safetyNote = try c.decodeIfPresent(String.self, forKey: .safetyNote)
        dataQualityNote = try c.decodeIfPresent(String.self, forKey: .dataQualityNote)
        sources = try c.decodeIfPresent([CoachSource].self, forKey: .sources) ?? []
        followUpChips = try c.decodeIfPresent([String].self, forKey: .followUpChips) ?? []
        actionsTaken = try c.decodeIfPresent([String].self, forKey: .actionsTaken) ?? []
        confidence = try c.decodeIfPresent(CoachConfidence.self, forKey: .confidence) ?? .medium
        cards = try c.decodeIfPresent([CoachCard].self, forKey: .cards) ?? []
        media = try c.decodeIfPresent([CoachMedia].self, forKey: .media) ?? []
        diagram = try c.decodeIfPresent(CoachDiagram.self, forKey: .diagram)
        travelCards = try c.decodeIfPresent([CoachTravelCard].self, forKey: .travelCards) ?? []
        itinerary = try c.decodeIfPresent([CoachItineraryDay].self, forKey: .itinerary) ?? []
    }

    // MARK: - Persistence helpers (CoachMessage.cardsJSON)

    /// Human-readable text stored in `CoachMessage.body` as a render-independent
    /// fallback (used if structured rendering ever fails to decode).
    var plainText: String {
        var parts = [summary]
        if !bullets.isEmpty { parts.append(bullets.map { "• \($0)" }.joined(separator: "\n")) }
        return parts.joined(separator: "\n\n")
    }

    func encodedJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(fromJSON json: String?) -> CoachResponse? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CoachResponse.self, from: data)
    }

    // MARK: - Adaptive shape guard (Experience loop M1)

    /// Defense-in-depth so the rendered shape matches the user's intent: a chart
    /// only belongs on a response the model explicitly committed to as
    /// chart-bearing (`insight_with_chart`). Any stray chart on a conversational
    /// reply (`insight`, `question`, casual/emotional answers, etc.) is dropped so
    /// we never surface, say, a heart-rate card for "I'm horny".
    ///
    /// The prompt is the primary lever (see `CoachPromptBuilder`); this keeps the
    /// invariant true even when the model misbehaves.
    func adaptiveShaped() -> CoachResponse {
        var copy = self.textSanitized()
        if copy.chart != nil, copy.responseType != .insightWithChart {
            copy.chart = nil
        }
        return copy
    }

    /// Strip em/en dashes from every user-visible text field. Models reach for the
    /// em dash constantly and ignore "don't use it" instructions, so we enforce it
    /// deterministically at the boundary: a spaced dash (" — ") becomes a comma,
    /// an unspaced one ("word—word") becomes a hyphen. Applied to all rendered
    /// strings (title, summary, bullets, notes, chips, actions, card/source text)
    /// so output reads clean and consistent.
    func textSanitized() -> CoachResponse {
        var copy = self
        copy.title = Self.deDash(title)
        copy.summary = Self.deDash(summary)
        copy.bullets = bullets.map(Self.deDash)
        copy.safetyNote = safetyNote.map(Self.deDash)
        copy.dataQualityNote = dataQualityNote.map(Self.deDash)
        copy.followUpChips = followUpChips.map(Self.deDash)
        copy.actionsTaken = actionsTaken.map(Self.deDash)
        copy.cards = cards.map { card in
            var c = card
            c.title = card.title.map(Self.deDash)
            c.body = card.body.map(Self.deDash)
            return c
        }
        return copy
    }

    /// Replace em/en dashes with reader-friendly punctuation. Spaced dashes →
    /// comma + space (clause break); tight dashes → hyphen (compound). Also
    /// normalizes the double-hyphen "--" some models emit as an em-dash stand-in.
    static func deDash(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var out = text
        // Spaced em/en dash (clause break) → comma + space.
        for sep in [" — ", " – ", "— ", " —", "– ", " –"] {
            out = out.replacingOccurrences(of: sep, with: ", ")
        }
        // Double-hyphen em-dash stand-in.
        out = out.replacingOccurrences(of: " -- ", with: ", ")
        out = out.replacingOccurrences(of: "--", with: "-")
        // Any remaining tight em/en dash → hyphen (compound words).
        out = out.replacingOccurrences(of: "—", with: "-")
        out = out.replacingOccurrences(of: "–", with: "-")
        // Tidy artifacts from substitution.
        out = out.replacingOccurrences(of: " ,", with: ",")
        out = out.replacingOccurrences(of: ", ,", with: ",")
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        return out
    }
}

enum CoachResponseType: String, Codable {
    case insight
    case insightWithChart = "insight_with_chart"
    case question
    case actionConfirmation = "action_confirmation"
    case dataMissing = "data_missing"
    case safetyGuidance = "safety_guidance"
    case errorRecovery = "error_recovery"

    /// Lenient decoding: models occasionally emit an off-spec `response_type`
    /// (e.g. "informative"). Treat any unrecognized value as a plain insight so a
    /// valid reply isn't discarded over an enum mismatch.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CoachResponseType(rawValue: raw) ?? .insight
    }
}

enum CoachConfidence: String, Codable {
    case low, medium, high
}

struct CoachSource: Codable, Equatable, Identifiable {
    var title: String
    var url: String
    var publisher: String
    var id: String { url + title }
}

/// Forward-compatible structured card (deferred past Milestone A). Kept minimal
/// and lenient so older/newer payloads never break decoding.
struct CoachCard: Codable, Equatable, Identifiable {
    var kind: String
    var title: String?
    var body: String?
    var id: String { kind + (title ?? "") + (body ?? "") }
}
