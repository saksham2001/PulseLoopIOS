import Foundation
import SwiftData
import XCTest
@testable import PulseLoop

/// Verifies the generic record sync (roadmap W3/W4) maps `TaskItem` rows to the
/// wire shape the web `/api/v1/sync/records` endpoint and `/tasks` page expect.
@MainActor
final class DataSyncProviderTests: XCTestCase {

    private func context() throws -> ModelContext {
        let schema = Schema([TaskItem.self, TaskBoard.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func testTasksProviderRecordType() {
        XCTAssertEqual(TasksSyncProvider().recordType, "task")
    }

    func testFetchDirtyMapsTaskFields() throws {
        let ctx = try context()
        let due = Date().addingTimeInterval(86_400)
        let item = TaskItem(title: "Write report", status: .inProgress, group: "Work", label: "urgent", dueDate: due, order: 2, weight: 4)
        ctx.insert(item)
        try ctx.save()

        let records = try TasksSyncProvider().fetchDirty(since: .distantPast, context: ctx)
        let rec = try XCTUnwrap(records.first { $0.clientId == item.id.uuidString })

        XCTAssertEqual(rec.type, "task")
        XCTAssertEqual(rec.payload["title"] as? String, "Write report")
        XCTAssertEqual(rec.payload["status"] as? String, "in_progress")
        XCTAssertEqual(rec.payload["group"] as? String, "Work")
        XCTAssertEqual(rec.payload["label"] as? String, "urgent")
        XCTAssertEqual(rec.payload["order"] as? Int, 2)
        XCTAssertEqual(rec.payload["weight"] as? Int, 4)
        XCTAssertNotNil(rec.payload["dueDate"] as? String)
        XCTAssertFalse(rec.deleted)
    }

    func testFetchDirtyOmitsNilOptionalFields() throws {
        let ctx = try context()
        let item = TaskItem(title: "Simple", group: "Inbox")
        ctx.insert(item)
        try ctx.save()

        let records = try TasksSyncProvider().fetchDirty(since: .distantPast, context: ctx)
        let rec = try XCTUnwrap(records.first)
        XCTAssertNil(rec.payload["label"], "No label set should be omitted from payload")
        XCTAssertNil(rec.payload["dueDate"], "No due date should be omitted from payload")
        XCTAssertNil(rec.payload["boardId"], "No board should be omitted from payload")
    }

    func testFetchDirtyRespectsSinceCursor() throws {
        let ctx = try context()
        let item = TaskItem(title: "Old", group: "Inbox")
        // Force an old updatedAt so the future cursor excludes it.
        item.updatedAt = Date(timeIntervalSince1970: 1_000)
        ctx.insert(item)
        try ctx.save()

        let future = Date().addingTimeInterval(86_400)
        let records = try TasksSyncProvider().fetchDirty(since: future, context: ctx)
        XCTAssertTrue(records.isEmpty, "Records older than the cursor must be excluded")
    }

    func testWireDictionaryRoundTripsThroughJSON() throws {
        let rec = SyncRecord(
            type: "task",
            clientId: "abc",
            payload: ["title": "Hi", "order": 1],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            deleted: false
        )
        let dict = rec.wireDictionary()
        // Must be JSON-serializable for the POST body.
        let data = try JSONSerialization.data(withJSONObject: ["records": [dict]])
        XCTAssertGreaterThan(data.count, 0)

        let parsed = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let records = try XCTUnwrap(parsed["records"] as? [[String: Any]])
        XCTAssertEqual(records.first?["clientId"] as? String, "abc")
        XCTAssertEqual(records.first?["type"] as? String, "task")
        XCTAssertEqual(records.first?["deleted"] as? Bool, false)
        XCTAssertNotNil(records.first?["updatedAt"] as? String)
    }

    // MARK: - Trip provider (web Travel parity)

    private func travelContext() throws -> ModelContext {
        let schema = Schema([Trip.self, TripItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func testTripProviderRecordType() {
        XCTAssertEqual(TripSyncProvider().recordType, "trip")
    }

    func testTripProviderMapsTripAndItems() throws {
        let ctx = try travelContext()
        let trip = Trip(destination: "Tokyo", originCity: "SFO",
                        startDate: Date().addingTimeInterval(7 * 86_400),
                        status: .planning, travelerCount: 2,
                        budgetAmount: 3000, budgetCurrency: "USD")
        ctx.insert(trip)
        let flight = TripItem(tripId: trip.id, kind: .flight, title: "SFO → HND",
                              price: 850, currency: "USD", dayOffset: 0, order: 0)
        let hotel = TripItem(tripId: trip.id, kind: .lodging, title: "Park Hyatt",
                             price: 400, currency: "USD", dayOffset: 0,
                             booked: true, rating: 4.7, order: 1)
        trip.items = [flight, hotel]
        ctx.insert(flight)
        ctx.insert(hotel)
        try ctx.save()

        let records = try TripSyncProvider().fetchDirty(since: .distantPast, context: ctx)
        let rec = try XCTUnwrap(records.first { $0.clientId == trip.id.uuidString })

        XCTAssertEqual(rec.type, "trip")
        XCTAssertEqual(rec.payload["title"] as? String, "Tokyo")
        XCTAssertEqual(rec.payload["status"] as? String, "planning")
        XCTAssertEqual(rec.payload["travelerCount"] as? Int, 2)
        XCTAssertEqual(rec.payload["itemCount"] as? Int, 2)
        XCTAssertEqual(rec.payload["currency"] as? String, "USD")
        XCTAssertEqual(rec.payload["estimatedCost"] as? Double, 1250)
        XCTAssertEqual(rec.payload["bookedCost"] as? Double, 400)
        XCTAssertEqual(rec.payload["originCity"] as? String, "SFO")

        let items = try XCTUnwrap(rec.payload["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?["kind"] as? String, "flight")
        XCTAssertEqual(items.first?["title"] as? String, "SFO → HND")
        XCTAssertEqual(items.last?["booked"] as? Bool, true)
        XCTAssertEqual(items.last?["rating"] as? Double, 4.7)

        // Whole payload must be JSON-serializable for the wire.
        let data = try JSONSerialization.data(withJSONObject: rec.wireDictionary())
        XCTAssertGreaterThan(data.count, 0)
    }
}
