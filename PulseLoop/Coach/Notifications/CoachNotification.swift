import Foundation

/// A generated daily check-in: a push-notification title + body.
struct CoachNotification: Codable, Equatable {
    var title: String
    var body: String

    func encodedJSON() -> String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func decode(fromJSON json: String?) -> CoachNotification? {
        guard let json else { return nil }
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8), let n = try? JSONDecoder().decode(CoachNotification.self, from: data) {
            return n
        }
        // Tolerate prose/fences around the object.
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end,
              let data = String(trimmed[start...end]).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CoachNotification.self, from: data)
    }
}

/// Strict Structured-Outputs schema for `coach_notification` (mirrors `CoachResponseSchema`).
enum CoachNotificationSchema {
    static let name = "coach_notification"

    static var textFormat: [String: Any] {
        ["type": "json_schema", "name": name, "schema": jsonSchema, "strict": true]
    }

    static var jsonSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "title": ["type": "string", "maxLength": 50],
                "body": ["type": "string", "maxLength": 160],
            ],
            "required": ["title", "body"],
            "additionalProperties": false,
        ]
    }
}
