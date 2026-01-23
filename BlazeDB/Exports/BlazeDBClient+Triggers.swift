//
//  BlazeDBClient+Triggers.swift
//  BlazeDB
//
//  Trigger persistence integration
//
//  Created by Auto on 1/XX/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation

extension BlazeDBClient {
    
    /// Persist trigger definition to StorageLayout metaData
    internal func persistTriggerDefinition(_ definition: TriggerDefinition) throws {
        let layout = try StorageLayout.loadSecure(from: collection.metaURLPath, signingKey: collection.encryptionKey)
        var updatedLayout = layout
        
        // Load existing trigger definitions from metaData
        var triggerDefinitions: [TriggerDefinition] = []
        if let triggersData = updatedLayout.metaData["_triggers"]?.dataValue,
           let decoded = try? JSONDecoder().decode([TriggerDefinition].self, from: triggersData) {
            triggerDefinitions = decoded
        }
        
        // Add new definition if not already present
        if !triggerDefinitions.contains(where: { $0.name == definition.name }) {
            triggerDefinitions.append(definition)
            
            // Encode and store in metaData
            let encoded = try JSONEncoder().encode(triggerDefinitions)
            updatedLayout.metaData["_triggers"] = .data(encoded)
            
            try updatedLayout.saveSecure(to: collection.metaURLPath, signingKey: collection.encryptionKey)
            BlazeLogger.debug("Persisted trigger definition: \(definition.name)")
        }
    }
    
    /// Reload triggers from StorageLayout metaData (called on DB open)
    internal func reloadTriggers() {
        guard let layout = try? StorageLayout.loadSecure(from: collection.metaURLPath, signingKey: collection.encryptionKey) else {
            return
        }
        
        // Load trigger definitions from metaData
        var triggerCount = 0
        if let triggersData = layout.metaData["_triggers"]?.dataValue,
           let decoded = try? JSONDecoder().decode([TriggerDefinition].self, from: triggersData) {
            triggerCount = decoded.count
        }
        
        // Triggers are metadata only - actual handlers are in Swift code
        // This is just for tracking which triggers exist
        BlazeLogger.debug("Loaded \(triggerCount) trigger definition(s) from storage")
    }
    
    /// Hook into onInsert to persist trigger definition
    /// This is called from the Triggers extension
    internal func persistTriggerOnInsert(_ definition: TriggerDefinition) {
        try? persistTriggerDefinition(definition)
    }
}
#endif // !BLAZEDB_LINUX_CORE
