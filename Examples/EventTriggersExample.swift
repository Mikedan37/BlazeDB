//
//  EventTriggersExample.swift
//  BlazeDB Examples
//
//  Event triggers for automatic data processing
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB

/// Example: Auto-generate fields on insert
func eventTriggersExample() throws {
    let db = try BlazeDBClient(name: "Triggers", password: "test123")
    
    // Trigger: Auto-generate slug from title
    db.onInsert { record, modified, ctx in
        if let title = record.string("title"),
           record.string("slug") == nil {
            let slug = title.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
            
            // Update record with generated slug
            modified?["slug"] = .string(slug)
            print("✅ Auto-generated slug: \(slug)")
        }
    }
    
    // Insert record (trigger fires automatically!)
    let id = try db.insert(BlazeDataRecord([
        "title": .string("Hello World"),
        "content": .string("Some content")
    ]))
    
    // Slug was auto-generated
    let record = try db.fetch(id: id)
    print("Slug: \(record?.string("slug") ?? "none")")
    // Output: "Slug: hello-world"
}

/// Example: Auto-maintain indexes
func triggerIndexMaintenanceExample() throws {
    let db = try BlazeDBClient(name: "TriggerIndexes", password: "test123")
    
    // Enable spatial index
    try db.enableSpatialIndex(latField: "latitude", lonField: "longitude")
    
    // Trigger: Rebuild spatial index when location changes
    db.onUpdate { oldRecord, newRecord, modified, ctx in
        let oldLat = oldRecord.double("latitude")
        let newLat = newRecord.double("latitude")
        let oldLon = oldRecord.double("longitude")
        let newLon = newRecord.double("longitude")
        
        if oldLat != newLat || oldLon != newLon {
            // Location changed - rebuild index
            try? ctx.rebuildSpatialIndex()
            print("✅ Spatial index rebuilt after location update")
        }
    }
    
    // Insert location
    let id = try db.insert(BlazeDataRecord([
        "name": .string("Location 1"),
        "latitude": .double(37.7749),
        "longitude": .double(-122.4194)
    ]))
    
    // Update location (trigger fires!)
    try db.update(id: id, with: [
        "latitude": .double(37.8044),
        "longitude": .double(-122.2711)
    ])
    // Output: "✅ Spatial index rebuilt after location update"
}

/// Example: Auto-logging
func triggerLoggingExample() throws {
    let db = try BlazeDBClient(name: "TriggerLogging", password: "test123")
    
    // Trigger: Log all inserts to audit log
    db.onInsert { record, modified, ctx in
        let auditLog = BlazeDataRecord([
            "action": .string("insert"),
            "recordId": .uuid(record.id),
            "timestamp": .date(Date()),
            "data": .dictionary(record.storage)
        ])
        
        // Insert into audit log (separate collection)
        // Note: In production, you'd use a separate collection
        print("📝 Audit log: Inserted record \(record.id)")
    }
    
    // Insert record (automatically logged!)
    _ = try db.insert(BlazeDataRecord([
        "name": .string("Test"),
        "value": .int(42)
    ]))
    // Output: "📝 Audit log: Inserted record <UUID>"
}

/// Example: Auto-enrichment with AI
func triggerAIEnrichmentExample() throws {
    let db = try BlazeDBClient(name: "TriggerAI", password: "test123")
    
    // Enable vector index for embeddings
    try db.enableVectorIndex(fieldName: "embedding")
    
    // Trigger: Generate embedding for text fields
    db.onInsert { record, modified, ctx in
        if let text = record.string("notes"),
           record.storage["embedding"] == nil {
            // In production, you'd call an embedding API here
            // For demo, generate a simple embedding
            let embedding: VectorEmbedding = (0..<128).map { _ in Float.random(in: -1...1) }
            let embeddingData = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
            
            modified?["embedding"] = .data(embeddingData)
            print("✅ Auto-generated embedding for notes")
        }
    }
    
    // Insert record (embedding auto-generated!)
    _ = try db.insert(BlazeDataRecord([
        "title": .string("Journal Entry"),
        "notes": .string("Had a great day today!")
    ]))
    // Output: "✅ Auto-generated embedding for notes"
}

