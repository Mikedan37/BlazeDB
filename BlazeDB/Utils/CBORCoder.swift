//  JSONCoder.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.

import Foundation

enum JSONCoder {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        return try JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        return try JSONDecoder().decode(T.self, from: data)
    }
}
