# Canonical Facade Example

This is the default BlazeDB onboarding path.

If you are new, start here and ignore advanced APIs until needed.

```swift
import BlazeDB

struct Bug: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var status: String
}

let db = try BlazeDB.open(name: "demo", password: "DemoPass123!")
let bug = Bug(title: "Crash on launch", status: "open")

try db.put(bug)

let loaded: Bug? = try db.get("bug:\(bug.id.uuidString)")
let openBugs: [Bug] = try db.query("bug")
    .where("status", equals: "open")
    .all()
```

Default mental model: `open -> put -> get -> query(namespace)`.
