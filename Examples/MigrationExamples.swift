//
//  MigrationExamples.swift
//  BlazeDB Examples
//
//  Complete examples for migrating from SQLite and Core Data to BlazeDB
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB

#if canImport(CoreData)
import CoreData
#endif

// MARK: - Progress Monitor Examples

class ProgressMonitorExamples {
    
    /// Example 1: Basic progress monitoring
    static func basicProgressMonitoring() throws {
        let monitor = MigrationProgressMonitor()
        
        // Start migration in background
        Task {
            try SQLiteMigrator.importFromSQLite(
                source: URL(fileURLWithPath: "/path/to/app.sqlite"),
                destination: URL(fileURLWithPath: "/path/to/app.blazedb"),
                password: "password",
                progressMonitor: monitor
            )
        }
        
        // Poll progress
        while true {
            let progress = monitor.getProgress()
            print("Progress: \(String(format: "%.1f", progress.percentage))%")
            print("Status: \(progress.status.rawValue)")
            print("Records: \(progress.recordsProcessed)/\(progress.recordsTotal ?? 0)")
            
            if progress.status == .completed || progress.status == .failed {
                break
            }
            
            Thread.sleep(forTimeInterval: 0.5)  // Poll every 0.5 seconds
        }
    }
    
    /// Example 2: SwiftUI progress view
    static func swiftUIProgressView() {
        // This would be in a SwiftUI View
        /*
        struct MigrationProgressView: View {
            @StateObject private var monitor = MigrationProgressMonitor()
            @State private var progress: MigrationProgress?
            
            var body: some View {
                VStack {
                    if let progress = progress {
                        Text("Status: \(progress.status.rawValue)")
                        Text("Table: \(progress.currentTable ?? "none")")
                        Text("\(String(format: "%.1f", progress.percentage))%")
                        ProgressView(value: progress.percentage / 100.0)
                        
                        if let remaining = progress.estimatedTimeRemaining {
                            Text("Time remaining: \(String(format: "%.0f", remaining))s")
                        }
                    }
                }
                .onAppear {
                    // Poll every 0.1 seconds
                    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                        progress = monitor.getProgress()
                    }
                }
            }
        }
        */
    }
    
    /// Example 3: Observer pattern
    static func observerPattern() {
        let monitor = MigrationProgressMonitor()
        
        // Subscribe to updates
        let observerID = monitor.addObserver { progress in
            print("Progress update: \(progress.percentage)%")
            // Update UI, send notifications, etc.
        }
        
        // Start migration
        Task {
            try SQLiteMigrator.importFromSQLite(
                source: URL(fileURLWithPath: "/path/to/app.sqlite"),
                destination: URL(fileURLWithPath: "/path/to/app.blazedb"),
                password: "password",
                progressMonitor: monitor
            )
        }
        
        // Later, remove observer
        // monitor.removeObserver(observerID)
    }
}

// MARK: - SQL Command Migration Examples

class SQLMigrationExamples {
    
    /// Example 1: Basic SQL command migration
    static func basicSQLMigration() throws {
        let sqlCommands = [
            "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT)",
            "INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com')",
            "INSERT INTO users (name, email) VALUES ('Bob', 'bob@example.com')"
        ]
        
        try SQLMigrator.importFromSQL(
            sqlCommands: sqlCommands,
            destination: URL(fileURLWithPath: "/path/to/app.blazedb"),
            password: "secure-password"
        )
        
        print("✅ SQL migration complete!")
    }
    
    /// Example 2: Migration from SQL file
    static func sqlFileMigration() throws {
        let sqlFile = URL(fileURLWithPath: "/path/to/schema.sql")
        
        try SQLMigrator.importFromSQLFile(
            sqlFileURL: sqlFile,
            destination: URL(fileURLWithPath: "/path/to/app.blazedb"),
            password: "secure-password"
        )
    }
    
    /// Example 3: Complex SQL migration with multiple tables
    static func complexSQLMigration() throws {
        let sqlCommands = [
            // Create tables
            "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT)",
            "CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER, title TEXT, content TEXT)",
            "CREATE TABLE comments (id INTEGER PRIMARY KEY, post_id INTEGER, user_id INTEGER, text TEXT)",
            
            // Insert data
            "INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com')",
            "INSERT INTO users (name, email) VALUES ('Bob', 'bob@example.com')",
            "INSERT INTO posts (user_id, title, content) VALUES (1, 'Hello', 'World')",
            "INSERT INTO comments (post_id, user_id, text) VALUES (1, 2, 'Nice post!')"
        ]
        
        try SQLMigrator.importFromSQL(
            sqlCommands: sqlCommands,
            destination: URL(fileURLWithPath: "/path/to/app.blazedb"),
            password: "secure-password",
            progressHandler: { current, total in
                print("Progress: \(current)/\(total) tables")
            }
        )
    }
}

// MARK: - SQLite Migration Examples

class SQLiteMigrationExamples {
    
