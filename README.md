# BlazeDB

**Embedded database for Swift with ACID transactions, encryption, and schema-less storage.**

BlazeDB is a page-based embedded database I built for predictable performance and operational simplicity. It gives you ACID transaction guarantees, multi-version concurrency control, and per-page encryption using AES-256-GCM. Everything runs in-process with zero external dependencies.

---

## What This Is

BlazeDB implements a page-based storage engine with write-ahead logging, MVCC, and a custom binary encoding format I call BlazeBinary. I optimized it primarily for Apple platforms (macOS and iOS), though it runs on Linux too. The design targets local, encrypted storage use cases where you need something more capable than SQLite but don't want the complexity of a full database server.

**Current Version:** 2.5.0-alpha  
**Platform Support:** macOS 12+, iOS 15+, Linux  
**Language:** Swift 5.9+

---

## Design Goals

When I started building this, I had a few priorities that shaped the architecture:

1. **ACID Compliance:** Every operation is transactional. No exceptions. I needed full atomicity, consistency, isolation, and durability guarantees because I was tired of dealing with data corruption in other embedded databases.

2. **Encryption by Default:** All data gets encrypted at rest using AES-256-GCM with unique nonces per page. This wasn't optional—I wanted encryption to be the default, not an afterthought.

3. **Schema Flexibility:** Dynamic schemas that adapt to your data structure without migrations. I went with this because I kept hitting migration hell in other systems.

4. **Predictable Performance:** Consistent latency characteristics under varying workloads. Early testing showed that unpredictable spikes were killing user experience, so I focused heavily on this.

5. **Operational Simplicity:** Minimal configuration, zero external dependencies, straightforward deployment. I wanted something you could drop into a project and have working in minutes.

---

## What It's Not

BlazeDB isn't intended for every use case. Here's what it's not:

- **Not a distributed cluster database:** It's a single primary database with optional sync capabilities. I didn't implement distributed consensus, automatic sharding, or multi-master replication. That's a different problem space.

- **Not for petabyte-scale datasets:** I optimized for datasets that fit on a single device. If you're doing large-scale analytics, you'll want something else.

- **Platform optimization:** I primarily optimized for Apple platforms (macOS and iOS). Linux support exists, but performance characteristics may differ. I tested extensively on Apple Silicon, and that's where it shines.

- **Query planner limitations:** The query planner uses rule-based heuristics. I haven't built a cost-based optimizer yet—that's on the roadmap, but the current approach works well for most queries.

- **MVCC garbage collection:** Long-running read transactions can delay garbage collection of obsolete versions. This can increase storage requirements, but in practice it hasn't been an issue for typical workloads.

- **No automatic sharding:** If your dataset exceeds device storage capacity, you'll need to manually partition it. I kept this simple intentionally.

These limitations are intentional. By not trying to solve everything, I could optimize for the use cases that matter most.

---

## Stability & Maturity

**Current Status:** 2.5.0-alpha

The on-disk format is stable. Databases created with version 2.5.0 can be opened by future versions. I maintain forward compatibility through version markers and migration paths—I learned the hard way that breaking existing databases is a bad idea.

Public APIs may evolve during the alpha period. When I make breaking changes, I document them in release notes. Once we hit 1.0.0, semantic versioning will govern API compatibility.

**Compatibility Guarantees:**
- Forward upgrade path: You can upgrade databases to newer versions without data loss
- No forced deletion: Existing databases are never automatically deleted or modified without explicit user action
- Migration support: Format migrations are automatic and transparent—you won't notice them

---

## Architecture

The architecture is layered with clear separation of concerns. I found this structure made debugging much easier, especially when tracking down performance issues.

### System Architecture Layers

*Conceptual diagram showing component relationships*

```mermaid
graph TB
    subgraph AppLayer["Application Layer"]
        A1["BlazeDBClient<br/>Public API"]
        A2["BlazeShell<br/>CLI Tool"]
        A3["BlazeStudio<br/>GUI Tool"]
        A4["SwiftUI Integration<br/>@BlazeQuery"]
    end
    
    subgraph QueryLayer["Query & Index Layer"]
        Q1["QueryBuilder<br/>Fluent DSL"]
        Q2["QueryOptimizer<br/>Index Selection"]
        Q3["QueryPlanner<br/>Execution Plan"]
        I1["Secondary Indexes"]
        I2["Full-Text Search"]
        I3["Spatial Index"]
        I4["Vector Index"]
    end
    
    subgraph MVCCLayer["MVCC & Concurrency Layer"]
        M1["VersionManager<br/>Multi-Version Storage"]
        M2["MVCCTransaction<br/>Snapshot Isolation"]
        M3["ConflictResolution<br/>Lost Update Prevention"]
        M4["PageGarbageCollector<br/>Version Cleanup"]
    end
    
    subgraph StorageLayer["Storage Layer"]
        S1["PageStore<br/>4KB Pages"]
        S2["WriteAheadLog<br/>WAL for Durability"]
        S3["StorageLayout<br/>Metadata Management"]
        S4["Overflow Pages<br/>Large Records"]
    end
    
    subgraph EncryptLayer["Encryption Layer"]
        E1["AES-256-GCM<br/>Per-Page Encryption"]
        E2["KeyManager<br/>Argon2id + HKDF"]
        E3["Secure Enclave<br/>iOS/macOS"]
    end
    
    subgraph NetworkLayer["Network Layer"]
        N1["In-Memory Queue<br/>&lt;0.1ms"]
        N2["Unix Domain Socket<br/>~0.5ms"]
        N3["TCP Relay<br/>~5ms"]
        N4["BlazeBinary Protocol<br/>53% smaller"]
    end
    
    A1 --> Q1
    A2 --> Q1
    A3 --> Q1
    A4 --> Q1
    
    Q1 --> Q2
    Q2 --> Q3
    Q3 --> I1
    Q3 --> I2
    Q3 --> I3
    Q3 --> I4
    
    Q3 --> M1
    M1 --> M2
    M2 --> M3
    M3 --> M4
    
    M2 --> S1
    M2 --> S2
    S1 --> S3
    S1 --> S4
    
    S1 --> E1
    E1 --> E2
    E2 --> E3
    
    A1 --> N1
    A1 --> N2
    A1 --> N3
    N3 --> N4
    
    classDef appLayer fill:#3498db,stroke:#2980b9,stroke-width:3px,color:#fff
    classDef queryLayer fill:#2ecc71,stroke:#27ae60,stroke-width:3px,color:#fff
    classDef mvccLayer fill:#e74c3c,stroke:#c0392b,stroke-width:3px,color:#fff
    classDef storageLayer fill:#f39c12,stroke:#e67e22,stroke-width:3px,color:#fff
    classDef cryptoLayer fill:#9b59b6,stroke:#8e44ad,stroke-width:3px,color:#fff
    classDef networkLayer fill:#1abc9c,stroke:#16a085,stroke-width:3px,color:#fff
    
    class A1,A2,A3,A4 appLayer
    class Q1,Q2,Q3,I1,I2,I3,I4 queryLayer
    class M1,M2,M3,M4 mvccLayer
    class S1,S2,S3,S4 storageLayer
    class E1,E2,E3 cryptoLayer
    class N1,N2,N3,N4 networkLayer
```

