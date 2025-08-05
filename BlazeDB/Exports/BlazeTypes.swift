//  BlazeTypes.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/19/25.

import Foundation

public struct BlazeDataRecord: Codable, Hashable, Equatable {
    public var storage: [String: BlazeDocumentField]

    public init(_ storage: [String: BlazeDocumentField]) {
        self.storage = storage
    }

    public subscript(key: String) -> BlazeDocumentField? {
        get { storage[key] }
        set { storage[key] = newValue }
    }
}

public extension BlazeDataRecord {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.storage = try container.decode([String: BlazeDocumentField].self, forKey: .storage)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storage, forKey: .storage)
    }

    private enum CodingKeys: String, CodingKey {
        case storage
    }
}
