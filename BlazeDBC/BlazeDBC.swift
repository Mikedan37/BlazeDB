//
//  BlazeDBC.swift
//  BlazeDBC
//
//  Stable C ABI exports. Thin wrapper over BlazeDBClient byte KV.
//

import Foundation
import BlazeDBCore

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private final class BlazeDBCBox {
    let client: BlazeDBClient
    init(client: BlazeDBClient) {
        self.client = client
    }
}

private func box(from db: OpaquePointer?) -> BlazeDBCBox? {
    guard let db else { return nil }
    return Unmanaged<BlazeDBCBox>.fromOpaque(UnsafeRawPointer(db)).takeUnretainedValue()
}

private func mapError(_ error: Error) -> Int32 {
    if let blaze = error as? BlazeDBError {
        switch blaze {
        case .recordNotFound:
            return 1 // BLAZEDB_NOT_FOUND
        case .corruptedData, .invalidData:
            return 3 // BLAZEDB_CORRUPT
        case .invalidInput, .passwordTooWeak:
            return 4 // BLAZEDB_INVALID_ARGUMENT
        case .passwordMismatch:
            return 5 // BLAZEDB_AUTH_FAILED
        case .diskFull, .permissionDenied, .databaseLocked, .concurrentProcessAccessNotSupported:
            return 2 // BLAZEDB_IO_ERROR
        default:
            return 6 // BLAZEDB_INTERNAL_ERROR
        }
    }
    let ns = error as NSError
    if ns.domain == NSCocoaErrorDomain {
        return 2
    }
    return 6
}

private func cString(_ ptr: UnsafePointer<CChar>?) -> String? {
    guard let ptr else { return nil }
    return String(cString: ptr)
}

@_cdecl("blazedb_open")
public func blazedb_open(
    _ path: UnsafePointer<CChar>?,
    _ password: UnsafePointer<CChar>?
) -> OpaquePointer? {
    guard let pathStr = cString(path), !pathStr.isEmpty else { return nil }
    guard let pass = cString(password), !pass.isEmpty else { return nil }
    do {
        let url = URL(fileURLWithPath: pathStr)
        let client = try BlazeDBClient.open(at: url, password: pass)
        let handle = BlazeDBCBox(client: client)
        return OpaquePointer(Unmanaged.passRetained(handle).toOpaque())
    } catch {
        return nil
    }
}

@_cdecl("blazedb_close")
public func blazedb_close(_ db: OpaquePointer?) {
    guard let db else { return }
    let box = Unmanaged<BlazeDBCBox>.fromOpaque(UnsafeRawPointer(db)).takeRetainedValue()
    try? box.client.close()
}

@_cdecl("blazedb_put")
public func blazedb_put(
    _ db: OpaquePointer?,
    _ key: UnsafePointer<CChar>?,
    _ data: UnsafeRawPointer?,
    _ length: Int
) -> Int32 {
    guard let box = box(from: db) else { return 4 }
    guard let keyStr = cString(key), !keyStr.isEmpty else { return 4 }
    guard length >= 0 else { return 4 }
    let bytes: Data
    if length == 0 {
        bytes = Data()
    } else {
        guard let data else { return 4 }
        bytes = Data(bytes: data, count: length)
    }
    do {
        try box.client.put(key: keyStr, value: bytes)
        return 0
    } catch {
        return mapError(error)
    }
}

@_cdecl("blazedb_get")
public func blazedb_get(
    _ db: OpaquePointer?,
    _ key: UnsafePointer<CChar>?,
    _ outData: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    _ outLength: UnsafeMutablePointer<Int>?
) -> Int32 {
    func clearOut() {
        outData?.pointee = nil
        outLength?.pointee = 0
    }

    guard let box = box(from: db) else {
        clearOut()
        return 4
    }
    guard let keyStr = cString(key), !keyStr.isEmpty else {
        clearOut()
        return 4
    }
    guard outData != nil, outLength != nil else {
        return 4
    }

    do {
        guard let payload = try box.client.get(key: keyStr) else {
            clearOut()
            return 1 // NOT_FOUND
        }
        let count = payload.count
        if count == 0 {
            // Distinguish empty value from missing: allocate a zero-size buffer via malloc(1)
            // and report length 0, or use a non-NULL sentinel. Prefer malloc(0)/empty Data:
            // many platforms return non-NULL from malloc(0); use malloc(1) and length 0.
            guard let buf = malloc(1) else {
                clearOut()
                return 6
            }
            outData?.pointee = buf
            outLength?.pointee = 0
            return 0
        }
        guard let buf = malloc(count) else {
            clearOut()
            return 6
        }
        payload.copyBytes(to: buf.assumingMemoryBound(to: UInt8.self), count: count)
        outData?.pointee = buf
        outLength?.pointee = count
        return 0
    } catch {
        clearOut()
        return mapError(error)
    }
}

@_cdecl("blazedb_delete")
public func blazedb_delete(
    _ db: OpaquePointer?,
    _ key: UnsafePointer<CChar>?
) -> Int32 {
    guard let box = box(from: db) else { return 4 }
    guard let keyStr = cString(key), !keyStr.isEmpty else { return 4 }
    do {
        try box.client.delete(key: keyStr)
        return 0
    } catch {
        return mapError(error)
    }
}

@_cdecl("blazedb_free")
public func blazedb_free(_ ptr: UnsafeMutableRawPointer?) {
    guard let ptr else { return }
    free(ptr)
}
