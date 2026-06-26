import Foundation

/// Hand-written strict JSON Schema for the `coach_response` structured output,
/// ported verbatim from `backend/app/schemas/coach.py::COACH_RESPONSE_JSON_SCHEMA`.
/// Every property is required and `additionalProperties` is false everywhere  - 
/// the exact shape OpenAI Structured Outputs strict mode expects.
///
/// `cards` is intentionally NOT in this schema for Milestone A (read-only); the
/// Swift `CoachResponse` type tolerates it for forward compatibility.
enum CoachResponseSchema {
    static let name = "coach_response"

    /// The `text.format` object for a Responses API request.
    static var textFormat: [String: Any] {
        [
            "type": "json_schema",
            "name": name,
            "schema": jsonSchema,
            "strict": true,
        ]
    }

    static var jsonSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "response_type": [
                    "type": "string",
                    "enum": [
                        "insight", "insight_with_chart", "question",
                        "action_confirmation", "data_missing",
                        "safety_guidance", "error_recovery",
                    ],
                ],
                "title": ["type": "string", "maxLength": 90],
                "summary": ["type": "string", "maxLength": 900],
                "bullets": [
                    "type": "array",
                    "items": ["type": "string", "maxLength": 220],
                    "maxItems": 5,
                ],
                "chart": chartSchema,
                "safety_note": ["type": ["string", "null"], "maxLength": 350],
                "data_quality_note": ["type": ["string", "null"], "maxLength": 350],
                "sources": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string"],
                            "url": ["type": "string"],
                            "publisher": ["type": "string"],
                        ],
                        "required": ["title", "url", "publisher"],
                        "additionalProperties": false,
                    ],
                ],
                "follow_up_chips": [
                    "type": "array",
                    "items": ["type": "string", "maxLength": 60],
                    "maxItems": 4,
                ],
                "actions_taken": ["type": "array", "items": ["type": "string"]],
                "confidence": ["type": "string", "enum": ["low", "medium", "high"]],
                "media": mediaSchema,
                "diagram": diagramSchema,
                "travel_cards": travelCardsSchema,
                "itinerary": itinerarySchema,
            ],
            "required": [
                "response_type", "title", "summary", "bullets", "chart",
                "safety_note", "data_quality_note", "sources",
                "follow_up_chips", "actions_taken", "confidence", "media",
                "diagram", "travel_cards", "itinerary",
            ],
            "additionalProperties": false,
        ]
    }

    /// A text-defined diagram (Mermaid markup or raw SVG). Nullable like `chart`;
    /// the model copies a `prepare_diagram` tool result here verbatim, or null.
    private static var diagramSchema: [String: Any] {
        [
            "type": ["object", "null"],
            "properties": [
                "kind": ["type": "string", "enum": ["mermaid", "svg"]],
                "title": ["type": "string"],
                "source": ["type": "string"],
            ],
            "required": ["kind", "title", "source"],
            "additionalProperties": false,
        ]
    }

    /// Generated media array. The model copies `generate_*` tool results here
    /// verbatim. Empty array when no media this turn.
    private static var mediaSchema: [String: Any] {
        [
            "type": "array",
            "items": [
                "type": "object",
                "properties": [
                    "kind": ["type": "string", "enum": ["image", "edit", "video"]],
                    "urls": ["type": "array", "items": ["type": "string"]],
                    "prompt": ["type": "string"],
                    "model": ["type": "string"],
                    "sandbox": ["type": "boolean"],
                ],
                "required": ["kind", "urls", "prompt", "model", "sandbox"],
                "additionalProperties": false,
            ],
            "maxItems": 4,
        ]
    }

    /// Inline travel result cards. The model copies a `prepare_travel_cards` tool
    /// result here verbatim. Empty array when there are no travel results this turn.
    /// Nullable fields use `["type", "null"]` so the model can omit a value.
    private static var travelCardsSchema: [String: Any] {
        [
            "type": "array",
            "items": [
                "type": "object",
                "properties": [
                    "kind": ["type": "string", "enum": CoachTravelCardKind.allCases.map(\.rawValue)],
                    "title": ["type": "string"],
                    "subtitle": ["type": ["string", "null"]],
                    "price": ["type": ["number", "null"]],
                    "currency": ["type": ["string", "null"]],
                    "time": ["type": ["string", "null"]],
                    "location": ["type": ["string", "null"]],
                    "rating": ["type": ["number", "null"]],
                    "thumbnail_url": ["type": ["string", "null"]],
                    "booking_url": ["type": ["string", "null"]],
                    "latitude": ["type": ["number", "null"]],
                    "longitude": ["type": ["number", "null"]],
                ],
                "required": [
                    "kind", "title", "subtitle", "price", "currency", "time",
                    "location", "rating", "thumbnail_url", "booking_url",
                    "latitude", "longitude",
                ],
                "additionalProperties": false,
            ],
            "maxItems": 12,
        ]
    }

    /// An optional proposed day-by-day itinerary outline. Empty array when absent.
    private static var itinerarySchema: [String: Any] {
        [
            "type": "array",
            "items": [
                "type": "object",
                "properties": [
                    "day_offset": ["type": "integer"],
                    "label": ["type": ["string", "null"]],
                    "items": ["type": "array", "items": ["type": "string"]],
                ],
                "required": ["day_offset", "label", "items"],
                "additionalProperties": false,
            ],
            "maxItems": 14,
        ]
    }

    private static var chartSchema: [String: Any] {
        [
            "type": ["object", "null"],
            "properties": [
                "chart_type": [
                    "type": "string",
                    "enum": ["line", "bar", "dot", "sleep_stage", "sparkline"],
                ],
                "title": ["type": "string"],
                "metric": [
                    "type": "string",
                    "enum": ["steps", "hr", "spo2", "sleep", "active_minutes", "calories", "distance"],
                ],
                "range": [
                    "type": "object",
                    "properties": [
                        "start": ["type": "string"],
                        "end": ["type": "string"],
                    ],
                    "required": ["start", "end"],
                    "additionalProperties": false,
                ],
                "data": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "x": ["type": "string"],
                            "y": ["type": "number"],
                            "series": ["type": ["string", "null"]],
                        ],
                        "required": ["x", "y", "series"],
                        "additionalProperties": false,
                    ],
                ],
                "annotations": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "x": ["type": "string"],
                            "label": ["type": "string"],
                        ],
                        "required": ["x", "label"],
                        "additionalProperties": false,
                    ],
                ],
            ],
            "required": ["chart_type", "title", "metric", "range", "data", "annotations"],
            "additionalProperties": false,
        ]
    }
}
