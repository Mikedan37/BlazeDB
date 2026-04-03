# BlazeDB Distributed: Quick Start Guide

> **OSS core positioning:** Distributed transport and cross-app sync are **not part of the default open-source runtime** in the current release. The repo may contain implementation sketches or gated code paths, but **public SwiftPM `BlazeDB` is the embedded engine first**; sync integration is intentionally deferred until a supported transport story ships. Treat this guide as **design and API direction**, not a promise that every snippet compiles against the default OSS product today.

**Distributed sync — design preview (non-default, deferred for OSS core)**

---

## **QUICK START:**

### **1. Local Sync (Same Device, Different Apps):**

```swift
// BugTracker.app
let bugsDB = try BlazeDBClient(
 name: "Bugs",
 at: bugsURL,
 password: "pass"
)

// Enable cross-app sync
try await bugsDB.enableCrossAppSync(
 appGroup: "group.com.yourcompany.suite",
 exportPolicy: ExportPolicy(
 collections: ["bugs"],
 fields: ["id", "title", "status", "priority"],
 readOnly: true
 )
)

// Dashboard.app
let bugTrackerDB = try BlazeDBClient.connectToSharedDB(
 appGroup: "group.com.yourcompany.suite",
 database: "bugs.blazedb",
 mode:.readOnly
)

// Query bugs from BugTracker!
let bugs = try await bugTrackerDB.fetchAll()
// <1ms latency!
```

### **2. Remote Sync (Different Devices):**

```swift
// iPhone
let bugsDB = try BlazeDBClient(
 name: "Bugs",
 at: bugsURL,
 password: "pass"
)

// Enable sync with server
try await bugsDB.enableSync(
 remote: RemoteNode(
 host: "yourpi.duckdns.org",
 port: 8080,
 database: "bugs"
 ),
 policy: SyncPolicy(
 collections: ["bugs", "comments"],
 teams: [myTeamId],
 encryptionMode:.e2eOnly // Server blind!
 )
)

// Automatically syncs to server! E2E encrypted!
```

### **3. Local DB-to-DB (Same Device, Same App):**

```swift
let bugsDB = try BlazeDBClient(name: "Bugs", at: bugsURL, password: "pass")
let usersDB = try BlazeDBClient(name: "Users", at: usersURL, password: "pass")

let topology = BlazeTopology()

let bugsNode = try await topology.register(db: bugsDB, name: "bugs")
let usersNode = try await topology.register(db: usersDB, name: "users")

// Connect locally
try await topology.connectLocal(
 from: bugsNode,
 to: usersNode,
 mode:.bidirectional
)

// Now you can do cross-DB queries!
// <1ms latency!
```

---

## **What exists in the codebase (may be gated or non-default):**

These components are part of the broader distributed design; availability in a given build depends on target and packaging—not on the default OSS `BlazeDB` surface:

**BlazeTopology** — Multi-DB coordinator (when enabled)
**InMemoryRelay** — Local relay paths (when enabled)
**SecureConnection** — Handshake + E2E paths (when enabled)
**WebSocketRelay** — Remote relay paths (when enabled)
**CrossAppSync** — App Groups–related flows (when enabled)

---

## **FEATURES (target / when sync is enabled—not the default OSS core checklist):**

 Local sync (Unix Domain Socket, <1ms)
 Remote sync (TCP + TLS, ~5ms)
 Diffie-Hellman handshake (P256)
 E2E encryption (AES-256-GCM)
 Perfect Forward Secrecy
 Cross-app sync (App Groups)
 Selective sync (RLS integrated)
 Operation log (crash-safe)
 Automatic reconnection

---

## **NEXT STEPS:**

1. Supported transport packaging for OSS consumers
2. Tests and integration examples aligned with the non-default sync surface
3. Documentation kept in sync with what the default package actually exports

---

**This guide is not a “ship checklist” for the core OSS build** — it tracks the distributed layer roadmap. For what you can rely on today, see `README.md` and `Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md`.

