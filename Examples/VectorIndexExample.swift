//
//  VectorIndexExample.swift
//  BlazeDB Examples
//
//  Vector similarity search with automatic indexing
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB

/// Example: Semantic search with vector embeddings
func vectorIndexExample() throws {
    // Initialize database
    let db = try BlazeDBClient(name: "VectorSearch", password: "test123")
    
    // Enable vector index for semantic search
    try db.enableVectorIndex(fieldName: "embedding")
    
    // Insert records with vector embeddings
    // In production, you'd generate these with an embedding model (OpenAI, etc.)
    let records = [
        ("happy", [0.8, 0.2, 0.1, 0.9]),
        ("sad", [0.1, 0.9, 0.8, 0.2]),
        ("excited", [0.9, 0.1, 0.2, 0.8]),
        ("calm", [0.2, 0.1, 0.9, 0.8]),
        ("anxious", [0.1, 0.8, 0.9, 0.2])
    ]
    
    for (emotion, vector) in records {
        let vectorData = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        _ = try db.insert(BlazeDataRecord([
            "emotion": .string(emotion),
            "embedding": .data(vectorData)
        ]))
    }
    
    // Query: Find emotions similar to "happy"
    let happyVector: VectorEmbedding = [0.8, 0.2, 0.1, 0.9]
    let similar = try db.query()
        .vectorNearest(field: "embedding", to: happyVector, limit: 3, threshold: 0.5)
        .execute()
    
    print("Emotions similar to 'happy':")
    for record in similar.records {
        print("  - \(record.string("emotion") ?? "unknown")")
    }
    
    // Performance: Vector index makes this O(log n) instead of O(n)
    print("\n✅ Vector index enabled - queries are ultra-fast!")
}

/// Example: Vector + Spatial hybrid query
func vectorSpatialHybridExample() throws {
    let db = try BlazeDBClient(name: "HybridSearch", password: "test123")
    
    // Enable both indexes
    try db.enableSpatialIndex(latField: "latitude", lonField: "longitude")
    try db.enableVectorIndex(fieldName: "moodEmbedding")
    
    // Insert location data with mood embeddings
    let locations = [
        ("SF", 37.7749, -122.4194, [0.8, 0.2, 0.1]),
        ("Oakland", 37.8044, -122.2711, [0.7, 0.3, 0.2]),
        ("Berkeley", 37.8715, -122.2730, [0.9, 0.1, 0.1])
    ]
    
    for (name, lat, lon, mood) in locations {
        let moodData = mood.withUnsafeBufferPointer { Data(buffer: $0) }
        _ = try db.insert(BlazeDataRecord([
            "name": .string(name),
            "latitude": .double(lat),
            "longitude": .double(lon),
            "moodEmbedding": .data(moodData)
        ]))
    }
    
    // Query: Find locations with similar mood AND within 10km
    let queryMood: VectorEmbedding = [0.8, 0.2, 0.1]
    let results = try db.query()
        .vectorAndSpatial(
            vectorField: "moodEmbedding",
            vectorEmbedding: queryMood,
            latitude: 37.7749,
            longitude: -122.4194,
            radiusMeters: 10_000
        )
        .execute()
    
    print("Locations with similar mood within 10km:")
    for record in results.records {
        print("  - \(record.string("name") ?? "unknown")")
    }
}