    /// Example 1: Basic SQLite migration
    static func basicMigration() throws {
        let sqliteURL = URL(fileURLWithPath: "/path/to/app.sqlite")
        let blazeDBURL = URL(fileURLWithPath: "/path/to/app.blazedb")
        
        try SQLiteMigrator.importFromSQLite(
            source: sqliteURL,
            destination: blazeDBURL,
            password: "secure-password"
        )
        
        print("✅ Migration complete!")
    }
    
    /// Example 2: Migration with progress tracking
    static func migrationWithProgress() throws {
        let sqliteURL = URL(fileURLWithPath: "/path/to/app.sqlite")
        let blazeDBURL = URL(fileURLWithPath: "/path/to/app.blazedb")
        
        try SQLiteMigrator.importFromSQLite(
            source: sqliteURL,
            destination: blazeDBURL,
            password: "secure-password",
            progressHandler: { current, total in
                let percent = Double(current) / Double(total) * 100
                print("Progress: \(String(format: "%.1f", percent))% (\(current)/\(total) tables)")
            }
        )
    }
    
    /// Example 3: Selective table migration
    static func selectiveTableMigration() throws {
        let sqliteURL = URL(fileURLWithPath: "/path/to/app.sqlite")
        let blazeDBURL = URL(fileURLWithPath: "/path/to/app.blazedb")
        
        // Only migrate specific tables
        try SQLiteMigrator.importFromSQLite(
            source: sqliteURL,
            destination: blazeDBURL,
            password: "secure-password",
            tables: ["users", "posts", "comments"]
        )
    }
    
    /// Example 4: Complete migration workflow with verification
    static func completeMigrationWorkflow() throws {
        // Step 1: Backup source
        let sourceURL = URL(fileURLWithPath: "/path/to/app.sqlite")
        let backupURL = sourceURL.appendingPathExtension("backup")
        try FileManager.default.copyItem(at: sourceURL, to: backupURL)
        print("✅ Source backed up")
        
        // Step 2: Migrate
        let destURL = URL(fileURLWithPath: "/path/to/app.blazedb")
        try SQLiteMigrator.importFromSQLite(
            source: sourceURL,
            destination: destURL,
            password: "secure-password",
            progressHandler: { current, total in
                print("Migrating table \(current)/\(total)...")
            }
        )
        print("✅ Migration complete")
        
        // Step 3: Verify
        let db = try BlazeDBClient(
            name: "MigratedDB",
            fileURL: destURL,
            password: "secure-password"
        )
        let count = try db.count()
        print("✅ Verification: \(count) records migrated")
        
        // Step 4: Create indexes
        try db.collection.createIndex(on: "email")
        try db.collection.createIndex(on: "createdAt")
        print("✅ Indexes created")
    }
}

// MARK: - Core Data Migration Examples

#if canImport(CoreData)
class CoreDataMigrationExamples {
    
    /// Example 1: Basic Core Data migration
    static func basicMigration() throws {
        let container = NSPersistentContainer(name: "MyApp")
        container.loadPersistentStores { _, error in
            if let error = error {
                // Log error instead of crashing
                print("❌ Failed to load Core Data store: \(error)")
                // In production, handle this gracefully - show error to user, use fallback, etc.
            }
        }
        
        let blazeDBURL = URL(fileURLWithPath: "/path/to/app.blazedb")
        
        try CoreDataMigrator.importFromCoreData(
            container: container,
            destination: blazeDBURL,
            password: "secure-password"
        )
        
        print("✅ Migration complete!")
    }
    
    /// Example 2: Migration with progress tracking
    static func migrationWithProgress() throws {
        let container = NSPersistentContainer(name: "MyApp")
        container.loadPersistentStores { _, error in
            if let error = error {
                // Log error instead of crashing
                print("❌ Failed to load Core Data store: \(error)")
                // In production, handle this gracefully - show error to user, use fallback, etc.
            }
        }
        
        let blazeDBURL = URL(fileURLWithPath: "/path/to/app.blazedb")
        
        try CoreDataMigrator.importFromCoreData(
            container: container,
            destination: blazeDBURL,
            password: "secure-password",
            progressHandler: { current, total in
                let percent = Double(current) / Double(total) * 100
                print("Progress: \(String(format: "%.1f", percent))% (\(current)/\(total) entities)")
            }
        )
    }
    
    /// Example 3: Selective entity migration
    static func selectiveEntityMigration() throws {
        let container = NSPersistentContainer(name: "MyApp")
        container.loadPersistentStores { _, error in
            if let error = error {
                // Log error instead of crashing
                print("❌ Failed to load Core Data store: \(error)")
                // In production, handle this gracefully - show error to user, use fallback, etc.
            }
        }
        
        let blazeDBURL = URL(fileURLWithPath: "/path/to/app.blazedb")
        
        // Only migrate specific entities
        try CoreDataMigrator.importFromCoreData(
            container: container,
            destination: blazeDBURL,
            password: "secure-password",
            entities: ["User", "Post", "Comment"]
        )
    }
}
#endif

