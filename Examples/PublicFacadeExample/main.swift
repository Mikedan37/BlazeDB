//
//  PublicFacadeExample
//
//  Canonical minimal usage of the document-style public API (`BlazeDB.open`, `put`, `get`, `query`).
//

import Foundation
import BlazeDB

private struct Bug: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var status: String
}

@main
struct PublicFacadeExampleMain {
    static func main() throws {
        let ns = String(describing: Bug.self).lowercased()
        let db = try BlazeDB.open(name: "PublicFacadeExample", password: "example-password-123")

        let bug = Bug(title: "Example bug", status: "open")
        try db.put(bug)

        let key = "\(ns):\(bug.id.uuidString)"
        let fetched: Bug? = try db.get(key)
        print("Fetched: \(fetched?.title ?? "nil")")

        let bugs: [Bug] = try db.query(ns)
            .where("status", equals: "open")
            .all()
        print("Open bugs: \(bugs.count)")
    }
}
