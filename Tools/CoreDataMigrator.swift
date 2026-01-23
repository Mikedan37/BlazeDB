//
//  CoreDataMigrator.swift
//  BlazeDB Migration Tools
//
//  Imports data from Core Data into BlazeDB
//

import Foundation
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
    /// - Throws: Error if migration fails
    ///
    /// Example:
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
    ///     print("Progress: \(current)/\(total)")
    /// }
    /// ```
    public static func importFromCoreData(
        container: NSPersistentContainer,
        destination: URL,
        password: String,
        entities: [String]? = nil,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) throws {
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
        
        // Create BlazeDB
        guard let blazeDB = BlazeDBClient(name: "Migration", at: destination, password: password) else {
            throw MigrationError.blazeDBError("Failed to initialize BlazeDB")
        }
        
        // Import each entity
        var totalRecords = 0
        for (index, entity) in entitiesToImport.enumerated() {
            let records = try importEntity(entity, from: context, into: blazeDB)
            totalRecords += records
            progressHandler?(index + 1, entitiesToImport.count)
        }
        
        // Persist to disk
        try blazeDB.persist()
        
        print("✅ Migration complete: \(totalRecords) records from \(entitiesToImport.count) entities")
    }
    
    // MARK: - Private Helpers
    
    private static func importEntity(_ entity: NSEntityDescription, from context: NSManagedObjectContext, into blazeDB: BlazeDBClient) throws -> Int {
        guard let entityName = entity.name else {
            throw MigrationError.coreDataError("Entity has no name")
        }
        
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
        
        let objects = try context.fetch(fetchRequest)
        var records: [BlazeDataRecord] = []
        
        for object in objects {
            var storage: [String: BlazeDocumentField] = [:]
            storage["_entity"] = .string(entityName)  // Track original entity name
            
            // Convert each attribute
            for (attributeName, attribute) in entity.attributesByName {
                guard let value = object.value(forKey: attributeName) else { continue }
                
                switch attribute.attributeType {
                case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
                    if let intValue = value as? Int {
                        storage[attributeName] = .int(intValue)
                    }
                    
                case .doubleAttributeType, .floatAttributeType, .decimalAttributeType:
                    if let doubleValue = value as? Double {
                        storage[attributeName] = .double(doubleValue)
                    } else if let decimal = value as? NSDecimalNumber {
                        storage[attributeName] = .double(decimal.doubleValue)
                    }
                    
                case .stringAttributeType:
                    if let stringValue = value as? String {
                        storage[attributeName] = .string(stringValue)
                    }
                    
                case .booleanAttributeType:
                    if let boolValue = value as? Bool {
                        storage[attributeName] = .bool(boolValue)
                    }
                    
                case .dateAttributeType:
                    if let dateValue = value as? Date {
                        storage[attributeName] = .date(dateValue)
                    }
                    
                case .binaryDataAttributeType:
                    if let dataValue = value as? Data {
                        storage[attributeName] = .data(dataValue)
                    }
                    
                case .UUIDAttributeType:
                    if let uuidValue = value as? UUID {
                        storage[attributeName] = .uuid(uuidValue)
                    }
                    
                case .transformableAttributeType:
                    // Try to convert to JSON
                    if let jsonData = try? JSONSerialization.data(withJSONObject: value),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        storage[attributeName] = .string(jsonString)
                    }
                    
                default:
                    // Convert to string as fallback
                    storage[attributeName] = .string(String(describing: value))
                }
            }
            
            // Handle relationships (store as IDs or arrays of IDs)
            for (relationshipName, relationship) in entity.relationshipsByName {
                guard let relatedObject = object.value(forKey: relationshipName) else { continue }
                
                if relationship.isToMany {
                    // To-many relationship: store as array of IDs
                    if let relatedSet = relatedObject as? Set<NSManagedObject> {
                        let ids = relatedSet.compactMap { $0.objectID.uriRepresentation().absoluteString }
                        storage[relationshipName] = .array(ids.map { .string($0) })
                    }
                } else {
                    // To-one relationship: store as single ID
                    if let related = relatedObject as? NSManagedObject {
                        let id = related.objectID.uriRepresentation().absoluteString
                        storage[relationshipName] = .string(id)
                    }
                }
            }
            
            records.append(BlazeDataRecord(storage))
        }
        
        // Batch insert for performance
        if !records.isEmpty {
            _ = try blazeDB.insertMany(records)
            print("✅ Imported \(records.count) records from entity '\(entityName)'")
        }
        
        return records.count
    }
}