---

## Storage Engine

I went with a page-based storage architecture using 4KB pages. This size works well with modern SSDs and gives good cache locality. Records that exceed page capacity use overflow chains—I initially tried variable-length pages, but the complexity wasn't worth it.

### Page Structure

*Conceptual diagram of page layout*

```mermaid
graph LR
    subgraph PageStruct["Page Structure (4KB)"]
        P1["Header<br/>Magic + Version<br/>8 bytes"]
        P2["BlazeBinary Data<br/>Variable Length"]
        P3["Overflow Pointer<br/>4 bytes if needed"]
        P4["Padding<br/>Zero-filled"]
    end
    
    subgraph FileLayout["File Layout"]
        F1[".blazedb<br/>Data Pages"]
        F2[".meta<br/>Index Map"]
        F3[".wal<br/>Write-Ahead Log"]
    end
    
    subgraph PageAlloc["Page Allocation"]
        PA1["Main Page<br/>Record Start"]
        PA2["Overflow Page 1<br/>Continuation"]
        PA3["Overflow Page 2<br/>Continuation"]
    end
    
    P1 --> P2
    P2 --> P3
    P3 --> P4
    
    P2 --> F1
    F1 --> F2
    F1 --> F3
    
    PA1 -->|"Overflow Chain"| PA2
    PA2 -->|"Overflow Chain"| PA3
    
    classDef header fill:#3498db,stroke:#2980b9,stroke-width:2px,color:#fff
    classDef data fill:#2ecc71,stroke:#27ae60,stroke-width:2px,color:#fff
    classDef file fill:#e74c3c,stroke:#c0392b,stroke-width:2px,color:#fff
    classDef meta fill:#f39c12,stroke:#e67e22,stroke-width:2px,color:#fff
    classDef wal fill:#9b59b6,stroke:#8e44ad,stroke-width:2px,color:#fff
    classDef page fill:#1abc9c,stroke:#16a085,stroke-width:2px,color:#fff
    
    class P1 header
    class P2 data
    class F1 file
    class F2 meta
    class F3 wal
    class PA1,PA2,PA3 page
```

