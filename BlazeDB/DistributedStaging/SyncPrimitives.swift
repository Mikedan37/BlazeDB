import Foundation

/// Swift 6-safe staging primitive for distributed ordering.
public struct StagingLamportTimestamp: Comparable, Codable, Hashable, Sendable {
    public let counter: UInt64
    public let nodeID: UUID

    public init(counter: UInt64, nodeID: UUID) {
        self.counter = counter
        self.nodeID = nodeID
    }

    public static func < (lhs: StagingLamportTimestamp, rhs: StagingLamportTimestamp) -> Bool {
        if lhs.counter != rhs.counter {
            return lhs.counter < rhs.counter
        }
        return lhs.nodeID.uuidString < rhs.nodeID.uuidString
    }
}

/// Minimal operation envelope used by staged sync flows.
public struct StagingSyncEnvelope: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case insert
        case update
        case delete
    }

    public let id: UUID
    public let timestamp: StagingLamportTimestamp
    public let collection: String
    public let recordID: UUID
    public let kind: Kind
    public let payload: [String: String]

    public init(
        id: UUID = UUID(),
        timestamp: StagingLamportTimestamp,
        collection: String,
        recordID: UUID,
        kind: Kind,
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.collection = collection
        self.recordID = recordID
        self.kind = kind
        self.payload = payload
    }
}
