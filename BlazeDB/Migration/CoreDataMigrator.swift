//
//  CoreDataMigrator.swift
//  BlazeDB
//
//  Core Data to BlazeDB migration tool
//  Integrated into main BlazeDB package
//
//  Created by Auto on 1/XX/25.
//

import Foundation

#if canImport(CoreData)
import CoreData

/// Tool for migrating data from Core Data to BlazeDB
public struct CoreDataMigrator {
    
    /// Import data from a Core Data persistent container into BlazeDB
    ///
    /// - Parameters:
    ///   - container: NSPersistentContainer with data to migrate
    ///   - destination: URL where BlazeDB file will be created
    ///   - password: Password for BlazeDB encryption
    ///   - entities: Optional array of entity names to import (nil = all entities)
    ///   - progressHandler: Optional callback with (current, total) progress
    /// - Throws: MigrationError if migration fails
    ///
    /// ## Example
    /// ```swift
    /// let container = NSPersistentContainer(name: "MyApp")
    /// container.loadPersistentStores { _, error in
    ///     if let error = error {
    ///         print("Failed to load Core Data stores: \(error)")
    ///         // Handle error appropriately - don't use fatalError in production
    ///         return
    ///     }
    /// }
    ///
    /// try CoreDataMigrator.importFromCoreData(
    ///     container: container,
    ///     destination: URL(fileURLWithPath: "/path/to/app.blazedb"),
    ///     password: "secure-password",
    ///     entities: ["User", "Post", "Comment"]
    /// ) { current, total in
    ///     // Progress updates via progressMonitor
    /// }
    /// ```
    public static func importFromCoreData(
        container: NSPersistentContainer,
        destination: URL,
        password: String,
        entities: [String]? = nil,
        progressHandler: ((Int, Int) -> Void)? = nil
        #if BLAZEDB_DISTRIBUTED
        , progressMonitor: MigrationProgressMonitor? = nil
        #else
        , progressMonitor: Any? = nil
        #endif
    ) throws {
        BlazeLogger.info("🔄 Starting Core Data migration to \(destination.path)")
        
        // Initialize progress monitor
        #if BLAZEDB_DISTRIBUTED
        progressMonitor?.reset()
        #endif
        
        let context = container.viewContext
        
        // Get list of entities
        let entitiesToImport: [NSEntityDescription]
        if let entityNames = entities {
            entitiesToImport = entityNames.compactMap { name in
                container.managedObjectModel.entitiesByName[name]
            }
        } else {
            entitiesToImport = Array(container.managedObjectModel.entities)
        }
        
        BlazeLogger.info("📋 Found \(entitiesToImport.count) entities to import: \(entitiesToImport.map { $0.name ?? "unknown" }.joined(separator: ", "))")
        
        // Count total records for progress tracking
        var totalRecordsCount: Int = 0
        for entity in entitiesToImport {
            guard let entityName = entity.name else { continue }
            let count = try getEntityRecordCount(entity: entity, from: context)
            totalRecordsCount += count
            BlazeLogger.debug("📊 Entity '\(entityName)': \(count) records")
        }
        
        BlazeLogger.info("📊 Total records to migrate: \(totalRecordsCount)")
        
        // Start progress monitor
        progressMonitor?.start(totalTables: entitiesToImport.count, recordsTotal: totalRecordsCount)
        
        // Create BlazeDB
        let blazeDB = try BlazeDBClient(
            name: "Migration",
            fileURL: destination,
            password: password
        )
        BlazeLogger.debug("✅ BlazeDB created at \(destination.path)")
        
        // Record telemetry for migration start (if enabled)
        #if !BLAZEDB_LINUX_CORE
        blazeDB.telemetry.record(
            operation: "migration.coredata.start",
            duration: 0,
            success: true,
            recordCount: totalRecordsCount
        )
        #endif
        
        // Import each entity
        var totalRecords = 0
        for (index, entity) in entitiesToImport.enumerated() {
            guard let entityName = entity.name else { continue }
            BlazeLogger.info("📥 Importing entity '\(entityName)' (\(index + 1)/\(entitiesToImport.count))...")
            #if BLAZEDB_DISTRIBUTED
            progressMonitor?.updateTable(entityName, index: index + 1, recordsProcessed: totalRecords)
            #endif
            
            let records = try importEntity(
                entity,
                from: context,
                into: blazeDB,
                progressMonitor: progressMonitor,
                baseRecordCount: totalRecords
            )
            totalRecords += records
            progressHandler?(index + 1, entitiesToImport.count)
            BlazeLogger.info("✅ Imported \(records) records from '\(entityName)' (total: \(totalRecords))")
        }
        
        // Persist to disk
        BlazeLogger.debug("💾 Persisting to disk...")
        #if BLAZEDB_DISTRIBUTED
        progressMonitor?.update(status: .creatingIndexes)
        #endif
        try blazeDB.persist()
        
        progressMonitor?.complete(recordsProcessed: totalRecords)
        
        // Record telemetry for migration completion
        #if !BLAZEDB_LINUX_CORE
        let migrationDuration = Date().timeIntervalSince(progressMonitor?.getProgress().startTime ?? Date())
        blazeDB.telemetry.record(
            operation: "migration.coredata.complete",
            duration: migrationDuration * 1000,  // Convert to milliseconds
            success: true,
            recordCount: totalRecords
        )
        #endif
        
        BlazeLogger.info("✅ Migration complete: \(totalRecords) records from \(entitiesToImport.count) entities")
    }
    
