//
//  main.swift
//  VaporServer
//
//  Example Vapor server with embedded BlazeDB
//  Demonstrates proper lifecycle, health endpoints, and signal handling
//
//  Created by Auto on 1/XX/25.
//

import Vapor
import BlazeDB
import Foundation

// MARK: - Application Setup

func configure(_ app: Application) throws {
    // Open database (one per server process)
    let db = try BlazeDBClient.openForDaemon(
        name: "vapor-server",
        password: ProcessInfo.processInfo.environment["DB_PASSWORD"] ?? "default-password-change-in-production"
    )
    
    // Store database in application storage
    app.storage["blazedb"] = db
    
    // Register routes
    try routes(app)
    
    // Setup graceful shutdown
    app.lifecycle.use(DatabaseLifecycle(db: db))
}

// MARK: - Routes

func routes(_ app: Application) throws {
    // Health endpoint
    app.get("db", "health") { req -> HealthResponse in
        guard let db = req.application.storage["blazedb"] as? BlazeDBClient else {
            throw Abort(.internalServerError, reason: "Database not initialized")
        }
        
        do {
            let health = try db.health()
            return HealthResponse(
                status: health.status.rawValue,
                reasons: health.reasons,
                suggestedActions: health.suggestedActions
            )
        } catch {
            throw Abort(.internalServerError, reason: "Health check failed: \(error.localizedDescription)")
        }
    }
    
    // Stats endpoint
    app.get("db", "stats") { req -> StatsResponse in
        guard let db = req.application.storage["blazedb"] as? BlazeDBClient else {
            throw Abort(.internalServerError, reason: "Database not initialized")
        }
        
        do {
            let stats = try db.stats()
            return StatsResponse(
                recordCount: stats.recordCount,
                pageCount: stats.pageCount,
                databaseSize: stats.databaseSize,
                walSize: stats.walSize,
                cacheHitRate: stats.cacheHitRate,
                indexCount: stats.indexCount
            )
        } catch {
            throw Abort(.internalServerError, reason: "Stats retrieval failed: \(error.localizedDescription)")
        }
    }
    
    // Dump endpoint (DEV ONLY - remove in production)
    #if DEBUG
    app.post("db", "dump") { req -> DumpResponse in
        guard let db = req.application.storage["blazedb"] as? BlazeDBClient else {
            throw Abort(.internalServerError, reason: "Database not initialized")
        }
        
        let dumpPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("dump-\(UUID().uuidString).blazedump")
        
        do {
            try db.export(to: dumpPath)
            return DumpResponse(
                success: true,
                path: dumpPath.path,
                message: "Database exported successfully"
            )
        } catch {
            throw Abort(.internalServerError, reason: "Export failed: \(error.localizedDescription)")
        }
    }
    #endif
    
    // Example CRUD endpoints
    app.get("users") { req -> [UserRecord] in
        guard let db = req.application.storage["blazedb"] as? BlazeDBClient else {
            throw Abort(.internalServerError, reason: "Database not initialized")
        }
        
        do {
            let records = try db.query()
                .where("active", equals: .bool(true))
                .execute()
                .records
            
            return records.map { UserRecord(from: $0) }
        } catch {
            throw Abort(.internalServerError, reason: "Query failed: \(error.localizedDescription)")
        }
    }
    
    app.post("users") { req -> UserRecord in
        guard let db = req.application.storage["blazedb"] as? BlazeDBClient else {
            throw Abort(.internalServerError, reason: "Database not initialized")
        }
        
        let userData = try req.content.decode(UserData.self)
        let record = BlazeDataRecord([
            "name": .string(userData.name),
            "email": .string(userData.email),
            "active": .bool(true),
            "createdAt": .date(Date())
        ])
        
        do {
            let id = try db.insert(record)
            return UserRecord(id: id, from: record)
        } catch BlazeDBError.databaseLocked {
            throw Abort(.serviceUnavailable, reason: "Database is locked by another process")
        } catch {
            throw Abort(.internalServerError, reason: "Insert failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Response Types

struct HealthResponse: Content {
    let status: String
    let reasons: [String]
    let suggestedActions: [String]
}

struct StatsResponse: Content {
    let recordCount: Int
    let pageCount: Int
    let databaseSize: Int64
    let walSize: Int64?
    let cacheHitRate: Double
    let indexCount: Int
}

struct DumpResponse: Content {
    let success: Bool
    let path: String
    let message: String
}

struct UserRecord: Content {
    let id: UUID
    let name: String
    let email: String
    let active: Bool
    let createdAt: Date
    
    init(id: UUID, from record: BlazeDataRecord) {
        self.id = id
        self.name = record.storage["name"]?.stringValue ?? ""
        self.email = record.storage["email"]?.stringValue ?? ""
        self.active = record.storage["active"]?.boolValue ?? false
        self.createdAt = record.storage["createdAt"]?.dateValue ?? Date()
    }
    
    init(from record: BlazeDataRecord) {
        self.id = record.storage["id"]?.uuidValue ?? UUID()
        self.name = record.storage["name"]?.stringValue ?? ""
        self.email = record.storage["email"]?.stringValue ?? ""
        self.active = record.storage["active"]?.boolValue ?? false
        self.createdAt = record.storage["createdAt"]?.dateValue ?? Date()
    }
}

struct UserData: Content {
    let name: String
    let email: String
}

// MARK: - Lifecycle Handler

final class DatabaseLifecycle: LifecycleHandler {
    let db: BlazeDBClient
    
    init(db: BlazeDBClient) {
        self.db = db
    }
    
    func willBoot(_ application: Application) throws {
        // Database is already open
        BlazeLogger.info("Vapor server starting with BlazeDB")
    }
    
    func shutdown(_ application: Application) {
        // Explicitly close database on shutdown
        do {
            try db.close()
            BlazeLogger.info("BlazeDB closed gracefully")
        } catch {
            BlazeLogger.error("Failed to close BlazeDB: \(error)")
        }
    }
}

// MARK: - Entry Point

@main
enum Entry {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        
        let app = Application(env)
        defer { app.shutdown() }
        
        try configure(app)
        try await app.execute()
    }
}