// MARK: - Manual Migration Examples

class ManualMigrationExamples {
    
    /// Example 1: Export from source and import to BlazeDB
    static func exportImportMigration() async throws {
        // Step 1: Export from source (example: JSON export)
        let sourceData = try Data(contentsOf: URL(fileURLWithPath: "/path/to/export.json"))
        
        // Step 2: Create BlazeDB
        let db = try BlazeDBClient(
            name: "MigratedDB",
            fileURL: URL(fileURLWithPath: "/path/to/app.blazedb"),
            password: "secure-password"
        )
        
        // Step 3: Import
        let stats = try await db.import(
            from: sourceData,
            format: .json,
            mode: .append
        )
        
        print("✅ Imported: \(stats.recordsImported) records")
        print("   Skipped: \(stats.recordsSkipped)")
        print("   Updated: \(stats.recordsUpdated)")
    }
    
    /// Example 2: Batch migration for large datasets
    static func batchMigration() async throws {
        let db = try BlazeDBClient(
            name: "MigratedDB",
            fileURL: URL(fileURLWithPath: "/path/to/app.blazedb"),
            password: "secure-password"
        )
        
        // Process in batches of 1000
        let batchSize = 1000
        var offset = 0
        var totalImported = 0
        
        while true {
            // Fetch batch from source
            let batch = try fetchBatchFromSource(offset: offset, limit: batchSize)
            
            if batch.isEmpty {
                break  // No more data
            }
            
            // Insert batch
            let ids = try db.insertMany(batch)
            totalImported += ids.count
            
            print("Imported batch: \(ids.count) records (total: \(totalImported))")
            
            offset += batchSize
        }
        
        print("✅ Batch migration complete: \(totalImported) records")
    }
    
    /// Helper: Fetch batch from source (implement based on your source)
    private static func fetchBatchFromSource(offset: Int, limit: Int) throws -> [BlazeDataRecord] {
        // Implement based on your source database
        // This is a placeholder
        return []
    }
}

// MARK: - Post-Migration Examples

class PostMigrationExamples {
    
    /// Example 1: Verify migration
    static func verifyMigration() throws {
        let db = try BlazeDBClient(
            name: "MigratedDB",
            fileURL: URL(fileURLWithPath: "/path/to/app.blazedb"),
            password: "secure-password"
        )
        
        // Check record count
        let count = try db.count()
        print("Total records: \(count)")
        
        // Sample records
        let sample = try db.fetchAll().prefix(5)
        for (index, record) in sample.enumerated() {
            print("Record \(index + 1):")
            for (key, value) in record.storage {
                print("  \(key): \(value)")
            }
        }
    }
    
    /// Example 2: Create indexes after migration
    static func createIndexes() throws {
        let db = try BlazeDBClient(
            name: "MigratedDB",
            fileURL: URL(fileURLWithPath: "/path/to/app.blazedb"),
            password: "secure-password"
        )
        
        // Create indexes for commonly queried fields
        try db.collection.createIndex(on: "email")
        try db.collection.createIndex(on: "createdAt")
        try db.collection.createIndex(on: "status")
        try db.collection.createIndex(on: "userId")
        
        print("✅ Indexes created")
    }
    
    /// Example 3: Data validation
    static func validateData() throws {
        let db = try BlazeDBClient(
            name: "MigratedDB",
            fileURL: URL(fileURLWithPath: "/path/to/app.blazedb"),
            password: "secure-password"
        )
        
        // Check for required fields
        let allRecords = try db.fetchAll()
        var missingFields: [String] = []
        
        for record in allRecords {
            if record.storage["id"] == nil {
                missingFields.append("id")
            }
            if record.storage["createdAt"] == nil {
                missingFields.append("createdAt")
            }
        }
        
        if !missingFields.isEmpty {
            print("⚠️ Missing fields: \(missingFields.joined(separator: ", "))")
        } else {
            print("✅ All records have required fields")
        }
    }
}

// MARK: - Error Handling Examples

class MigrationErrorHandling {
    
    /// Example: Robust migration with error handling
    static func robustMigration() {
        do {
            let sqliteURL = URL(fileURLWithPath: "/path/to/app.sqlite")
            let blazeDBURL = URL(fileURLWithPath: "/path/to/app.blazedb")
            
            try SQLiteMigrator.importFromSQLite(
                source: sqliteURL,
                destination: blazeDBURL,
                password: "secure-password"
            )
            
            print("✅ Migration successful")
            
        } catch MigrationError.sqliteError(let message) {
            print("❌ SQLite error: \(message)")
            // Handle SQLite-specific errors
        } catch MigrationError.blazeDBError(let message) {
            print("❌ BlazeDB error: \(message)")
            // Handle BlazeDB-specific errors
        } catch MigrationError.invalidData(let message) {
            print("❌ Invalid data: \(message)")
            // Handle data validation errors
        } catch {
            print("❌ Unexpected error: \(error)")
            // Handle other errors
        }
    }
}