    // MARK: - Private Helpers
    
    private static func getEntityRecordCount(entity: NSEntityDescription, from context: NSManagedObjectContext) throws -> Int {
        guard let entityName = entity.name else { return 0 }
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
        fetchRequest.includesSubentities = false
        return try context.count(for: fetchRequest)
    }
    
    private static func importEntity(
        _ entity: NSEntityDescription,
        from context: NSManagedObjectContext,
        into blazeDB: BlazeDBClient
        #if BLAZEDB_DISTRIBUTED
        , progressMonitor: MigrationProgressMonitor? = nil
        #else
        , progressMonitor: Any? = nil
        #endif
        , baseRecordCount: Int = 0
    ) throws -> Int {
        guard let entityName = entity.name else {
            throw MigrationError.coreDataError("Entity has no name")
        }
        
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
        let objects = try context.fetch(fetchRequest)
        
        var records: [BlazeDataRecord] = []
        var nullValueCount = 0
        
        for object in objects {
            var document: [String: BlazeDocumentField] = [:]
            
            // Get all attributes
            for (name, attribute) in entity.attributesByName {
                let value = object.value(forKey: name)
                
                if value == nil {
                    nullValueCount += 1
                    continue  // Skip nil values
                }
                
                let field: BlazeDocumentField?
                switch attribute.attributeType {
                case .stringAttributeType:
                    guard let stringValue = value as? String else { continue }
                    field = .string(stringValue)
                case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
                    guard let intValue = value as? Int else { continue }
                    field = .int(intValue)
                case .doubleAttributeType, .floatAttributeType:
                    guard let doubleValue = value as? Double else { continue }
                    field = .double(doubleValue)
                case .booleanAttributeType:
                    guard let boolValue = value as? Bool else { continue }
                    field = .bool(boolValue)
                case .dateAttributeType:
                    guard let dateValue = value as? Date else { continue }
                    field = .date(dateValue)
                case .binaryDataAttributeType:
                    guard let dataValue = value as? Data else { continue }
                    field = .data(dataValue)
                case .UUIDAttributeType:
                    if let uuid = value as? UUID {
                        field = .uuid(uuid)
                    } else if let uuidString = value as? String, let uuid = UUID(uuidString: uuidString) {
                        field = .uuid(uuid)
                    } else {
                        continue
                    }
                default:
                    // Convert to string for unsupported types
                    field = .string(String(describing: value))
                }
                
                guard let field = field else { continue }
                document[name] = field
            }
            
            // Get relationships (optional, as references)
            for (name, _) in entity.relationshipsByName {
                if let relatedObject = object.value(forKey: name) as? NSManagedObject,
                   let relatedID = relatedObject.value(forKey: "id") as? UUID ?? relatedObject.objectID.uriRepresentation().absoluteString.data(using: .utf8).flatMap({ UUID(uuidString: String(data: $0, encoding: .utf8) ?? "") }) {
                    document[name] = .uuid(relatedID)
                }
            }
            
            // Convert to BlazeDataRecord
            let record = BlazeDataRecord(document)
            records.append(record)
        }
        
        // Batch insert for performance
        if !records.isEmpty {
            _ = try blazeDB.insertMany(records)
            #if BLAZEDB_DISTRIBUTED
            progressMonitor?.update(recordsProcessed: baseRecordCount + records.count)
            #endif
        }
        
        if nullValueCount > 0 {
            BlazeLogger.debug("⚠️ Skipped \(nullValueCount) nil values (BlazeDB uses missing fields instead of null)")
        }
        BlazeLogger.debug("✅ Entity '\(entityName)' complete: \(records.count) records")
        return records.count
    }
}

#else
// Fallback when Core Data is not available
public struct CoreDataMigrator {
    public static func importFromCoreData(
        container: Any,
        destination: URL,
        password: String,
        entities: [String]? = nil,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) throws {
        throw MigrationError.coreDataError("Core Data not available on this platform")
    }
}
#endif

