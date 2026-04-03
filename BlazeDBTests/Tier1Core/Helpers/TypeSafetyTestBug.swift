// Shared BlazeDocument fixture for type-safety tests (Tier1Fast + Tier1Extended via Helpers symlink).
import Foundation
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

struct TestBug: BlazeDocument {
    var id: UUID
    var title: String
    var priority: Int
    var status: String
    var assignee: String?
    var tags: [String]
    var createdAt: Date

    var isHighPriority: Bool {
        priority >= 7
    }

    var isOpen: Bool {
        status == "open"
    }

    func toStorage() throws -> BlazeDataRecord {
        var fields: [String: BlazeDocumentField] = [
            "id": .uuid(id),
            "title": .string(title),
            "priority": .int(priority),
            "status": .string(status),
            "tags": .array(tags.map { .string($0) }),
            "createdAt": .date(createdAt)
        ]

        if let assignee = assignee {
            fields["assignee"] = .string(assignee)
        }

        return BlazeDataRecord(fields)
    }

    init(from storage: BlazeDataRecord) throws {
        self.id = try storage.uuid("id")
        self.title = try storage.string("title")
        self.priority = try storage.int("priority")
        self.status = try storage.string("status")
        self.assignee = storage.stringOptional("assignee")

        let tagsArray = try storage.array("tags")
        self.tags = tagsArray.stringValues

        self.createdAt = try storage.date("createdAt")
    }

    init(
        id: UUID = UUID(),
        title: String,
        priority: Int,
        status: String,
        assignee: String? = nil,
        tags: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.priority = priority
        self.status = status
        self.assignee = assignee
        self.tags = tags
        self.createdAt = createdAt
    }
}
