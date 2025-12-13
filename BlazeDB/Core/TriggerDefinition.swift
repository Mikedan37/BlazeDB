//
//  TriggerDefinition.swift
//  BlazeDB
//
//  Persistent trigger definition for StorageLayout
//
//  Created by Auto on 1/XX/25.
//

import Foundation

/// Persistent trigger definition (metadata only)
/// Actual trigger handlers are in Swift code, this is just metadata
public struct TriggerDefinition: Codable {
    public let name: String
    public let event: String  // "beforeInsert", "afterInsert", etc.
    public let collectionName: String?
    
    public init(name: String, event: String, collectionName: String?) {
        self.name = name
        self.event = event
        self.collectionName = collectionName
    }
}

