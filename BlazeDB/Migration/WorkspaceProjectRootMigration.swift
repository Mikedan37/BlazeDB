//
//  WorkspaceProjectRootMigration.swift
//  BlazeDB
//
//  Migration to add projectRoot field to Workspace records
//  Defaults projectRoot to the previous shared workspace path for existing records
//
//  Created by Auto on 2025-11-27.
//

import Foundation

/// Migration helper to add projectRoot field to Workspace records
public struct WorkspaceProjectRootMigration {
    
    /// Migrates all Workspace records to include the projectRoot field
    ///
    /// This migration:
    /// 1. Finds all Workspace records (identified by a "type" or "kind" field, or by collection name)
    /// 2. Adds projectRoot field, defaulting to the existing shared workspace path if available
    /// 3. Updates the records in place
    ///
    /// - Parameters:
    ///   - client: The BlazeDBClient instance
    ///   - workspaceTypeField: Field name that identifies Workspace records (default: "type")
    ///   - workspaceTypeValue: Value that identifies Workspace records (default: "workspace")
    ///   - sharedPathField: Field name for the existing shared workspace path (default: "sharedPath" or "path")
    ///   - defaultProjectRoot: Default value if no shared path exists (default: "")
    /// - Throws: BlazeDBError if migration fails
    ///
    /// ## Example
    /// ```swift
    /// let db = try BlazeDBClient(name: "AgentCore", fileURL: dbURL, password: "password")
    /// try WorkspaceProjectRootMigration.migrate(
    ///     client: db,
    ///     workspaceTypeField: "type",
    ///     workspaceTypeValue: "workspace"
    /// )
    /// ```
    public static func migrate(
        client: BlazeDBClient,
        workspaceTypeField: String = "type",
        workspaceTypeValue: String = "workspace",
        sharedPathField: String? = nil, // Will try "sharedPath", "path", "workspacePath"
        defaultProjectRoot: String = ""
    ) throws {
        BlazeLogger.info("🔄 Starting Workspace projectRoot migration...")
        
        // Fetch all records
        let allRecords = try client.fetchAll()
        
        // Find workspace records
        var workspaceRecords: [(UUID, BlazeDataRecord)] = []
        for record in allRecords {
            // Check if this is a workspace record
            let isWorkspace: Bool
            if let typeValue = record.storage[workspaceTypeField]?.stringValue {
                isWorkspace = typeValue.lowercased() == workspaceTypeValue.lowercased()
            } else if let kindValue = record.storage["kind"]?.stringValue {
                isWorkspace = kindValue.lowercased() == workspaceTypeValue.lowercased()
            } else {
                // If no type field, check if record has workspace-like fields
                isWorkspace = record.storage["workspaceId"] != nil || 
                             record.storage["workspaceName"] != nil ||
                             record.storage["sharedPath"] != nil
            }
            
            if isWorkspace {
                if let id = record.storage["id"]?.uuidValue {
                    workspaceRecords.append((id, record))
                }
            }
        }
        
        BlazeLogger.info("📋 Found \(workspaceRecords.count) Workspace records to migrate")
        
        if workspaceRecords.isEmpty {
            BlazeLogger.info("✅ No Workspace records found - migration complete")
            return
        }
        
        // Determine the shared path field name
        let pathFieldName: String
        if let specified = sharedPathField {
            pathFieldName = specified
        } else {
            // Try common field names
            let candidateFields = ["sharedPath", "path", "workspacePath", "sharedWorkspacePath"]
            pathFieldName = candidateFields.first { field in
                workspaceRecords.contains { $0.1.storage[field] != nil }
            } ?? "sharedPath"
        }
        
        // Migrate each workspace record
        var migratedCount = 0
        var skippedCount = 0
        
        try client.beginTransaction()
        
        do {
            for (id, record) in workspaceRecords {
                // Check if projectRoot already exists
                if record.storage["projectRoot"] != nil {
                    BlazeLogger.debug("⏭️  Workspace \(id.uuidString.prefix(8)) already has projectRoot - skipping")
                    skippedCount += 1
                    continue
                }
                
                // Get the shared path value to use as default
                let projectRootValue: String
                if let sharedPath = record.storage[pathFieldName]?.stringValue, !sharedPath.isEmpty {
                    projectRootValue = sharedPath
                    BlazeLogger.debug("📝 Using shared path '\(sharedPath)' as projectRoot for workspace \(id.uuidString.prefix(8))")
                } else {
                    projectRootValue = defaultProjectRoot
                    BlazeLogger.debug("📝 Using default projectRoot '\(defaultProjectRoot)' for workspace \(id.uuidString.prefix(8))")
                }
                
                // Create updated record with projectRoot
                var updatedStorage = record.storage
                updatedStorage["projectRoot"] = .string(projectRootValue)
                let updatedRecord = BlazeDataRecord(updatedStorage)
                
                // Update the record
                try client.update(id: id, with: updatedRecord)
                migratedCount += 1
            }
            
            // Commit transaction
            try client.commitTransaction()
            
            BlazeLogger.info("✅ Migration complete: \(migratedCount) records migrated, \(skippedCount) skipped")
            
        } catch {
            // Rollback on error
            try? client.rollbackTransaction()
            BlazeLogger.error("❌ Migration failed: \(error)")
            throw error
        }
    }
    
    /// Check if migration is needed
    ///
    /// Returns true if any Workspace records are missing the projectRoot field
    ///
    /// - Parameters:
    ///   - client: The BlazeDBClient instance
    ///   - workspaceTypeField: Field name that identifies Workspace records
    ///   - workspaceTypeValue: Value that identifies Workspace records
    /// - Returns: True if migration is needed, false otherwise
    public static func needsMigration(
        client: BlazeDBClient,
        workspaceTypeField: String = "type",
        workspaceTypeValue: String = "workspace"
    ) throws -> Bool {
        let allRecords = try client.fetchAll()
        
        for record in allRecords {
            // Check if this is a workspace record
            let isWorkspace: Bool
            if let typeValue = record.storage[workspaceTypeField]?.stringValue {
                isWorkspace = typeValue.lowercased() == workspaceTypeValue.lowercased()
            } else if let kindValue = record.storage["kind"]?.stringValue {
                isWorkspace = kindValue.lowercased() == workspaceTypeValue.lowercased()
            } else {
                isWorkspace = record.storage["workspaceId"] != nil || 
                             record.storage["workspaceName"] != nil ||
                             record.storage["sharedPath"] != nil
            }
            
            if isWorkspace && record.storage["projectRoot"] == nil {
                return true
            }
        }
        
        return false
    }
}

