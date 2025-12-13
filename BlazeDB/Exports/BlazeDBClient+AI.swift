//
//  BlazeDBClient+AI.swift
//  BlazeDB
//
//  AI-Facing Query Layer for BlazeDB
//
//  This extension provides low-level storage APIs for AI workloads.
//  Higher-level packages (e.g., HandwritingAIKit, App) are responsible for
//  encoding/decoding using BlazeBinaryCodable.
//
//  Created by Michael Danylchuk on 12/4/25.
//

import Foundation

// MARK: - AI Data Structures

/// Represents a continuation training sample for handwriting AI.
public struct AIContinuationSample {
    public let beforeText: String
    public let afterText: String
    public let createdAt: Date
    
    public init(beforeText: String, afterText: String, createdAt: Date) {
        self.beforeText = beforeText
        self.afterText = afterText
        self.createdAt = createdAt
    }
}

// MARK: - AI-Facing Storage APIs

extension BlazeDBClient {
    
    // MARK: - Style Model Storage
    
    /// Save a style model to the database.
    ///
    /// The style model is stored as a single record with a special type identifier.
    /// Higher-level packages should encode the model using BlazeBinaryCodable before
    /// passing the Data to this method.
    ///
    /// - Parameter data: The encoded style model data
    /// - Throws: BlazeDBError if the save operation fails
    ///
    /// ## Example
    /// ```swift
    /// // In HandwritingAIKit or App layer:
    /// let encodedModel = try model.encodeBlazeBinary()
    /// try db.saveStyleModel(data: encodedModel)
    /// ```
    public func saveStyleModel(data: Data) throws {
        // Use a fixed UUID for the style model record
        let styleModelID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        
        let record = BlazeDataRecord([
            "type": .string("style_model"),
            "data": .data(data),
            "updatedAt": .date(Date())
        ])
        
        // Upsert to handle both insert and update cases
        _ = try upsert(id: styleModelID, data: record)
        BlazeLogger.debug("Saved style model (\(data.count) bytes)")
    }
    
    /// Load the style model from the database.
    ///
    /// Returns the raw Data that was previously saved. Higher-level packages should
    /// decode this using BlazeBinaryCodable.
    ///
    /// - Returns: The style model data if found, or `nil` if not found
    /// - Throws: BlazeDBError if the load operation fails
    ///
    /// ## Example
    /// ```swift
    /// // In HandwritingAIKit or App layer:
    /// if let modelData = try db.loadStyleModel() {
    ///     let model = try StyleModel.decodeBlazeBinary(from: modelData)
    /// }
    /// ```
    public func loadStyleModel() throws -> Data? {
        let styleModelID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        
        guard let record = try fetch(id: styleModelID),
              case let .data(modelData)? = record.storage["data"] else {
            return nil
        }
        
        BlazeLogger.debug("Loaded style model (\(modelData.count) bytes)")
        return modelData
    }
    
    // MARK: - Style Embedding Storage
    
    /// Save a style embedding vector to the database.
    ///
    /// The style embedding is stored as a single record with a deterministic UUID.
    /// The vector is encoded as binary Data (array of Float values).
    ///
    /// - Parameter vector: The style embedding vector (array of Float values)
    /// - Throws: BlazeDBError if the save operation fails
    ///
    /// ## Example
    /// ```swift
    /// let embedding: [Float] = [0.1, 0.2, 0.3, ...]
    /// try db.saveStyleEmbedding(vector: embedding)
    /// ```
    public func saveStyleEmbedding(vector: [Float]) throws {
        // Use a deterministic UUID for the style embedding record
        let styleEmbeddingID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        
        // Encode vector as Data (array of Float values)
        let vectorData = vector.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        
        let record = BlazeDataRecord([
            "type": .string("style_embedding"),
            "data": .data(vectorData),
            "vectorLength": .int(vector.count),
            "updatedAt": .date(Date())
        ])
        
        // Upsert to handle both insert and update cases
        _ = try upsert(id: styleEmbeddingID, data: record)
        BlazeLogger.debug("Saved style embedding (\(vector.count) dimensions, \(vectorData.count) bytes)")
    }
    
