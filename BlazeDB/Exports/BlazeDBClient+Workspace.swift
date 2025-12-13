//
//  BlazeDBClient+Workspace.swift
//  BlazeDB
//
//  Workspace-specific query helpers for multi-workspace agent workloads
//  Provides convenient methods for common workspace queries
//
//  Created by Auto on 2025-11-27.
//

import Foundation

extension BlazeDBClient {
    
    // MARK: - Workspace Queries
    
    /// Get all workspaces by project root
    ///
    /// Uses the projectRoot index for efficient lookup.
    ///
    /// - Parameter projectRoot: The project root path to search for
    /// - Returns: Array of workspace records matching the project root
    /// - Throws: BlazeDBError if query fails
    public func getWorkspaces(byProjectRoot projectRoot: String) throws -> [BlazeDataRecord] {
        return try query()
            .where("type", equals: .string("workspace"))
            .where("projectRoot", equals: .string(projectRoot))
            .execute()
            .records
    }
    
    /// Get run history for a workspace
    ///
    /// Uses the workspaceId+timestamp index for efficient lookup.
    ///
    /// - Parameters:
    ///   - workspaceId: The workspace ID
    ///   - limit: Optional limit on number of results
    ///   - orderBy: Order by timestamp (default: descending, most recent first)
    /// - Returns: Array of run history records
    /// - Throws: BlazeDBError if query fails
    public func getRunHistory(
        forWorkspace workspaceId: UUID,
        limit: Int? = nil,
        orderBy: SortOrder = .descending
    ) throws -> [BlazeDataRecord] {
        var query = self.query()
            .where("type", equals: .string("run"))
            .where("workspaceId", equals: .uuid(workspaceId))
            .orderBy("timestamp", descending: orderBy == .descending)
        
        if let limit = limit {
            query = query.limit(limit)
        }
        
        return try query.execute().records
    }
    
    /// Get file metadata for a workspace
    ///
    /// Uses the workspaceId+filePath index for efficient lookup.
    ///
    /// - Parameters:
    ///   - workspaceId: The workspace ID
    ///   - fileExtension: Optional file extension filter (e.g., ".swift")
    /// - Returns: Array of file metadata records
    /// - Throws: BlazeDBError if query fails
    public func getFileMetadata(
        forWorkspace workspaceId: UUID,
        fileExtension: String? = nil
    ) throws -> [BlazeDataRecord] {
        var query = self.query()
            .where("type", equals: .string("file"))
            .where("workspaceId", equals: .uuid(workspaceId))
        
        if let ext = fileExtension {
            query = query.where("filePath", contains: ext)
        }
        
        return try query.execute().records
    }
    
    /// Get workspace summary
    ///
    /// Returns cached summary or recalculates if needed.
    ///
    /// - Parameter workspaceId: The workspace ID
    /// - Returns: WorkspaceSummary or nil if workspace not found
    /// - Throws: BlazeDBError if operation fails
    public func getWorkspaceSummary(for workspaceId: UUID) throws -> WorkspaceSummary? {
        return try WorkspaceSummaryManager.getSummary(client: self, workspaceId: workspaceId)
    }
    
    /// Recalculate workspace summary
    ///
    /// Forces a full recalculation of workspace statistics.
    ///
    /// - Parameter workspaceId: The workspace ID
    /// - Returns: The updated WorkspaceSummary
    /// - Throws: BlazeDBError if calculation fails
    public func recalculateWorkspaceSummary(for workspaceId: UUID) throws -> WorkspaceSummary {
        return try WorkspaceSummaryManager.recalculateSummary(client: self, workspaceId: workspaceId)
    }
    
    /// Get all workspace summaries
    ///
    /// Returns summaries for all workspaces in the database.
    ///
    /// - Returns: Array of all WorkspaceSummary records
    /// - Throws: BlazeDBError if fetch fails
    public func getAllWorkspaceSummaries() throws -> [WorkspaceSummary] {
        return try WorkspaceSummaryManager.getAllSummaries(client: self)
    }
    
    /// Initialize workspace indexes
    ///
    /// Creates all recommended indexes for workspace-based queries.
    /// Safe to call multiple times (idempotent).
    ///
    /// - Throws: BlazeDBError if index creation fails
    public func initializeWorkspaceIndexes() throws {
        try WorkspaceIndexing.createWorkspaceIndexes(client: self)
    }
}

/// Sort order for queries
public enum SortOrder {
    case ascending
    case descending
}

extension QueryBuilder {
    /// Order results by a field
    ///
    /// - Parameters:
    ///   - field: Field name to sort by
    ///   - order: Sort order (ascending or descending)
    /// - Returns: QueryBuilder for chaining
    @discardableResult
    public func order(by field: String, _ order: SortOrder) -> QueryBuilder {
        switch order {
        case .ascending:
            return self.orderBy(field, descending: false)
        case .descending:
            return self.orderBy(field, descending: true)
        }
    }
}

