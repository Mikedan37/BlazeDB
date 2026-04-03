//
//  BlazeDBClient+Triggers.swift
//  BlazeDB
//
//  Trigger persistence integration
//
#if !BLAZEDB_LINUX_CORE
import Foundation

extension BlazeDBClient {

    private func loadTriggerPersistenceLayout() throws -> StorageLayout {
        try StorageLayout.loadSecure(
            from: collection.metaURLPath,
            signingKey: collection.encryptionKey,
            password: collection.password,
            salt: collection.kdfSalt,
            allowUnsignedLayoutFallback: true
        )
    }

    private func triggerMetadataEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func triggerMetadataDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
    
    /// Persist trigger definition to StorageLayout metaData
    internal func persistTriggerDefinition(_ definition: TriggerDefinition) throws {
        let layout = try loadTriggerPersistenceLayout()
        var updatedLayout = layout
        
        // Load existing trigger definitions from metaData
        var triggerDefinitions: [TriggerDefinition] = []
        if let triggersData = updatedLayout.metaData["_triggers"]?.dataValue,
           let decoded = try? triggerMetadataDecoder().decode([TriggerDefinition].self, from: triggersData) {
            triggerDefinitions = decoded
        }
        
        // Add new definition if not already present
        if !triggerDefinitions.contains(where: { $0.name == definition.name }) {
            triggerDefinitions.append(definition)
            
            // Encode and store in metaData
            let encoded = try triggerMetadataEncoder().encode(triggerDefinitions)
            updatedLayout.metaData["_triggers"] = .data(encoded)
            
            try updatedLayout.saveSecure(to: collection.metaURLPath, signingKey: collection.encryptionKey)
            BlazeLogger.debug("Persisted trigger definition: \(definition.name)")
        }
    }
    
    /// Reload triggers from StorageLayout metaData (called on DB open)
    internal func reloadTriggers() {
        let layout: StorageLayout
        do {
            layout = try loadTriggerPersistenceLayout()
        } catch {
            BlazeLogger.warn("reloadTriggers: could not load layout from \(collection.metaURLPath): \(error.localizedDescription)")
            return
        }
        
        // Load trigger definitions from metaData
        var triggerCount = 0
        if let triggersData = layout.metaData["_triggers"]?.dataValue,
           let decoded = try? triggerMetadataDecoder().decode([TriggerDefinition].self, from: triggersData) {
            triggerCount = decoded.count
        }
        
        // Triggers are metadata only - actual handlers are in Swift code
        // This is just for tracking which triggers exist
        BlazeLogger.debug("Loaded \(triggerCount) trigger definition(s) from storage")
    }
    
    /// Hook into onInsert to persist trigger definition
    /// This is called from the Triggers extension
    internal func persistTriggerOnInsert(_ definition: TriggerDefinition) {
        do {
            try persistTriggerDefinition(definition)
        } catch {
            BlazeLogger.warn("persistTriggerOnInsert: failed for '\(definition.name)': \(error.localizedDescription)")
        }
    }
}
#endif // !BLAZEDB_LINUX_CORE