    /// Load the style embedding vector from the database.
    ///
    /// Returns the vector as an array of Float values, or `nil` if not found.
    ///
    /// - Returns: The style embedding vector if found, or `nil` if not found
    /// - Throws: BlazeDBError if the load operation fails
    ///
    /// ## Example
    /// ```swift
    /// if let embedding = try db.loadStyleEmbedding() {
    ///     // Use embedding vector...
    /// }
    /// ```
    public func loadStyleEmbedding() throws -> [Float]? {
        let styleEmbeddingID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        
        guard let record = try fetch(id: styleEmbeddingID),
              case let .data(vectorData)? = record.storage["data"] else {
            return nil
        }
        
        // Decode vector from Data
        let count = vectorData.count / MemoryLayout<Float>.size
        guard count > 0 else { return nil }
        
        var vector: [Float] = []
        vector.reserveCapacity(count)
        
        vectorData.withUnsafeBytes { bytes in
            let floats = bytes.bindMemory(to: Float.self)
            for i in 0..<count {
                vector.append(floats[i])
            }
        }
        
        BlazeLogger.debug("Loaded style embedding (\(vector.count) dimensions)")
        return vector
    }
    
    // MARK: - Snapshot Storage
    
    /// Save a snapshot for a given ID.
    ///
    /// Snapshots are stored as records with the provided ID and a timestamp.
    /// Multiple snapshots can be stored for the same ID. Higher-level packages
    /// should encode the snapshot using BlazeBinaryCodable before passing the Data.
    ///
    /// - Parameters:
    ///   - id: The UUID associated with this snapshot
    ///   - snapshotData: The encoded snapshot data
    /// - Throws: BlazeDBError if the save operation fails
    ///
    /// ## Example
    /// ```swift
    /// // In HandwritingAIKit or App layer:
    /// let encodedSnapshot = try snapshot.encodeBlazeBinary()
    /// try db.saveSnapshot(id: documentID, snapshotData: encodedSnapshot)
    /// ```
    public func saveSnapshot(id: UUID, snapshotData: Data) throws {
        // Generate a unique ID for this snapshot record
        let snapshotRecordID = UUID()
        
        let record = BlazeDataRecord([
            "type": .string("snapshot"),
            "snapshotId": .uuid(id),
            "data": .data(snapshotData),
            "createdAt": .date(Date())
        ])
        
        // Set the ID in the record and insert
        var recordWithID = record
        recordWithID.storage["id"] = .uuid(snapshotRecordID)
        _ = try insert(recordWithID)
        BlazeLogger.debug("Saved snapshot for ID \(id.uuidString.prefix(8)) (\(snapshotData.count) bytes)")
    }
    
    /// Load all snapshots for a given ID.
    ///
    /// Returns all snapshots stored for the provided ID, ordered by creation time (oldest first).
    /// Higher-level packages should decode each Data using BlazeBinaryCodable.
    ///
    /// - Parameter id: The UUID to load snapshots for
    /// - Returns: Array of snapshot data, ordered by creation time
    /// - Throws: BlazeDBError if the load operation fails
    ///
    /// ## Example
    /// ```swift
    /// // In HandwritingAIKit or App layer:
    /// let snapshots = try db.loadSnapshots(for: documentID)
    /// for snapshotData in snapshots {
    ///     let snapshot = try Snapshot.decodeBlazeBinary(from: snapshotData)
    ///     // Process snapshot...
    /// }
    /// ```
    public func loadSnapshots(for id: UUID) throws -> [Data] {
        let results = try query()
            .where("type", equals: .string("snapshot"))
            .where("snapshotId", equals: .uuid(id))
            .orderBy("createdAt", descending: false)
            .execute()
            .records
        
        let snapshots = results.compactMap { record -> Data? in
            guard case let .data(snapshotData)? = record.storage["data"] else {
                return nil
            }
            return snapshotData
        }
        
        BlazeLogger.debug("Loaded \(snapshots.count) snapshot(s) for ID \(id.uuidString.prefix(8))")
        return snapshots
    }
    
    // MARK: - Continuation Training Sample Storage
    
    /// Generate a deterministic UUID from a string hash.
    /// Uses a simple hash of the string to create a deterministic UUID.
    private func deterministicUUID(from string: String) -> UUID {
        // Use a simple hash function to create deterministic bytes
        var hash: UInt64 = 5381
        for char in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(char)
        }
        
