# BlazeDB Sync - Start Here

**Confused? Start here. This is the simple guide.**

---

## **What is Sync?**

Two databases automatically share data. Insert in one → appears in the other.

---

## **Quick Start (30 seconds):**

```swift
// 1. Create two databases
let db1 = try BlazeDBClient(name: "DB1", fileURL: url1, password: "pass")
let db2 = try BlazeDBClient(name: "DB2", fileURL: url2, password: "pass")

// 2. Connect them
let topology = BlazeTopology()
let id1 = try await topology.register(db: db1, name: "DB1", role:.server)
let id2 = try await topology.register(db: db2, name: "DB2", role:.client)
try await topology.connectLocal(from: id1, to: id2, mode:.bidirectional)

// 3. Insert data - it syncs automatically!
let id = try db1.insert(BlazeDataRecord(["message":.string("Hello!")]))

// 4. Wait a moment, then check db2
try await Task.sleep(nanoseconds: 500_000_000)
let synced = try db2.fetch(id: id)
print(" Synced: \(synced?.string("message")?? "not found")")
```

**That's it. Sync is automatic.**

---

## **More Details:**

- ** START HERE:** `SYNC_TRANSPORT_GUIDE.md` - **Clear examples for all 3 transport layers**
- **Simple Guide:** `SYNC_SIMPLE_GUIDE.md` - 3 steps, no confusion
- **Walkthrough:** `SYNC_WALKTHROUGH.md` - Step-by-step examples
- **Unix Domain Sockets:** `UNIX_DOMAIN_SOCKETS.md` - Cross-app sync details
- **Full Guide:** `CONNECTING_DATABASES_GUIDE.md` - Everything

---

## **What Works:**

 **Local Sync** - Same device (fast: <1ms)
 **Remote Sync** - Different devices (needs server: ~5ms)
 **Automatic** - No manual sync needed
 **Bidirectional** - Both databases can write

---

**Questions? Check the guides above. They're all simple and clear.**
