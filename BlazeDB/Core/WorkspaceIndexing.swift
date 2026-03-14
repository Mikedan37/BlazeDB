//
//  WorkspaceIndexing.swift
//  BlazeDB
//
//  Efficient indexing for multi-workspace agent workloads
//  Provides optimized indexes for workspace-related queries
//
//

import Foundation

/// Workspace indexing utilities for multi-workspace agent workloads
public struct WorkspaceIndexing {
    
    /// Creates all recommended indexes for workspace-based queries
    ///
    /// This creates indexes for:
    /// - Workspace records by projectRoot
    /// - Run history by workspace
    /// - File metadata by workspace
    ///
    /// - Parameter client: The BlazeDBClient instance
    /// - Throws: BlazeDBError if index creation fails
    ///
    /// ## Example
    /// ```swift
    /// let db = try BlazeDBClient(name: "AgentCore", fileURL: dbURL, password: "password")
    /// try WorkspaceIndexing.createWorkspaceIndexes(client: db)
    /// ```
    public static func createWorkspaceIndexes(client: BlazeDBClient) throws {
        BlazeLogger.info("🔧 Creating workspace indexes for multi-workspace workloads...")
        
        let collection = client.collection
        
        // 1. Index for Workspace records by projectRoot
        // This enables fast lookup of workspaces by their project root path
        do {
            try collection.createIndex(on: ["type", "projectRoot"])
            BlazeLogger.info("✅ Created index: type+projectRoot (for workspace lookup)")
        } catch {
            BlazeLogger.warn("⚠️ Failed to create type+projectRoot index: \(error)")
        }
        
        // 2. Index for run history by workspace
        // Enables fast queries like "all runs for workspace X"
        do {
            try collection.createIndex(on: ["type", "workspaceId", "timestamp"])
            BlazeLogger.info("✅ Created index: type+workspaceId+timestamp (for run history)")
        } catch {
            BlazeLogger.warn("⚠️ Failed to create run history index: \(error)")
        }
        
        // Alternative: If run history uses different field names
        do {
            try collection.createIndex(on: ["kind", "workspaceId", "createdAt"])
            BlazeLogger.info("✅ Created index: kind+workspaceId+createdAt (for run history)")
        } catch {
            BlazeLogger.debug("ℹ️ Skipped kind+workspaceId+createdAt index (may not be needed)")
        }
        
        // 3. Index for file metadata by workspace
        // Enables fast queries like "all Swift files in workspace X"
        do {
            try collection.createIndex(on: ["type", "workspaceId", "filePath"])
            BlazeLogger.info("✅ Created index: type+workspaceId+filePath (for file metadata)")
        } catch {
            BlazeLogger.warn("⚠️ Failed to create file metadata index: \(error)")
        }
        
        // Alternative: If file metadata uses different field names
        do {
            try collection.createIndex(on: ["kind", "workspaceId", "path"])
            BlazeLogger.info("✅ Created index: kind+workspaceId+path (for file metadata)")
        } catch {
            BlazeLogger.debug("ℹ️ Skipped kind+workspaceId+path index (may not be needed)")
        }
        
        // 4. Index for workspace summary lookups
        // Enables fast workspace summary queries
        do {
            try collection.createIndex(on: ["type", "workspaceId"])
            BlazeLogger.info("✅ Created index: type+workspaceId (for workspace summaries)")
        } catch {
            BlazeLogger.warn("⚠️ Failed to create workspace summary index: \(error)")
        }
        
        BlazeLogger.info("✅ Workspace indexing setup complete")
    }
    
    /// Creates indexes with custom field names
    ///
    /// Use this if your schema uses different field names than the defaults.
    ///
    /// - Parameters:
    ///   - client: The BlazeDBClient instance
    ///   - workspaceTypeField: Field name for record type (default: "type")
    ///   - workspaceIdField: Field name for workspace ID (default: "workspaceId")
    ///   - projectRootField: Field name for project root (default: "projectRoot")
    ///   - timestampField: Field name for timestamp (default: "timestamp")
    ///   - filePathField: Field name for file path (default: "filePath")
    /// - Throws: BlazeDBError if index creation fails
    public static func createWorkspaceIndexes(
        client: BlazeDBClient,
        workspaceTypeField: String = "type",
        workspaceIdField: String = "workspaceId",
        projectRootField: String = "projectRoot",
        timestampField: String = "timestamp",
        filePathField: String = "filePath"
    ) throws {
        BlazeLogger.info("🔧 Creating workspace indexes with custom field names...")
        
        let collection = client.collection
        
        // Workspace by projectRoot
        try collection.createIndex(on: [workspaceTypeField, projectRootField])
        BlazeLogger.info("✅ Created index: \(workspaceTypeField)+\(projectRootField)")
        
        // Run history by workspace
        try collection.createIndex(on: [workspaceTypeField, workspaceIdField, timestampField])
        BlazeLogger.info("✅ Created index: \(workspaceTypeField)+\(workspaceIdField)+\(timestampField)")
        
        // File metadata by workspace
        try collection.createIndex(on: [workspaceTypeField, workspaceIdField, filePathField])
        BlazeLogger.info("✅ Created index: \(workspaceTypeField)+\(workspaceIdField)+\(filePathField)")
        
        // Workspace summary
        try collection.createIndex(on: [workspaceTypeField, workspaceIdField])
        BlazeLogger.info("✅ Created index: \(workspaceTypeField)+\(workspaceIdField)")
        
        BlazeLogger.info("✅ Custom workspace indexing setup complete")
    }
}