        // Create additional hash bytes from the string
        var bytes: [UInt8] = []
        var state = hash
        for i in 0..<16 {
            if i < 8 {
                // Use the hash directly for first 8 bytes
                bytes.append(UInt8((state >> (i * 8)) & 0xFF))
            } else {
                // Generate additional bytes using a simple PRNG
                state = state &* 1103515245 &+ 12345
                bytes.append(UInt8(state & 0xFF))
            }
        }
        
        // Set version (4) and variant bits according to UUID spec
        bytes[6] = (bytes[6] & 0x0F) | 0x40  // Version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // Variant 10
        
        // Create UUID from bytes
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
    
    /// Save a continuation training sample.
    ///
    /// Saves a before/after text pair for handwriting continuation training.
    /// Uses a deterministic UUID derived from the hash of `beforeText` to enable
    /// deduplication and updates.
    ///
    /// - Parameters:
    ///   - beforeText: The text before continuation
    ///   - afterText: The text after continuation
    ///   - data: Optional Data payload (e.g., encoded annotation data)
    /// - Throws: BlazeDBError if the save operation fails
    ///
    /// ## Example
    /// ```swift
    /// try db.saveContinuationSample(
    ///     beforeText: "Hello",
    ///     afterText: "Hello, world!",
    ///     data: optionalAnnotationData
    /// )
    /// ```
    public func saveContinuationSample(beforeText: String, afterText: String, data: Data? = nil) throws {
        // Generate deterministic UUID from beforeText hash
        let sampleID = deterministicUUID(from: beforeText)
        
        // Encode the pair as Data using BlazeBinary encoding
        // Store as a simple structure: beforeText + separator + afterText
        // Using UTF-8 encoding with a null separator for safety
        let beforeData = beforeText.data(using: .utf8) ?? Data()
        let afterData = afterText.data(using: .utf8) ?? Data()
        
        // Create a simple binary format: [beforeLength: UInt32][beforeData][afterLength: UInt32][afterData]
        var encodedData = Data()
        let beforeLength = UInt32(beforeData.count)
        let afterLength = UInt32(afterData.count)
        encodedData.append(contentsOf: withUnsafeBytes(of: beforeLength) { Data($0) })
        encodedData.append(beforeData)
        encodedData.append(contentsOf: withUnsafeBytes(of: afterLength) { Data($0) })
        encodedData.append(afterData)
        
        var recordFields: [String: BlazeDocumentField] = [
            "type": .string("continuation_sample"),
            "data": .data(encodedData),
            "beforeText": .string(beforeText),  // Store as string for querying
            "afterText": .string(afterText),    // Store as string for querying
            "createdAt": .date(Date())
        ]
        
        // Add optional Data payload if provided
        if let payloadData = data {
            recordFields["payload"] = .data(payloadData)
        }
        
        let record = BlazeDataRecord(recordFields)
        
        // Upsert to handle both insert and update cases (same beforeText = same ID)
        _ = try upsert(id: sampleID, data: record)
        BlazeLogger.debug("Saved continuation sample: '\(beforeText.prefix(20))...' -> '\(afterText.prefix(20))...'\(data != nil ? " (with payload)" : "")")
    }
    
    /// Load all continuation training samples.
    ///
    /// Returns all training pairs in insertion order (by createdAt timestamp, oldest → newest).
    ///
    /// - Returns: Array of `AIContinuationSample` objects, ordered by creation time (oldest first)
    /// - Throws: BlazeDBError if the load operation fails
    ///
    /// ## Example
    /// ```swift
    /// let samples = try db.loadContinuationSamples()
    /// for sample in samples {
    ///     print("\(sample.beforeText) -> \(sample.afterText) (created: \(sample.createdAt))")
    /// }
    /// ```
    public func loadContinuationSamples() throws -> [AIContinuationSample] {
        let results = try query()
            .where("type", equals: .string("continuation_sample"))
            .orderBy("createdAt", descending: false)  // Oldest first (insertion order)
            .execute()
            .records
        
        var samples: [AIContinuationSample] = []
        for record in results {
            guard let beforeText = record.storage["beforeText"]?.stringValue,
                  let afterText = record.storage["afterText"]?.stringValue,
                  let createdAt = record.storage["createdAt"]?.dateValue else {
                continue
            }
            samples.append(AIContinuationSample(
                beforeText: beforeText,
                afterText: afterText,
                createdAt: createdAt
            ))
        }
        
        BlazeLogger.debug("Loaded \(samples.count) continuation sample(s)")
        return samples
    }
}

