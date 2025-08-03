//  CBORCoder.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.

import Foundation
internal import SwiftCBOR

enum CBORCoder {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let jsonData = try JSONEncoder().encode(value)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as! [String: Any]
        let cborMap = try encodeToCBOR(jsonObject)
        return Data(CBOR.map(cborMap).encode())
    }

    static func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        guard
            let decodedCBOR = try? CBORDecoder(input: [UInt8](data)).decodeItem(),
            let cborMap = decodedCBOR.getMap()
        else {
            throw NSError(domain: "CBORDecode", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected CBOR map"])
        }

        let jsonObject = decodeCBORMap(cborMap)
        let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
        return try JSONDecoder().decode(T.self, from: jsonData)
    }

    // MARK: - Private bridge methods

    private static func encodeToCBOR(_ json: [String: Any]) throws -> [CBOR: CBOR] {
        var map = [CBOR: CBOR]()
        for (key, value) in json {
            let cborKey = CBOR.utf8String(key)
            let cborValue: CBOR

            switch value {
            case let v as String:
                cborValue = .utf8String(v)
            case let v as Int:
                cborValue = v >= 0 ? .unsignedInt(UInt64(v)) : .negativeInt(UInt64(abs(v + 1)))
            case let v as Bool:
                cborValue = .boolean(v)
            case let v as Double:
                cborValue = .double(v)
            default:
                throw NSError(domain: "CBORBridge", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unsupported value: \(value)"])
            }

            map[cborKey] = cborValue
        }
        return map
    }

    private static func decodeCBORMap(_ map: [CBOR: CBOR]) -> [String: Any] {
        var json = [String: Any]()

        for (key, value) in map {
            guard case let .utf8String(k) = key else { continue }

            let v: Any
            switch value {
            case let .utf8String(str):
                v = str
            case let .unsignedInt(i):
                v = Int(i)
            case let .negativeInt(i):
                v = -1 - Int(i)
            case let .boolean(b):
                v = b
            case let .double(d):
                v = d
            default:
                continue
            }

            json[k] = v
        }

        return json
    }
}

private extension CBOR {
    func getMap() -> [CBOR: CBOR]? {
        if case let .map(m) = self {
            return m
        }
        return nil
    }
}
