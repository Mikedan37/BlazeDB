//
//  AssociatedObjects.swift
//  BlazeDB
//
//  Platform-safe associated object storage
//  Uses Objective-C runtime on Apple platforms, dictionary storage on Linux
//
//  Created by Auto on 12/14/25.
//

import Foundation

#if canImport(ObjectiveC)
import ObjectiveC
#endif

/// Platform-safe associated object storage
/// On Apple platforms: uses Objective-C runtime
/// On Linux: uses static dictionary storage
internal enum AssociatedObjects {
    #if canImport(ObjectiveC)
    // Apple platforms: use Objective-C runtime
    static func get<T: AnyObject>(_ object: AnyObject, key: UnsafeRawPointer) -> T? {
        return objc_getAssociatedObject(object, key) as? T
    }
    
    static func set(_ object: AnyObject, key: UnsafeRawPointer, value: AnyObject?) {
        objc_setAssociatedObject(object, key, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    #else
    // Linux: use static dictionary storage with type-erased values
    private static var storage: [ObjectIdentifier: [UnsafeRawPointer: Any]] = [:]
    private static let lock = NSLock()
    
    static func get<T: AnyObject>(_ object: AnyObject, key: UnsafeRawPointer) -> T? {
        lock.lock()
        defer { lock.unlock() }
        let id = ObjectIdentifier(object)
        return storage[id]?[key] as? T
    }
    
    static func set(_ object: AnyObject, key: UnsafeRawPointer, value: AnyObject?) {
        lock.lock()
        defer { lock.unlock() }
        let id = ObjectIdentifier(object)
        if storage[id] == nil {
            storage[id] = [:]
        }
        if let value = value {
            storage[id]?[key] = value
        } else {
            storage[id]?.removeValue(forKey: key)
            if storage[id]?.isEmpty == true {
                storage.removeValue(forKey: id)
            }
        }
    }
    
    // Helper for value types (String, Bool, etc.)
    static func getValue<T>(_ object: AnyObject, key: UnsafeRawPointer) -> T? {
        lock.lock()
        defer { lock.unlock() }
        let id = ObjectIdentifier(object)
        return storage[id]?[key] as? T
    }
    
    static func setValue(_ object: AnyObject, key: UnsafeRawPointer, value: Any?) {
        lock.lock()
        defer { lock.unlock() }
        let id = ObjectIdentifier(object)
        if storage[id] == nil {
            storage[id] = [:]
        }
        if let value = value {
            storage[id]?[key] = value
        } else {
            storage[id]?.removeValue(forKey: key)
            if storage[id]?.isEmpty == true {
                storage.removeValue(forKey: id)
            }
        }
    }
    #endif
}

