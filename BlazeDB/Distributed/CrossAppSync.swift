//
//  CrossAppSync.swift
//  BlazeDB Distributed
//
//  Cross-app synchronization coordinator (same device, different apps)
//

#if !BLAZEDB_LINUX_CORE
#if BLAZEDB_DISTRIBUTED
import BlazeDBCore
#endif
import Foundation

/// Coordinates cross-app synchronization using App Groups
public actor CrossAppSyncCoordinator {
    private let database: BlazeDBClient
    private let appGroup: String
    private let exportPolicy: ExportPolicy
    private var isEnabled = false
    
    public init(
        database: BlazeDBClient,
        appGroup: String,
        exportPolicy: ExportPolicy
    ) {
        self.database = database
        self.appGroup = appGroup
        self.exportPolicy = exportPolicy
    }
    
    // MARK: - Enable/Disable
    
    public func enable() async throws {
        guard !isEnabled else { return }
        
        // Create shared container URL
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else {
            throw CrossAppSyncError.invalidAppGroup
        }
        
        // Create shared database path
        let dbName = database.fileURL.lastPathComponent
        let sharedPath = containerURL.appendingPathComponent(dbName)
        
        // Copy database to shared location (if not already there)
        if !FileManager.default.fileExists(atPath: sharedPath.path) {
            try FileManager.default.copyItem(at: database.fileURL, to: sharedPath)
        }
        
        // Set up file coordination
        try await setupFileCoordination(sharedPath: sharedPath)
        
        isEnabled = true
        
        BlazeLogger.info("CrossAppSync enabled for app group: \(appGroup) (shared path: \(sharedPath.path), collections: \(exportPolicy.collections))")
    }
    
    public func disable() async {
        isEnabled = false
        BlazeLogger.info("CrossAppSync disabled")
    }
    
    // MARK: - File Coordination
    
    private func setupFileCoordination(sharedPath: URL) async throws {
        // Use NSFileCoordinator for safe multi-app access
        let coordinator = NSFileCoordinator()
        
        // Set up file presenter to watch for changes
        let presenter = DatabaseFilePresenter(
            database: database,
            sharedPath: sharedPath,
            exportPolicy: exportPolicy
        )
        
        NSFileCoordinator.addFilePresenter(presenter)
    }
}

// MARK: - File Presenter

private class DatabaseFilePresenter: NSObject, NSFilePresenter {
    let database: BlazeDBClient
    let sharedPath: URL
    let exportPolicy: ExportPolicy
    
    init(
        database: BlazeDBClient,
        sharedPath: URL,
        exportPolicy: ExportPolicy
    ) {
        self.database = database
        self.sharedPath = sharedPath
        self.exportPolicy = exportPolicy
        super.init()
    }
    
    var presentedItemURL: URL? {
        return sharedPath
    }
    
    var presentedItemOperationQueue: OperationQueue {
        return OperationQueue.main
    }
    
    func presentedItemDidChange() {
        // Another app modified the database
        // Reload relevant collections
        Task {
            await reloadExportedCollections()
        }
    }
    
    private func reloadExportedCollections() async {
        // Reload collections based on export policy
        for collection in exportPolicy.collections {
            // Trigger reload notification
            NotificationCenter.default.post(
                name: .blazeDBCollectionDidChange,
                object: nil,
                userInfo: ["collection": collection]
            )
        }
    }
}

extension Notification.Name {
    static let blazeDBCollectionDidChange = Notification.Name("blazeDBCollectionDidChange")
}

// MARK: - Errors

enum CrossAppSyncError: Error {
    case invalidAppGroup
    case fileCoordinationFailed
}

// MARK: - BlazeDBClient Extension

extension BlazeDBClient {
    /// Enable cross-app sync for this database
    public func enableCrossAppSync(
        appGroup: String,
        exportPolicy: ExportPolicy
    ) async throws {
        let coordinator = CrossAppSyncCoordinator(
            database: self,
            appGroup: appGroup,
            exportPolicy: exportPolicy
        )
        
        try await coordinator.enable()
    }
    
    /// Connect to a shared database from another app
    public static func connectToSharedDB(
        appGroup: String,
        database: String,
        mode: AccessMode = .readOnly
    ) throws -> BlazeDBClient {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else {
            throw CrossAppSyncError.invalidAppGroup
        }
        
        let sharedPath = containerURL.appendingPathComponent(database)
        
        guard FileManager.default.fileExists(atPath: sharedPath.path) else {
            throw CrossAppSyncError.invalidAppGroup
        }
        
        // Create read-only connection
        guard let client = BlazeDBClient(
            name: database,
            at: sharedPath,
            password: ""  // Will need to handle password sharing
        ) else {
            throw CrossAppSyncError.invalidAppGroup
        }
        return client
    }
    
    public enum AccessMode {
        case readOnly
        case readWrite
    }
}
#endif // !BLAZEDB_LINUX_CORE

