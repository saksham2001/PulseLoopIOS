import Foundation

/// One learning the model proposes during the daily knowledge-base pass. Decoded
/// from the strict Structured-Outputs response and turned into a `DailyLearning`.
struct LearningItem: Codable, Equatable {
    var title: String
    var detail: String
    /// Raw `LearningCategory` value; defaults to `.general` if unrecognised.
    var category: String
    var importance: Int

    var resolvedCategory: LearningCategory {
        LearningCategory(rawValue: category) ?? .general
    }
}

/// The full payload of the daily pass: zero or more learnings. The model is told
/// to return an empty array when the day's data is too thin to learn anything
/// new, so we never fabricate insights.
struct DailyLearningContent: Codable, Equatable {
    var learnings: [LearningItem]

    static func decode(fromJSON json: String?) -> DailyLearningContent? {
        guard let json else { return nil }
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let c = try? JSONDecoder().decode(DailyLearningContent.self, from: data) {
            return c
        }
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"), start < end,
              let data = String(trimmed[start...end]).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DailyLearningContent.self, from: data)
    }
}

/// Strict Structured-Outputs schema for the daily knowledge-base pass.
enum DailyLearningSchema {
    static let name = "daily_learnings"

    static var textFormat: [String: Any] {
        ["type": "json_schema", "name": name, "schema": jsonSchema, "strict": true]
    }

    static var jsonSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "learnings": [
                    "type": "array",
                    "maxItems": 4,
                    "items": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string", "maxLength": 70],
                            "detail": ["type": "string", "maxLength": 280],
                            "category": [
                                "type": "string",
                                "enum": LearningCategory.allCases.map(\.rawValue),
                            ],
                            "importance": ["type": "integer", "minimum": 1, "maximum": 5],
                        ],
                        "required": ["title", "detail", "category", "importance"],
                        "additionalProperties": false,
                    ],
                ],
            ],
            "required": ["learnings"],
            "additionalProperties": false,
        ]
    }
}
