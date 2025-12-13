//
//  WorkspaceSummary.swift
//  BlazeDB
//
//  Lightweight workspace summary table for multi-workspace agent workloads
//  Provides fast aggregated statistics without full table scans
//
//  Created by Auto on 2025-11-27.
//

import Foundation

/// Workspace summary statistics
public struct WorkspaceSummary: Codable {
    /// Workspace ID
    public let workspaceId: UUID
    
    /// Total number of Swift files in the workspace
    public var totalSwiftFiles: Int
    
    /// Total number of symbols (functions, classes, etc.) in the workspace
    public var totalSymbols: Int
    
    /// Total number of runs executed in this workspace
    public var totalRuns: Int
    
    /// Timestamp of the last execution in this workspace
    public var lastExecutionTimestamp: Date?
    
    /// Project root path for this workspace
    public let projectRoot: String
    
    /// When this summary was last updated
    public var lastUpdated: Date
    
    public init(
        workspaceId: UUID,
        projectRoot: String,
        totalSwiftFiles: Int = 0,
        totalSymbols: Int = 0,
        totalRuns: Int = 0,
        lastExecutionTimestamp: Date? = nil,
        lastUpdated: Date = Date()
    ) {
        self.workspaceId = workspaceId
        self.projectRoot = projectRoot
        self.totalSwiftFiles = totalSwiftFiles
        self.totalSymbols = totalSymbols
        self.totalRuns = totalRuns
        self.lastExecutionTimestamp = lastExecutionTimestamp
        self.lastUpdated = lastUpdated
    }
    
    /// Convert to BlazeDataRecord for storage
    public func toBlazeDataRecord() -> BlazeDataRecord {
        var storage: [String: BlazeDocumentField] = [
            "id": .uuid(workspaceId),
            "type": .string("workspace_summary"),
            "workspaceId": .uuid(workspaceId),
            "projectRoot": .string(projectRoot),
            "totalSwiftFiles": .int(totalSwiftFiles),
            "totalSymbols": .int(totalSymbols),
            "totalRuns": .int(totalRuns),
            "lastUpdated": .date(lastUpdated)
        ]
        
        if let lastExecution = lastExecutionTimestamp {
            storage["lastExecutionTimestamp"] = .date(lastExecution)
        }
        
        return BlazeDataRecord(storage)
    }
    
    /// Create from BlazeDataRecord
    public init?(from record: BlazeDataRecord) {
        guard let workspaceId = record.storage["workspaceId"]?.uuidValue ?? record.storage["id"]?.uuidValue,
              let projectRoot = record.storage["projectRoot"]?.stringValue else {
            return nil
        }
        
        self.workspaceId = workspaceId
        self.projectRoot = projectRoot
        self.totalSwiftFiles = record.storage["totalSwiftFiles"]?.intValue ?? 0
        self.totalSymbols = record.storage["totalSymbols"]?.intValue ?? 0
        self.totalRuns = record.storage["totalRuns"]?.intValue ?? 0
        self.lastExecutionTimestamp = record.storage["lastExecutionTimestamp"]?.dateValue
        self.lastUpdated = record.storage["lastUpdated"]?.dateValue ?? Date()
    }
}

/// Workspace summary manager for maintaining aggregated statistics
public struct WorkspaceSummaryManager {
    
    /// Recalculate and update workspace summary
    ///
    /// This scans all records for a workspace and calculates:
    /// - Total Swift files
    /// - Total symbols
    /// - Total runs
    /// - Last execution timestamp
    ///
    /// - Parameters:
    ///   - client: The BlazeDBClient instance
    ///   - workspaceId: The workspace ID to summarize
    ///   - workspaceTypeField: Field name for record type (default: "type")
    ///   - workspaceIdField: Field name for workspace ID (default: "workspaceId")
    /// - Returns: The updated WorkspaceSummary
    /// - Throws: BlazeDBError if calculation fails
    public static func recalculateSummary(
        client: BlazeDBClient,
        workspaceId: UUID,
        workspaceTypeField: String = "type",
        workspaceIdField: String = "workspaceId"
    ) throws -> WorkspaceSummary {
        BlazeLogger.info("📊 Recalculating workspace summary for \(workspaceId.uuidString.prefix(8))...")
        
        let allRecords = try client.fetchAll()
        
        var totalSwiftFiles = 0
        var totalSymbols = 0
        var totalRuns = 0
        var lastExecutionTimestamp: Date? = nil
        var projectRoot: String = ""
        
        // Find workspace record to get projectRoot
        // Try direct lookup first (most common case)
        if let workspaceRecord = try? client.fetch(id: workspaceId) {
            if let type = workspaceRecord.storage[workspaceTypeField]?.stringValue,
               type.lowercased() == "workspace" {
                projectRoot = workspaceRecord.storage["projectRoot"]?.stringValue ?? ""
            }
        }
        
        // Fallback: scan all records if direct lookup didn't work
        if projectRoot.isEmpty {
            for record in allRecords {
                if let recordId = record.storage["id"]?.uuidValue, recordId == workspaceId {
                    if let type = record.storage[workspaceTypeField]?.stringValue,
                       type.lowercased() == "workspace" {
                        projectRoot = record.storage["projectRoot"]?.stringValue ?? ""
                        break
                    }
                }
            }
        }
        
        // Scan records for this workspace
        for record in allRecords {
            // Check if record belongs to this workspace
            let belongsToWorkspace: Bool
            if let recordWorkspaceId = record.storage[workspaceIdField]?.uuidValue {
                belongsToWorkspace = recordWorkspaceId == workspaceId
            } else {
                belongsToWorkspace = false
            }
            
            if !belongsToWorkspace {
                continue
            }
            
            // Count Swift files
            if let type = record.storage[workspaceTypeField]?.stringValue,
               type.lowercased() == "file" || type.lowercased() == "filemetadata" {
                if let path = record.storage["filePath"]?.stringValue ?? record.storage["path"]?.stringValue,
                   path.hasSuffix(".swift") {
                    totalSwiftFiles += 1
                }
            }
            
            // Count symbols
            if let type = record.storage[workspaceTypeField]?.stringValue,
               type.lowercased() == "symbol" || type.lowercased() == "symbolmetadata" {
                totalSymbols += 1
            }
            
            // Count runs and track last execution
            if let type = record.storage[workspaceTypeField]?.stringValue,
               type.lowercased() == "run" || type.lowercased() == "runhistory" || type.lowercased() == "execution" {
                totalRuns += 1
                
                // Update last execution timestamp
                if let timestamp = record.storage["timestamp"]?.dateValue ?? 
                                   record.storage["createdAt"]?.dateValue ??
                                   record.storage["executedAt"]?.dateValue {
                    if lastExecutionTimestamp == nil || timestamp > lastExecutionTimestamp! {
                        lastExecutionTimestamp = timestamp
                    }
                }
            }
        }
        
        let summary = WorkspaceSummary(
            workspaceId: workspaceId,
            projectRoot: projectRoot,
            totalSwiftFiles: totalSwiftFiles,
            totalSymbols: totalSymbols,
            totalRuns: totalRuns,
            lastExecutionTimestamp: lastExecutionTimestamp
        )
        
        // Save summary
        try saveSummary(client: client, summary: summary)
        
        BlazeLogger.info("✅ Workspace summary updated: \(totalSwiftFiles) files, \(totalSymbols) symbols, \(totalRuns) runs")
        
        return summary
    }
    
