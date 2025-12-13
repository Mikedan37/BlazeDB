//
//  BlazeDBClient+Triggers.swift
//  BlazeDB
//
//  Trigger persistence integration
//
//  Created by Auto on 1/XX/25.
//

import Foundation

extension BlazeDBClient {
    
    /// Persist trigger definition to StorageLayout
    internal func persistTriggerDefinition(_ definition: TriggerDefinition) throws {
        let layout = try StorageLayout.loadSecure(from: collection.metaURLPath, signingKey: collection.encryptionKey)
        var updatedLayout = layout
        if !updatedLayout.triggerDefinitions.contains(where: { $0.name == definition.name }) {
            updatedLayout.triggerDefinitions.append(definition)
            try updatedLayout.saveSecure(to: collection.metaURLPath, signingKey: collection.encryptionKey)
            BlazeLogger.debug("Persisted trigger definition: \(definition.name)")
        }
    }
    
    /// Reload triggers from StorageLayout (called on DB open)
    internal func reloadTriggers() {
        guard let layout = try? StorageLayout.loadSecure(from: collection.metaURLPath, signingKey: collection.encryptionKey) else {
            return
        }
        
        // Triggers are metadata only - actual handlers are in Swift code
        // This is just for tracking which triggers exist
        BlazeLogger.debug("Loaded \(layout.triggerDefinitions.count) trigger definition(s) from storage")
    }
    
    /// Hook into onInsert to persist trigger definition
    /// This is called from the Triggers extension
    internal func persistTriggerOnInsert(_ definition: TriggerDefinition) {
        try? persistTriggerDefinition(definition)
    }
}

