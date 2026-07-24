//
//  BlazeDBClient+ByteKV.swift
//  BlazeDB
//
//  Language-neutral byte key-value surface. Keys are UTF-8 strings; values are
//  opaque blobs. The C ABI (BlazeDBC) wraps these methods only.
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Reserved storage namespace and fields for the byte KV API.
enum BlazeByteKV {
    static let kind = "_kv"
    static let keyField = "_kvKey"
    static let valueField = "_kvValue"

    /// Deterministic UUID from the UTF-8 encoding of `key` (SHA-256, first 16 bytes).
    static func recordID(forKey key: String) -> UUID {
        let digest = SHA256.hash(data: Data(key.utf8))
        let b = Array(digest.prefix(16))
        return UUID(uuid: (
            b[0], b[1], b[2], b[3],
            b[4], b[5], b[6], b[7],
            b[8], b[9], b[10], b[11],
            b[12], b[13], b[14], b[15]
        ))
    }

    static func makeRecord(key: String, value: Data) -> BlazeDataRecord {
        BlazeDataRecord([
            BlazeRecordKind.storageKey: .string(kind),
            keyField: .string(key),
            valueField: .data(value)
        ])
    }
}

extension BlazeDBClient {
    /// Store an opaque byte value under a UTF-8 string key.
    ///
    /// Keys are identity after UTF-8 encoding. Values are never interpreted.
    /// Overwrites any previous value for the same key.
    public func put(key: String, value: Data) throws {
        guard !key.isEmpty else {
            throw BlazeDBError.invalidInput(reason: "KV key cannot be empty")
        }
        let id = BlazeByteKV.recordID(forKey: key)
        let record = BlazeByteKV.makeRecord(key: key, value: value)
        if let existing = try fetch(id: id) {
            if case let .string(stored)? = existing.storage[BlazeByteKV.keyField], stored != key {
                throw BlazeDBError.invalidData(
                    reason: "KV key hash collision: stored key does not match '\(key)'"
                )
            }
            try update(id: id, with: record)
        } else {
            try insert(record, id: id)
        }
    }

    /// Fetch the opaque bytes previously stored under `key`, or `nil` if absent.
    public func get(key: String) throws -> Data? {
        guard !key.isEmpty else {
            throw BlazeDBError.invalidInput(reason: "KV key cannot be empty")
        }
        let id = BlazeByteKV.recordID(forKey: key)
        guard let record = try fetch(id: id) else { return nil }
        if case let .string(stored)? = record.storage[BlazeByteKV.keyField], stored != key {
            throw BlazeDBError.invalidData(
                reason: "KV key hash collision: stored key does not match '\(key)'"
            )
        }
        guard case let .data(payload)? = record.storage[BlazeByteKV.valueField] else {
            throw BlazeDBError.corruptedData(
                location: "kv:\(key)",
                reason: "Missing or invalid _kvValue field"
            )
        }
        return payload
    }

    /// Delete the value under `key`. No-op if the key does not exist.
    public func delete(key: String) throws {
        guard !key.isEmpty else {
            throw BlazeDBError.invalidInput(reason: "KV key cannot be empty")
        }
        let id = BlazeByteKV.recordID(forKey: key)
        if let existing = try fetch(id: id) {
            if case let .string(stored)? = existing.storage[BlazeByteKV.keyField], stored != key {
                throw BlazeDBError.invalidData(
                    reason: "KV key hash collision: stored key does not match '\(key)'"
                )
            }
        }
        do {
            try delete(id: id)
        } catch BlazeDBError.recordNotFound {
            // Idempotent delete for missing keys.
            return
        }
    }
}