    /// Get workspace summary (cached or recalculated)
    ///
    /// - Parameters:
    ///   - client: The BlazeDBClient instance
    ///   - workspaceId: The workspace ID
    ///   - forceRecalculate: If true, recalculates even if cached summary exists
    /// - Returns: The WorkspaceSummary, or nil if workspace not found
    /// - Throws: BlazeDBError if operation fails
    public static func getSummary(
        client: BlazeDBClient,
        workspaceId: UUID,
        forceRecalculate: Bool = false
    ) throws -> WorkspaceSummary? {
        // Try to fetch cached summary
        if !forceRecalculate {
            let summaries = try client.query()
                .where("type", equals: .string("workspace_summary"))
                .where("workspaceId", equals: .uuid(workspaceId))
                .execute()
                .records
            
            if let summaryRecord = summaries.first,
               let summary = WorkspaceSummary(from: summaryRecord) {
                BlazeLogger.debug("📊 Using cached workspace summary")
                return summary
            }
        }
        
        // Recalculate if not found or forced
        return try recalculateSummary(client: client, workspaceId: workspaceId)
    }
    
    /// Save or update workspace summary
    ///
    /// - Parameters:
    ///   - client: The BlazeDBClient instance
    ///   - summary: The WorkspaceSummary to save
    /// - Throws: BlazeDBError if save fails
    public static func saveSummary(client: BlazeDBClient, summary: WorkspaceSummary) throws {
        let record = summary.toBlazeDataRecord()
        
        // Use upsert to update if exists, insert if new
        try client.upsert(id: summary.workspaceId, data: record)
        
        BlazeLogger.debug("💾 Saved workspace summary for \(summary.workspaceId.uuidString.prefix(8))")
    }
    
    /// Incrementally update summary when a new record is added
    ///
    /// This is more efficient than full recalculation for frequent updates.
    ///
    /// - Parameters:
    ///   - client: The BlazeDBClient instance
    ///   - workspaceId: The workspace ID
    ///   - recordType: Type of record being added ("file", "symbol", "run")
    ///   - timestamp: Optional timestamp for run records
    /// - Throws: BlazeDBError if update fails
    public static func incrementSummary(
        client: BlazeDBClient,
        workspaceId: UUID,
        recordType: String,
        timestamp: Date? = nil
    ) throws {
        guard var summary = try getSummary(client: client, workspaceId: workspaceId, forceRecalculate: false) else {
            // Summary doesn't exist, create it
            _ = try recalculateSummary(client: client, workspaceId: workspaceId)
            return
        }
        
        let type = recordType.lowercased()
        
        // Increment appropriate counter
        if type == "file" || type == "filemetadata" {
            summary.totalSwiftFiles += 1
        } else if type == "symbol" || type == "symbolmetadata" {
            summary.totalSymbols += 1
        } else if type == "run" || type == "runhistory" || type == "execution" {
            summary.totalRuns += 1
            if let timestamp = timestamp {
                if summary.lastExecutionTimestamp == nil || timestamp > summary.lastExecutionTimestamp! {
                    summary.lastExecutionTimestamp = timestamp
                }
            }
        }
        
        summary.lastUpdated = Date()
        
        try saveSummary(client: client, summary: summary)
    }
    
    /// Get all workspace summaries
    ///
    /// - Parameter client: The BlazeDBClient instance
    /// - Returns: Array of all WorkspaceSummary records
    /// - Throws: BlazeDBError if fetch fails
    public static func getAllSummaries(client: BlazeDBClient) throws -> [WorkspaceSummary] {
        let records = try client.query()
            .where("type", equals: .string("workspace_summary"))
            .execute()
            .records
        
        return records.compactMap { WorkspaceSummary(from: $0) }
    }
}