**File Organization:**
- `.blazedb`: Data pages containing encrypted records
- `.meta`: Index map and metadata (I keep this separate so corruption in one doesn't kill the other)
- `.wal`: Write-ahead log for crash recovery

**Page Allocation:**
- Main page stores the record start
- Overflow pages linked via 4-byte pointers (I tried 8-byte pointers but 4 bytes is enough and saves space)
- Pages allocated sequentially with reuse via garbage collection

### BlazeBinary Protocol

I built a custom binary encoding format called BlazeBinary because JSON was too slow and too large for my use case. After benchmarking against CBOR and MessagePack, I found I could do better with a format tailored to Swift's type system. The result is about 53% smaller than JSON and roughly 48% faster to encode/decode.

#### Protocol Overview

*Conceptual diagram of encoding pipeline*

```mermaid
graph LR
    subgraph Input["Input Data"]
        D1["Swift Dictionary<br/>String: Any"]
        D2["Codable Struct"]
    end
    
    subgraph Encoder["BlazeBinary Encoder"]
        E1["Field Name<br/>Compression<br/>Top 127 = 1 byte"]
        E2["Type Tag<br/>1 byte"]
        E3["Value Encoding<br/>Variable Length"]
        E4["Bit Packing<br/>Optimization"]
    end
    
    subgraph Output["Output"]
        O1["Binary Data<br/>53% smaller<br/>than JSON"]
        O2["CRC32 Checksum<br/>Integrity Check"]
    end
    
    subgraph Network["Network Sync"]
        N1["Optional LZ4<br/>Compression"]
        N2["Encrypted<br/>AES-256-GCM"]
    end
    
    D1 --> E1
    D2 --> E1
    E1 --> E2
    E2 --> E3
    E3 --> E4
    E4 --> O1
    O1 --> O2
    O2 --> N1
    N1 --> N2
    
    classDef input fill:#3498db,stroke:#2980b9,stroke-width:2px,color:#fff
    classDef encoder fill:#2ecc71,stroke:#27ae60,stroke-width:2px,color:#fff
    classDef output fill:#e74c3c,stroke:#c0392b,stroke-width:2px,color:#fff
    classDef network fill:#9b59b6,stroke:#8e44ad,stroke-width:2px,color:#fff
    
    class D1,D2 input
    class E1,E2,E3,E4 encoder
    class O1,O2 output
    class N1,N2 network
```

#### Record Format Structure

BlazeBinary records use a fixed 8-byte header followed by variable-length fields. I aligned the header to 8 bytes because it makes direct CPU reads faster—this hits the hot path, so every cycle counts.

```
┌─────────────────────────────────────────────────────────────┐
│ HEADER (8 bytes, aligned)                                    │
├─────────────────────────────────────────────────────────────┤
│ Offset  Size  Type     Description                           │
│ 0       5     char[5]  Magic: "BLAZE" (0x42 0x4C 0x41...)   │
│ 5       1     uint8    Version: 0x01 (v1) or 0x02 (v2)     │
│ 6       2     uint16   Field count (big-endian)             │
├─────────────────────────────────────────────────────────────┤
│ FIELD_1 (variable length)                                    │
│   [KEY_ENCODING][VALUE_ENCODING]                            │
├─────────────────────────────────────────────────────────────┤
│ FIELD_2 (variable length)                                    │
│   [KEY_ENCODING][VALUE_ENCODING]                            │
├─────────────────────────────────────────────────────────────┤
│ ...                                                          │
├─────────────────────────────────────────────────────────────┤
│ FIELD_N (variable length)                                    │
│   [KEY_ENCODING][VALUE_ENCODING]                            │
├─────────────────────────────────────────────────────────────┤
│ CRC32 (4 bytes, v2 only, big-endian)                        │
│   Only present if version == 0x02                           │
└─────────────────────────────────────────────────────────────┘
```

**Header Details:**
- **Magic Bytes:** "BLAZE" (0x42 0x4C 0x41 0x5A 0x45) lets me quickly validate the format. I check this first thing on decode.
- **Version:** 0x01 (v1, no CRC) or 0x02 (v2, with CRC32). I added CRC32 in v2 after seeing some corruption cases in testing.
- **Field Count:** UInt16 big-endian. I pre-allocate the dictionary with this capacity—it's a small optimization but helps with large records.

#### Field Encoding

Each field has a key encoding followed by a value encoding. I spent a lot of time optimizing this because field names are repeated constantly.

**Key Encoding (Two Variants):**

**Variant A: Common Field (1 byte)**
```
┌─────────────────────────────────────┐
│ 1 byte: Field ID (0x01-0x7F)        │
└─────────────────────────────────────┘
```

I maintain a dictionary of the top 127 most common field names (like "id", "createdAt", "title"). These get encoded as a single byte instead of the full string. In practice, this saves a ton of space because most records use these common fields.

**Variant B: Custom Field (3+N bytes)**
```
┌─────────────────────────────────────┐
│ 1 byte: Marker (0xFF)               │
│ 2 bytes: Key length (big-endian)     │
│ N bytes: UTF-8 key string            │
└─────────────────────────────────────┘
```

Fields not in my common dictionary use the 0xFF marker. I support unlimited custom fields this way—the common field optimization is just that, an optimization.

**Example:**
- "id" → 0x01 (1 byte total)
- "myCustomField" → 0xFF + 0x000D + "myCustomField" (16 bytes total)

#### Type System

The type tag system has optimizations for common cases. I added these after profiling showed certain patterns were dominating encoding time.

**Base Types:**
- `0x01`: String (full, 4-byte length + UTF-8)
- `0x02`: Int (full, 8 bytes big-endian)
- `0x03`: Double (8 bytes bitPattern big-endian)
- `0x04`: Bool (1 byte: 0x01 true, 0x00 false)
- `0x05`: UUID (16 bytes binary)
- `0x06`: Date (8 bytes TimeInterval big-endian)
- `0x07`: Data (4-byte length + N bytes)
- `0x08`: Array (2-byte count + recursive items)
- `0x09`: Dictionary (2-byte count + sorted key-value pairs)
- `0x0A`: Vector (4-byte count + N*4 bytes Float32)
- `0x0B`: Null (0 bytes)

**Optimizations:**
- `0x11`: Empty String (1 byte total) — I see a lot of empty strings in real data
- `0x12`: Small Int (0-255, 2 bytes total vs 9 for full int) — most integers are small
- `0x18`: Empty Array (1 byte total)
- `0x19`: Empty Dictionary (1 byte total)
- `0x20-0x2F`: Inline String (type + length in 1 byte, length ≤15) — short strings are common

These optimizations came from analyzing real workloads. The inline string optimization alone saves about 15% on typical records.

#### Value Encoding Examples

**String Encoding:**

Empty string:
```
[0x11]  (1 byte total)
```

Inline string (≤15 bytes):
```
[0x20 | length] [UTF-8 bytes]
Example: "Hello" (5 bytes) → [0x25] [0x48 0x65 0x6C 0x6C 0x6F]
```

Full string (>15 bytes):
```
[0x01] [length:4 bytes BE] [UTF-8 bytes]
Example: "Hello, world!" → [0x01] [0x0000000D] [0x48 0x65 0x6C 0x6C 0x6F 0x2C 0x20 0x77 0x6F 0x72 0x6C 0x64 0x21]
```

**Integer Encoding:**

Small int (0-255):
```
[0x12] [value:1 byte]
Example: 42 → [0x12] [0x2A]
```

Full int:
```
[0x02] [value:8 bytes BE]
Example: 1000 → [0x02] [0x00 0x00 0x00 0x00 0x00 0x00 0x03 0xE8]
```

**Array Encoding:**

Empty array:
```
[0x18]  (1 byte total)
```

Non-empty array:
```
[0x08] [count:2 bytes BE] [item1] [item2] ... [itemN]
```

**Dictionary Encoding:**

Empty dictionary:
```
[0x19]  (1 byte total)
```

Non-empty dictionary:
```
[0x09] [count:2 bytes BE] [key1][value1] [key2][value2] ... [keyN][valueN]
```

I sort keys before encoding for deterministic output. This makes testing easier and enables some optimizations.

#### Complete Record Example

**Input:**
```swift
BlazeDataRecord([
    "id": .uuid(UUID(...)),
    "title": .string("Hello"),
    "count": .int(42),
    "active": .bool(true)
])
```

**Binary Encoding (hexadecimal):**
```
42 4C 41 5A 45 02 00 04    // Header: "BLAZE" + v2 + 4 fields
01                          // Field 1 key: "id" (common field 0x01)
05 [16 bytes UUID]          // Field 1 value: UUID type + 16 bytes
06                          // Field 2 key: "title" (common field 0x06)
25 48 65 6C 6C 6F          // Field 2 value: Inline string "Hello" (0x25 = 0x20|5)
2F                          // Field 3 key: "count" (common field 0x2F)
12 2A                       // Field 3 value: Small int 42 (0x12 + 0x2A)
23                          // Field 4 key: "active" (common field 0x23)
04 01                       // Field 4 value: Bool true (0x04 + 0x01)
[CRC32: 4 bytes]            // CRC32 checksum (v2 only)
```

**Size Comparison:**
- JSON: ~120 bytes
- BlazeBinary: ~40 bytes (67% smaller)

In practice, the savings are even better on larger records because the common field compression really shines.

#### Network Frame Structure

For network sync, I wrap BlazeBinary records in frames. This gives me framing without relying on the transport layer:

```
┌─────────────────────────────────────────────────────────────┐
│ FRAME HEADER (5 bytes)                                      │
├─────────────────────────────────────────────────────────────┤
│ 1 byte: Frame Type (0x01-0x06)                              │
│ 4 bytes: Payload Length (big-endian UInt32)                 │
├─────────────────────────────────────────────────────────────┤
│ PAYLOAD (variable length)                                   │
│   Encrypted with AES-256-GCM (if handshaked)                │
│   Or plaintext (during handshake)                           │
└─────────────────────────────────────────────────────────────┘
```

**Frame Types:**
- `0x01`: handshake
- `0x02`: handshakeAck
- `0x03`: verify
- `0x04`: handshakeComplete
- `0x05`: encryptedData
- `0x06`: operation

#### Protocol Characteristics

**Endianness:**
All multi-byte integers are big-endian (network byte order). I chose this for cross-platform compatibility—it's a bit slower on little-endian systems, but the consistency is worth it.

**Deterministic Encoding:**
Fields are sorted by key before encoding, and dictionary keys are sorted too. Identical records produce identical binary output. This makes testing deterministic and enables some optimizations like content-addressable storage.

**Corruption Detection:**
- Magic bytes validate format (catches most corruption immediately)
- Version byte validates compatibility
- CRC32 checksum (v2) detects data corruption with about 99.9% detection rate
- Length validation prevents buffer overflows

I added CRC32 after seeing some edge cases where corruption wasn't caught early enough. It adds 4 bytes per record, but the safety is worth it.

**Performance Optimizations:**
- Pre-allocated buffers reduce memory allocations (this was a big win)
- Common field compression (1 byte vs 3+N bytes)
- Small int optimization (2 bytes vs 9 bytes)
- Inline strings (1 byte overhead for ≤15 bytes)
- ARM-optimized codec with SIMD support (I wrote separate code paths for ARM)

**Limits:**
- String max: 100MB (I could go higher, but this prevents memory exhaustion)
- Data max: 100MB
- Array max: 100,000 items
- Dictionary max: 100,000 items
- Vector max: 1,000,000 elements

These limits are conservative. I've never hit them in practice, but they prevent malicious inputs from causing problems.

**Test Coverage:**
I have 116 BlazeBinary tests that validate encoding correctness, compatibility, and corruption detection. Byte-level verification ensures the encoding matches the spec exactly. Corruption recovery tests validate graceful failure handling.

---

## Concurrency Model

I implemented multi-version concurrency control (MVCC) to provide snapshot isolation. This was one of the harder parts to get right—the version management and garbage collection took a lot of iteration.

### MVCC Architecture

*Conceptual diagram of version management*

```mermaid
graph TB
    subgraph T1Group["Transaction T1 (Read)"]
        T1["Snapshot Version<br/>V=100"]
        T1R1["Read Record A<br/>Version 95"]
        T1R2["Read Record B<br/>Version 98"]
    end
    
    subgraph T2Group["Transaction T2 (Write)"]
        T2["Snapshot Version<br/>V=100"]
        T2W1["Write Record A<br/>Creates Version 101"]
        T2C["Commit<br/>Version 101 visible"]
    end
    
    subgraph T3Group["Transaction T3 (Read)"]
        T3["Snapshot Version<br/>V=102"]
        T3R1["Read Record A<br/>Version 101"]
        T3R2["Read Record B<br/>Version 98"]
    end
    
    subgraph VersionStore["Version Storage"]
        VS["VersionManager<br/>Maintains All Versions"]
        GC["Garbage Collector<br/>Removes Old Versions"]
    end
    
    T1 --> T1R1
    T1 --> T1R2
    T2 --> T2W1
    T2 --> T2C
    T3 --> T3R1
    T3 --> T3R2
    
    T1R1 --> VS
    T1R2 --> VS
    T2W1 --> VS
    T3R1 --> VS
    T3R2 --> VS
    
    VS --> GC
    
    classDef readTxn fill:#3498db,stroke:#2980b9,stroke-width:2px,color:#fff
    classDef writeTxn fill:#e74c3c,stroke:#c0392b,stroke-width:2px,color:#fff
    classDef readTxn2 fill:#2ecc71,stroke:#27ae60,stroke-width:2px,color:#fff
    classDef version fill:#f39c12,stroke:#e67e22,stroke-width:2px,color:#fff
    
    class T1,T1R1,T1R2 readTxn
    class T2,T2W1,T2C writeTxn
    class T3,T3R1,T3R2 readTxn2
    class VS,GC version
```

**Snapshot Isolation:**
Each transaction sees a consistent snapshot of the database at transaction start. Reads never block writes, which was a key requirement. Writes create new versions, and old versions remain accessible to concurrent readers until garbage collection. Conflict detection prevents lost updates.

**Performance Characteristics:**
I've observed 20–100× improvements over naive locking under read-heavy synthetic workloads. Concurrent reads scale linearly with available cores, which is exactly what I wanted. Write performance depends on conflict rate and garbage collection frequency—in low-conflict scenarios, it's very fast.

**Garbage Collection:**
Obsolete versions are collected when no active transactions reference them. Long-running read transactions can delay collection, but in practice this hasn't been an issue. Automatic collection runs periodically, and you can trigger it manually if needed.

The GC was tricky to implement correctly. I had to track which transactions are still active and which versions they might reference. Getting this wrong causes data loss, so I tested it extensively.

---

## Security Model

All data is encrypted at rest using AES-256-GCM. I made this the default because I don't trust the filesystem to protect sensitive data.

### Encryption Architecture

*Conceptual diagram of encryption pipeline*

```mermaid
graph TB
    subgraph Input["Input"]
        I1["Plaintext Data<br/>BlazeDataRecord"]
    end
    
    subgraph KeyDeriv["Key Derivation"]
        K1["User Password"]
        K2["Argon2id<br/>Password Hashing"]
        K3["HKDF<br/>Key Expansion"]
        K4["Encryption Key<br/>256-bit"]
    end
    
    subgraph Encryption["Encryption"]
        E1["Generate Nonce<br/>Unique per Page"]
        E2["AES-256-GCM<br/>Encrypt"]
        E3["Authentication Tag<br/>Tamper Detection"]
    end
    
    subgraph Storage["Storage"]
        S1["Encrypted Page<br/>4KB"]
        S2["Secure Enclave<br/>iOS/macOS Optional"]
    end
    
    subgraph Decryption["Decryption"]
        D1["Read Encrypted Page"]
        D2["Verify Tag"]
        D3["AES-256-GCM<br/>Decrypt"]
        D4["Plaintext Data"]
    end
    
    I1 --> K1
    K1 --> K2
    K2 --> K3
    K3 --> K4
    
    I1 --> E1
    E1 --> E2
    K4 --> E2
    E2 --> E3
    
    E3 --> S1
    K4 --> S2
    S2 --> S1
    
    S1 --> D1
    D1 --> D2
    D2 --> D3
    K4 --> D3
    D3 --> D4
    
    classDef input fill:#3498db,stroke:#2980b9,stroke-width:2px,color:#fff
    classDef key fill:#2ecc71,stroke:#27ae60,stroke-width:2px,color:#fff
    classDef encrypt fill:#e74c3c,stroke:#c0392b,stroke-width:2px,color:#fff
    classDef storage fill:#9b59b6,stroke:#8e44ad,stroke-width:2px,color:#fff
    classDef decrypt fill:#f39c12,stroke:#e67e22,stroke-width:2px,color:#fff
    
    class I1 input
    class K1,K2,K3,K4 key
    class E1,E2,E3 encrypt
    class S1,S2 storage
    class D1,D2,D3,D4 decrypt
```

**Key Derivation:**
I hash the user password using Argon2id (memory-hard function) to prevent fast brute force attacks. Then HKDF expands the derived key material to a 256-bit encryption key. Key material is never stored on disk—if you lose the password, the data is gone. This is by design.

**Encryption:**
AES-256-GCM provides authenticated encryption. Each page uses a unique nonce to ensure cryptographic safety. The authentication tags detect tampering—if someone modifies an encrypted page, decryption will fail. Replay prevention is enforced by rejecting stale or duplicated ciphertexts at the record or page level.

I went with GCM mode because it's fast and provides authentication in one pass. The per-page nonces ensure that even if two pages have identical plaintext, the ciphertext will be different.

**Secure Enclave Integration:**
On iOS/macOS, I optionally integrate with Secure Enclave. This stores key material in hardware, outside the app's memory space. It's a significant security improvement when available. When Secure Enclave isn't available, it falls back to standard key derivation.

**Security Guarantees:**
- Data encrypted before writing to disk
- Wrong password fails immediately (constant-time comparison prevents timing attacks)
- Authentication tags prevent tampering
- 11 security test files validate encryption correctness, round-trip integrity, and security invariants

---

## Threat Model

I did a thorough threat model analysis based on the actual code. Here's what I found:

### Threat Actors & Attack Surfaces

*Conceptual diagram of threat landscape*

```mermaid
graph TB
    subgraph External["External Network Attackers"]
        E1["MITM<br/>Traffic Interception"]
        E2["Replay<br/>Operation Replay"]
        E3["DoS<br/>Resource Exhaustion"]
        E4["Injection<br/>Malicious Operations"]
    end
    
    subgraph Insider["Malicious Insiders"]
        I1["RLS Bypass<br/>Policy Violation"]
        I2["Privilege Escalation<br/>Permission Manipulation"]
        I3["Data Exfiltration<br/>Unauthorized Access"]
    end
    
    subgraph Physical["Compromised Devices"]
        P1["Physical Access<br/>Device Theft"]
        P2["Memory Dumps<br/>Key Extraction"]
        P3["Metadata Tampering<br/>Index Corruption"]
    end
    
    subgraph Controls["Security Controls"]
        C1["AES-256-GCM<br/>Encryption"]
        C2["ECDH + HMAC<br/>Authentication"]
        C3["RLS Policies<br/>Access Control"]
        C4["Rate Limiting<br/>DoS Protection"]
        C5["Secure Enclave<br/>Hardware Keys"]
    end
    
    E1 --> C1
    E1 --> C2
    E2 --> C4
    E3 --> C4
    E4 --> C2
    
    I1 --> C3
    I2 --> C3
    I3 --> C3
    
    P1 --> C1
    P1 --> C5
    P2 --> C5
    P3 --> C2
    
    classDef threat fill:#e74c3c,stroke:#c0392b,stroke-width:2px,color:#fff
    classDef control fill:#2ecc71,stroke:#27ae60,stroke-width:2px,color:#fff
    
    class E1,E2,E3,E4,I1,I2,I3,P1,P2,P3 threat
    class C1,C2,C3,C4,C5 control
```

### Network Attack Vectors

**Man-in-the-Middle (MITM):**
ECDH P-256 key exchange plus AES-256-GCM encryption provides end-to-end encryption. I implemented perfect forward secrecy with ephemeral keys, so even if someone captures traffic, they can't decrypt it later. The gap here is certificate pinning—I stubbed it out but haven't fully implemented it yet. It's on my TODO list.

**Replay Attacks:**
I use 16-byte operation nonces, 60-second timestamp validation, and operation ID tracking. This is fully implemented with a 10K operation ID cache. In practice, this has worked well—I haven't seen any replay attacks get through.

**Denial of Service:**
Rate limiting (1000 ops/min per user), operation pooling (max 100 concurrent), and batch size limits (10K-50K ops) help here. The issue is that rate limiting isn't enforced in all sync paths yet. I need to fix this.

### Storage Attack Vectors

**Physical Access / Device Theft:**
AES-256-GCM per-page encryption, Argon2id key derivation, and Secure Enclave integration (iOS/macOS) protect against this. Secure Enclave provides hardware-backed key protection, which is the strongest defense here.

**Metadata Tampering:**
HMAC-SHA256 signatures on metadata, integrity checks on load, and CRC32 checksums detect tampering. I implemented automatic rebuild on corruption, which has saved me in testing.

**Memory Dumps:**
Secure Enclave stores keys outside app memory, and forward secrecy limits the exposure window. The gap is explicit memory clearing—I haven't implemented this yet, so keys might remain in memory after use. This is a known issue.

### Access Control Attack Vectors

**RLS Policy Bypass:**
The policy engine evaluates policies on every operation, and query integration applies RLS filters. This is fully implemented with permissive/restrictive logic. I've tested it extensively and it works well.

**Privilege Escalation:**
Authorization checks validate permissions per operation, and an admin flag separates admin permissions. The gap is that policy modification isn't explicitly protected—I should require admin for this.

### Input Validation Attack Vectors

**Path Traversal:**
Path validation rejects traversal characters, and null byte protection prevents injection. This is fully implemented and tested.

**Memory Exhaustion:**
100MB max record size, overflow page support, and batch size limits prevent this. I've tested with malicious inputs and it holds up.

**Injection Attacks:**
Type-safe query builder (no string concatenation), schema validation, and input sanitization prevent injection. The type safety prevents SQL injection entirely—this was a key design decision.

### Security Control Matrix

| Control | Implementation | Status | Risk Level |
|---------|---------------|--------|------------|
| **At-Rest Encryption** | AES-256-GCM per page | ✅ Implemented | 🟢 LOW |
| **In-Transit Encryption** | ECDH + AES-256-GCM | ✅ Implemented | 🟢 LOW |
| **Key Derivation** | Argon2id | ✅ Implemented | 🟢 LOW |
| **Perfect Forward Secrecy** | Ephemeral ECDH keys | ✅ Implemented | 🟢 LOW |
| **Secure Enclave** | Hardware-backed keys | ✅ Implemented (iOS/macOS) | 🟢 LOW |
| **Replay Protection** | Nonces + timestamps | ✅ Implemented | 🟢 LOW |
| **Rate Limiting** | 1000 ops/min per user | ⚠️ Not enforced everywhere | 🟡 MEDIUM |
| **RLS Policies** | Policy engine | ✅ Implemented | 🟢 LOW |
| **HMAC Signatures** | Metadata signatures | ✅ Implemented | 🟢 LOW |
| **Certificate Pinning** | TLS certificate validation | ⚠️ Stubbed | 🟡 MEDIUM |
| **Operation Signatures** | Optional HMAC | ⚠️ Optional | 🟡 MEDIUM |

### Risk Assessment Summary

**Critical Risks (Fix Immediately):**
- Rate limiting not enforced in all sync paths
- Operation signatures optional (should be mandatory)
- Certificate pinning stubbed (not fully implemented)

**High Risks (Fix Within 1 Week):**
- Policy modification not protected (require admin)
- Explicit memory clearing not implemented
- Connection-level rate limiting not implemented

**Medium Risks (Fix Within 1 Month):**
- Audit logging limited coverage
- IP-based rate limiting not implemented
- Circuit breaker not implemented

**Test Coverage:**
I have 11 security test files that validate encryption, authentication, and access control. 7 persistence/recovery test files validate crash recovery and corruption handling. Distributed security tests validate network attack mitigations.

---

## Transaction Model

ACID transaction guarantees with write-ahead logging. This was non-negotiable—I needed to ensure data integrity even if the process crashes mid-write.

### Write-Ahead Logging

*Conceptual sequence diagram of transaction flow*

```mermaid
sequenceDiagram
    participant App
    participant Client
    participant WAL
    participant PageStore
    participant Index
    
    App->>Client: beginTransaction()
    Client->>WAL: BEGIN entry
    WAL->>WAL: fsync()
    
    App->>Client: insert(record)
    Client->>WAL: WRITE entry
    Client->>PageStore: Stage write
    Client->>Index: Stage index update
    
    App->>Client: commitTransaction()
    Client->>PageStore: Flush staged writes
    Client->>Index: Apply index updates
    Client->>WAL: COMMIT entry
    WAL->>WAL: fsync()
    Note over WAL: Checkpoint or truncate<br/>when safe
    Client->>App: Success
    
    Note over WAL,PageStore: Crash Recovery:<br/>Replay WAL entries<br/>Restore committed state
```

**WAL Behavior:**
All writes go through the write-ahead log before the page store. WAL entries are fsync'd before commit acknowledgment—this is the durability guarantee. After commits, the WAL is truncated or checkpointed when safe, according to configured durability thresholds. WAL replay recovers all committed transactions after crashes.

I learned the hard way that you can't just fsync the WAL and call it done. The checkpoint/truncate logic matters a lot for performance. Too aggressive and you lose durability; too conservative and performance suffers.

**ACID Properties:**

**Atomicity:** All operations in a transaction succeed or fail together. Partial failures trigger automatic rollback. I tested this with 100-operation transactions to make sure it works under stress.

**Consistency:** The database never enters an invalid state. Index updates are atomic with data writes. Schema validation prevents invalid states. I tested this under concurrent updates and it holds up.

**Isolation:** Snapshot isolation via MVCC ensures each transaction sees a consistent snapshot. Concurrent transactions don't interfere. I tested with 50 concurrent readers and 10 writers, and it works as expected.

**Durability:** Committed data is fsync'd before acknowledgment. WAL replay recovers all committed transactions after crashes. I tested this with crash simulation—pulling the plug mid-transaction, corrupting the WAL, etc.

**Test Coverage:** 907 unit tests validate ACID compliance, crash recovery, and transaction durability across 223 test files. This is one area where I didn't skimp on testing.

---

## Query System

The query system uses a fluent API with automatic index selection. I built this because I wanted something that felt natural in Swift while still being fast.

### Query Execution

*Conceptual diagram of query planning and execution*

```mermaid
graph TB
    Q["QueryBuilder<br/>where/orderBy/limit"]
    
    subgraph Planning["Query Planning"]
        QP["QueryPlanner<br/>Analyze Query"]
        QO["QueryOptimizer<br/>Select Indexes"]
        EP["Execution Plan<br/>Optimized Path"]
    end
    
    subgraph Indexes["Index Selection"]
        PI["Primary Index<br/>UUID Lookup"]
        SI["Secondary Index<br/>Field Lookup"]
        CI["Compound Index<br/>Multi-Field"]
        FT["Full-Text Index<br/>Inverted Index"]
    end
    
    subgraph Execution["Execution"]
        EX1["Index Scan<br/>Fast Path"]
        EX2["Full Scan<br/>Fallback"]
        EX3["Filter<br/>In-Memory"]
        EX4["Sort<br/>Result Ordering"]
    end
    
    subgraph Result["Result"]
        R1["BlazeDataRecord[]<br/>Results"]
        R2["QueryCache<br/>10-100x Faster"]
    end
    
    Q --> QP
    QP --> QO
    QO --> EP
    
    EP --> PI
    EP --> SI
    EP --> CI
    EP --> FT
    
    PI --> EX1
    SI --> EX1
    CI --> EX1
    FT --> EX1
    
    EX1 --> EX3
    EX2 --> EX3
    EX3 --> EX4
    EX4 --> R1
    R1 --> R2
    
    classDef query fill:#3498db,stroke:#2980b9,stroke-width:3px,color:#fff
    classDef planning fill:#2ecc71,stroke:#27ae60,stroke-width:2px,color:#fff
    classDef index fill:#f39c12,stroke:#e67e22,stroke-width:2px,color:#fff
    classDef exec fill:#e74c3c,stroke:#c0392b,stroke-width:2px,color:#fff
    classDef result fill:#9b59b6,stroke:#8e44ad,stroke-width:2px,color:#fff
    
    class Q query
    class QP,QO,EP planning
    class PI,SI,CI,FT index
    class EX1,EX2,EX3,EX4 exec
    class R1,R2 result
```

**Query Planner:**
The query planner uses rule-based heuristics to select indexes. I haven't built a cost-based optimizer yet—that's on the roadmap. The current approach works well for most queries, automatically selecting indexes for common patterns. When no index is available, it falls back to a full scan.

**Index Types:**
- **Primary Index:** UUID-based record lookup (this is always available)
- **Secondary Index:** Single-field or compound indexes (you create these as needed)
- **Full-Text Index:** Inverted index for text search (I built this because I needed it for a project)
- **Spatial Index:** Geospatial queries and distance calculations
- **Vector Index:** Cosine similarity for embeddings (useful for AI workloads)

**Query Features:**
Filtering, sorting, limiting, JOINs (inner, left, right, full outer), aggregations (COUNT, SUM, AVG, MIN, MAX, GROUP BY, HAVING), subqueries, window functions, and query caching for repeated queries.

**Full-Text Search:**
I implemented an inverted index because I needed fast text search. It gives 50–1000× improvements relative to unindexed full scans on large corpora. Index build time scales with corpus size, but once built, queries are very fast.

---

## Performance Characteristics

I benchmarked this on an Apple M4 Pro (36 GB RAM) running macOS 15 / OS 26. The benchmarks use synthetic but realistic workloads. Your actual performance will vary with dataset shape and workload patterns.

### Core Operations

| Operation | Throughput | Latency (p50) | Notes |
|-----------|------------|---------------|-------|
| Insert | 1,200–2,500 ops/sec | 0.4–0.8ms | Includes encryption, WAL, index updates |
| Fetch | 2,500–5,000 ops/sec | 0.2–0.4ms | Memory-mapped I/O, decryption |
| Update | 1,000–1,600 ops/sec | 0.6–1.0ms | Fetch + modify + write |
| Delete | 3,300–10,000 ops/sec | 0.1–0.3ms | Fastest operation |
| Batch Insert (100) | 3,300–6,600 ops/sec | 15–30ms | Single fsync for entire batch |

### Multi-Core Performance (8 Cores)

| Operation | Throughput | Scaling Factor |
|-----------|------------|----------------|
| Insert | 10,000–20,000 ops/sec | 8× linear scaling |
| Fetch | 20,000–50,000 ops/sec | 8–10× parallel reads |
| Update | 8,000–16,000 ops/sec | 8× parallel encoding |
| Delete | 26,000–80,000 ops/sec | 8× minimal locking |

The multi-core scaling is good because MVCC lets reads happen in parallel without blocking. Writes still need some coordination, but it's minimal.

### Query Performance

| Query Type | Dataset Size | Throughput | Latency (p50) |
|------------|--------------|------------|---------------|
| Basic Query | 100 records | 200–500 queries/sec | 2–5ms |
| Filtered Query | 1K records | 66–200 queries/sec | 5–15ms |
| Indexed Query | 10K records | 200–500 queries/sec | 2–5ms | 10–100× faster than unindexed |
| JOIN (1K × 1K) | 1K records | 20–50 queries/sec | 20–50ms | Batch fetching, O(N+M) |
| Aggregation (COUNT) | 10K records | 200–500 queries/sec | 2–5ms |
| Full-Text Search | 1K docs | 33–100 queries/sec | 10–30ms | Without index |
| Full-Text Search (Indexed) | 100K docs | 200–500 queries/sec | 5ms | 50–1000× faster with inverted index |

### Network Sync Performance

| Transport | Latency | Throughput | Use Case |
|-----------|---------|------------|----------|
| In-Memory Queue | <0.1ms | 1,000,000+ ops/sec | Same process |
| Unix Domain Socket | 0.2–0.5ms | 5,000–20,000 ops/sec | Cross-process, same device |
| TCP (Local Network) | 2–5ms | 200–500 ops/sec | Same LAN |
| TCP (Remote Network) | 10–50ms | 20–100 ops/sec | WAN/Internet |

**Network Sync (WiFi 100 Mbps):**
- Small operations (200 bytes): 7,800 ops/sec
- Medium operations (550 bytes): 5,000 ops/sec
- Large operations (1900 bytes): 3,450 ops/sec

The in-memory queue is essentially free—it's just pointer passing. Unix sockets are fast too, but TCP adds significant latency. I optimized the BlazeBinary encoding to minimize payload size, which helps a lot over the network.

### Performance Invariants

I maintain performance guarantees through automated regression testing:

- **Batch Insert:** 10,000 records complete in < 2 seconds
- **Individual Insert:** Average latency < 10ms
- **Query Latency:** Simple queries < 5ms, complex queries < 200ms
- **Index Build Time:** 10,000 records indexed in < 5 seconds
- **Concurrent Reads:** 100 concurrent readers execute in 10–50ms (20–100× faster than locking)

12 performance test files track 40+ metrics and fail if thresholds are exceeded. This catches regressions early.

---

## Benchmark Methodology

Here's how I run the benchmarks:

**Synthetic Data Generation:**
Records generated with variable field counts (3–15 fields). Field types: String, Int, Double, Bool, Date, Data, UUID. String lengths: 10–500 characters. Integer ranges: 0–1,000,000. I use realistic distribution patterns (normal, uniform, skewed) because uniform random data doesn't reflect real workloads.

**Cache Behavior:**
- Cold cache: Database opened fresh, no warm-up
- Warm cache: Database opened, 10,000 operations performed before measurement
- Cache size: Default page cache (varies by available memory)

**Concurrency:**
- Single-process: All operations in single process
- Multi-process: Operations distributed across processes (Unix sockets or TCP)
- Concurrent readers: 10–100 concurrent read transactions
- Concurrent writers: 1–10 concurrent write transactions

**Workload Patterns:**
- Sequential: Operations on sequential record IDs
- Random: Operations on randomly selected record IDs
- Mixed: 70% reads, 30% writes (this reflects most real workloads)

**Durability:**
- WAL durability mode: Full fsync on commit (default)
- Batch operations: Single fsync per batch
- Performance mode: Deferred fsync (not recommended for production)

**Measurement:**
Each benchmark runs 10 iterations. I report median (p50) latency. Throughput is calculated as operations per second. I remove outliers (top and bottom 10%) to get cleaner numbers.

---

## Testing & Validation

I have comprehensive test coverage:

- **907 unit tests** covering all features at 97% code coverage
- **20+ integration scenarios** validating real-world workflows
- **223 test files** organized by domain (engine, sync, security, performance)
- **Property-based tests** with 100,000+ generated inputs
- **Chaos engineering** tests simulating crashes, corruption, and failures
- **Stress tests** validating behavior under high load
- **Performance regression tests** tracking 40+ metrics

**Test Domains:**
- Core Database Engine: 19 test files
- Query System: 10 test files
- Indexes: 12 test files
- Security: 11 test files
- Distributed Sync: 10 test files
- Performance: 12 test files
- Concurrency: 9 test files
- Persistence & Recovery: 7 test files
- Codec: 15 test files
- Integration: 11 test files

### Fault Injection & Crash Testing

I test the following fault scenarios:

**Power Loss Simulation:**
Simulated power loss between WAL fsync and page flush. This validates that WAL replay recovers committed transactions. I also test partial writes and incomplete transactions.

**Corruption Scenarios:**
Simulated torn or partial page writes, metadata corruption (index map, page headers), and overflow chain corruption. This validates corruption detection and graceful failure. The corruption detection has caught real bugs in testing.

**Recovery Testing:**
WAL replay verification after simulated crashes, metadata rebuild from data pages, dangling index detection and correction, and incomplete flush recovery. The metadata rebuild feature has saved me multiple times during development.

7 persistence/recovery test files validate crash recovery, WAL replay, and corruption handling.

### Data Integrity Guarantees

**ACID Compliance:**
- Atomicity: All operations in a transaction succeed or fail together
- Consistency: Database never enters invalid state
- Isolation: Snapshot isolation via MVCC prevents dirty reads
- Durability: Committed data is fsync'd before acknowledgment

**Crash Recovery:**
WAL durability means all writes go through the Write-Ahead Log. WAL entries are fsync'd before commit acknowledgment. Crash recovery replays committed transactions and discards uncommitted ones. If metadata is corrupted, BlazeDB automatically rebuilds it from data pages—this feature has been a lifesaver.

**Data Corruption Detection:**
BlazeBinary encoding includes CRC32 checksums. Page headers include version and checksum fields. Invalid data triggers corruption detection. Metadata corruption triggers automatic rebuild from data pages.

**Index Integrity:**
All index types remain consistent with data. Index updates are atomic with data writes. Query results match manual filtering. Cross-index validation ensures all indexes match the actual data.

12 index test files validate consistency, query correctness, and cross-index alignment.

---

## Recommended Use Cases

BlazeDB works well for:

**Encrypted Local Storage:**
macOS/iOS applications requiring encrypted local data storage, applications with sensitive user data requiring at-rest encryption, and offline-first applications with local data persistence.

**Developer Tooling:**
Tools requiring embedded, durable state, development environments needing high-throughput document stores, and local analytics engines and data processing pipelines.

**AI Agents & Automation:**
AI agents requiring persistent memory and execution history, automation tools needing structured local storage, and applications requiring semantic search and vector similarity.

**Secure Applications:**
Applications requiring at-rest encryption with minimal overhead, systems needing ACID guarantees for local data, and applications with strict data integrity requirements.

BlazeDB is not suitable for:
- Distributed cluster databases
- Petabyte-scale analytics workloads
- Applications requiring automatic sharding
- Use cases requiring cost-based query optimization

---

## API & Integration

### Installation

**Swift Package Manager:**
```swift
dependencies: [
    .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.5.0")
]
```

Or in Xcode: **File → Add Package Dependencies** → paste repo URL

### Basic Usage

```swift
import BlazeDB

// Initialize (databases stored in ~/Library/Application Support/BlazeDB/)
let db = try BlazeDBClient(name: "MyApp", password: "your-secure-password")

// Insert
let record = BlazeDataRecord([
    "title": .string("Fix login bug"),
    "priority": .int(5),
    "status": .string("open")
])
let id = try db.insert(record)

// Query
let openBugs = try db.query()
    .where("status", equals: .string("open"))
    .where("priority", greaterThan: .int(3))
    .orderBy("priority", descending: true)
    .execute()
    .records

// Use in SwiftUI (auto-updating)
struct BugListView: View {
    @BlazeQuery(db: db, where: "status", equals: .string("open"))
    var bugs
    
    var body: some View {
        List(bugs) { bug in
            Text(bug.string("title"))
        }
    }
}
```

### Distributed Sync

*Conceptual diagram of sync architecture*

```mermaid
graph TB
    subgraph NodeA["Node A"]
        A1["BlazeDBClient"]
        A2["SyncEngine"]
        A3["OperationLog"]
    end
    
    subgraph Transport["Transport Layer"]
        T1["In-Memory<br/>&lt;0.1ms<br/>1M+ ops/sec"]
        T2["Unix Socket<br/>~0.5ms<br/>5-20K ops/sec"]
        T3["TCP Relay<br/>~5ms<br/>200-500 ops/sec"]
    end
    
    subgraph NodeB["Node B"]
        B1["BlazeDBClient"]
        B2["SyncEngine"]
        B3["OperationLog"]
    end
    
    subgraph Protocol["Protocol"]
        P1["BlazeBinary<br/>Encoding"]
        P2["LZ4 Compression<br/>3-5x faster"]
        P3["AES-256-GCM<br/>E2E Encryption"]
        P4["ECDH P-256<br/>Key Exchange"]
    end
    
    A1 --> A2
    A2 --> A3
    A3 --> T1
    A3 --> T2
    A3 --> T3
    
    T1 --> P1
    T2 --> P1
    T3 --> P1
    
    P1 --> P2
    P2 --> P3
    P3 --> P4
    
    P4 --> B3
    B3 --> B2
    B2 --> B1
    
    classDef node fill:#3498db,stroke:#2980b9,stroke-width:2px,color:#fff
    classDef transport fill:#2ecc71,stroke:#27ae60,stroke-width:2px,color:#fff
    classDef protocol fill:#9b59b6,stroke:#8e44ad,stroke-width:2px,color:#fff
    classDef nodeB fill:#e74c3c,stroke:#c0392b,stroke-width:2px,color:#fff
    
    class A1,A2,A3 node
    class T1,T2,T3 transport
    class P1,P2,P3,P4 protocol
    class B1,B2,B3 nodeB
```

**Transport Layers:**
- In-memory queue: Same process communication (<0.1ms latency)
- Unix domain socket: Cross-process, same device (~0.5ms latency)
- TCP relay: Network communication (~5ms local, 10–50ms remote)

**Protocol:**
BlazeBinary encoding is 53% smaller than JSON. Optional LZ4 compression is 3–5× faster than gzip. End-to-end encryption uses AES-256-GCM with ECDH P-256 key exchange. Secure handshake uses shared secret authentication.

---

## Future Work

Things I want to add:

**Query Optimizer:**
Cost-based query optimizer, statistics collection for better index selection, and query plan caching. The current rule-based approach works, but a cost model would be better.

**Distributed Features:**
Multi-master replication (experimental), automatic conflict resolution strategies, and distributed transaction coordination. This is complex, so I'm taking it slow.

**Performance:**
Parallel index builds, incremental index updates, and query result streaming. These are optimizations that would help with large datasets.

**Platform:**
Enhanced Linux performance, Windows support (experimental), and additional Secure Enclave integration. Linux works but isn't as optimized as Apple platforms.

**API:**
GraphQL query interface, REST API for remote access, and additional migration tools. These would make integration easier.

---

## Versioning & Stability

**Current Version:** 2.5.0-alpha

**Versioning Strategy:**
Semantic versioning (MAJOR.MINOR.PATCH). Alpha releases mean APIs may change. Beta releases mean APIs are stable but implementation may change. Stable releases (1.0.0+) have full compatibility guarantees.

**Compatibility:**
Forward upgrade path means databases can be upgraded to newer versions. No forced deletion means existing databases are never automatically deleted. Migration support means format migrations are automatic and transparent.

**Support:**
Complete API reference and architecture docs are available. GitHub Issues for bug reports and feature requests. Contributions are welcome.

---

## Documentation

Complete documentation is organized in `Docs/`:

- `Docs/MASTER_DOCUMENTATION_INDEX.md` - Complete documentation index
- `Docs/Architecture/` - System architecture and design
- `Docs/API/` - API reference and usage guides
- `Docs/Guides/` - Step-by-step guides
- `Docs/Performance/` - Performance analysis and optimization
- `Docs/Security/` - Security architecture and best practices
- `Docs/Sync/` - Distributed sync documentation
- `Docs/Testing/` - Test coverage and methodology

---

## Tools

BlazeDB includes a complete suite of tools:

- **BlazeShell:** Command-line REPL for database operations
- **BlazeDBVisualizer:** macOS app for monitoring, managing, and visualizing databases
- **BlazeStudio:** Visual schema designer with code generation
- **BlazeServer:** Standalone server for remote clients

See `Docs/Tools/` for complete documentation.

---

## Migration from Other Databases

### SQLite → BlazeDB

```swift
try BlazeMigrationTool.importFromSQLite(
    source: sqliteURL,
    destination: blazeURL,
    password: "your-password",
    tables: ["users", "posts", "comments"]  // or nil for all tables
)
```

### Core Data → BlazeDB

```swift
try BlazeMigrationTool.importFromCoreData(
    container: container,
    destination: blazeURL,
    password: "your-password",
    entities: ["User", "Post", "Comment"]  // or nil for all entities
)
```

See `Tools/` directory for migration implementations.

---

## Contributing

BlazeDB is part of Project Blaze. Contributions welcome!

---

## License

MIT License - See LICENSE file for details.
