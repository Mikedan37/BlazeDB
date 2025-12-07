//
//  TypeSafeModels.swift
//  BlazeDB Examples
//
//  Example type-safe models showing how to use BlazeDocument protocol.
//  These serve as templates for creating your own type-safe models.
//
//  Created by Michael Danylchuk on 7/1/25.
//

import Foundation
import BlazeDB

// MARK: - Example 1: Simple Bug Model

struct Bug: BlazeDocument {
    var id: UUID
    var title: String
    var priority: Int
    var status: String
    var assignee: String?
    var createdAt: Date
    
    // Computed properties work!
    var isHighPriority: Bool {
        priority >= 7
    }
    
    var isOpen: Bool {
        status == "open"
    }
    
    // MARK: - BlazeDocument Protocol
    
    func toStorage() throws -> BlazeDataRecord {
        var fields: [String: BlazeDocumentField] = [
            "id": .uuid(id),
            "title": .string(title),
            "priority": .int(priority),
            "status": .string(status),
            "createdAt": .date(createdAt)
        ]
        
        if let assignee = assignee {
            fields["assignee"] = .string(assignee)
        }
        
        return BlazeDataRecord(fields)
    }
    
    init(from storage: BlazeDataRecord) throws {
        self.id = try storage.uuid("id")
        self.title = try storage.string("title")
        self.priority = try storage.int("priority")
        self.status = try storage.string("status")
        self.createdAt = try storage.date("createdAt")
        self.assignee = storage.stringOptional("assignee")
    }
    
    // MARK: - Convenience Initializers
    
    init(id: UUID = UUID(), title: String, priority: Int, status: String, assignee: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.priority = priority
        self.status = status
        self.assignee = assignee
        self.createdAt = createdAt
    }
}

// MARK: - Example 2: User Model with Nested Data

struct User: BlazeDocument {
    var id: UUID
    var name: String
    var email: String
    var role: String
    var profile: UserProfile?
    var settings: UserSettings
    var createdAt: Date
    
    struct UserProfile: Codable, Equatable {
        var avatar: String
        var bio: String
        var location: String?
    }
    
    struct UserSettings: Codable, Equatable {
        var theme: String
        var notifications: Bool
        var language: String
    }
    
    // MARK: - BlazeDocument Protocol
    
    func toStorage() throws -> BlazeDataRecord {
        var fields: [String: BlazeDocumentField] = [
            "id": .uuid(id),
            "name": .string(name),
            "email": .string(email),
            "role": .string(role),
            "createdAt": .date(createdAt)
        ]
        
        // Encode nested structures as JSON
        if let profile = profile {
            let encoder = JSONEncoder()
            let data = try encoder.encode(profile)
            fields["profile"] = .data(data)
        }
        
        let settingsData = try JSONEncoder().encode(settings)
        fields["settings"] = .data(settingsData)
        
        return BlazeDataRecord(fields)
    }
    
    init(from storage: BlazeDataRecord) throws {
        self.id = try storage.uuid("id")
        self.name = try storage.string("name")
        self.email = try storage.string("email")
        self.role = try storage.string("role")
        self.createdAt = try storage.date("createdAt")
        
        // Decode nested structures
        if let profileData = storage.dataOptional("profile") {
            self.profile = try? JSONDecoder().decode(UserProfile.self, from: profileData)
        } else {
            self.profile = nil
        }
        
        let settingsData = try storage.data("settings")
        self.settings = try JSONDecoder().decode(UserSettings.self, from: settingsData)
    }
    
    // MARK: - Convenience Initializers
    
    init(
        id: UUID = UUID(),
        name: String,
        email: String,
        role: String,
        profile: UserProfile? = nil,
        settings: UserSettings = UserSettings(theme: "light", notifications: true, language: "en"),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.role = role
        self.profile = profile
        self.settings = settings
        self.createdAt = createdAt
    }
}

// MARK: - Example 3: Project Model with Arrays

struct Project: BlazeDocument {
    var id: UUID
    var name: String
    var description: String
    var tags: [String]
    var memberIDs: [UUID]
    var metadata: [String: String]
    var createdAt: Date
    var updatedAt: Date
    
    // MARK: - BlazeDocument Protocol
    
    func toStorage() throws -> BlazeDataRecord {
        return BlazeDataRecord([
            "id": .uuid(id),
            "name": .string(name),
            "description": .string(description),
            "tags": .array(tags.map { .string($0) }),
            "memberIDs": .array(memberIDs.map { .uuid($0) }),
            "metadata": .dictionary(metadata.mapValues { .string($0) }),
            "createdAt": .date(createdAt),
            "updatedAt": .date(updatedAt)
        ])
    }
    
    init(from storage: BlazeDataRecord) throws {
        self.id = try storage.uuid("id")
        self.name = try storage.string("name")
        self.description = try storage.string("description")
        
        // Extract arrays
        let tagsArray = try storage.array("tags")
        self.tags = tagsArray.stringValues
        
        let memberIDsArray = try storage.array("memberIDs")
        self.memberIDs = memberIDsArray.compactMap { $0.uuidValue }
        
        // Extract dictionary
        let metadataDict = try storage.dictionary("metadata")
        self.metadata = metadataDict.stringValues
        
        self.createdAt = try storage.date("createdAt")
        self.updatedAt = try storage.date("updatedAt")
    }
    
    // MARK: - Convenience Initializers
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        tags: [String] = [],
        memberIDs: [UUID] = [],
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.tags = tags
        self.memberIDs = memberIDs
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Example 4: Hybrid Model (Type-Safe + Dynamic)

struct Task: BlazeDocument {
    var id: UUID
    var title: String
    var completed: Bool
    var dueDate: Date?
    
    // Access to underlying storage for dynamic fields
    private var _storage: BlazeDataRecord
    
    // Dynamic field access
    subscript(key: String) -> BlazeDocumentField? {
        get { _storage.storage[key] }
        set {
            if let newValue = newValue {
                _storage.storage[key] = newValue
            } else {
                _storage.storage.removeValue(forKey: key)
            }
        }
    }
    
    // Custom metadata accessor
    var customMetadata: [String: BlazeDocumentField] {
        get {
            return _storage.storage.filter { key, _ in
                !["id", "title", "completed", "dueDate"].contains(key)
            }
        }
        set {
            // Remove old custom fields
            for key in _storage.storage.keys {
                if !["id", "title", "completed", "dueDate"].contains(key) {
                    _storage.storage.removeValue(forKey: key)
                }
            }
            // Add new custom fields
            for (key, value) in newValue {
                _storage.storage[key] = value
            }
        }
    }
    
    // MARK: - BlazeDocument Protocol
    
    func toStorage() throws -> BlazeDataRecord {
        return _storage
    }
    
    init(from storage: BlazeDataRecord) throws {
        self._storage = storage
        self.id = try storage.uuid("id")
        self.title = try storage.string("title")
        self.completed = try storage.bool("completed")
        self.dueDate = storage.dateOptional("dueDate")
    }
    
    // MARK: - Convenience Initializers
    
    init(id: UUID = UUID(), title: String, completed: Bool = false, dueDate: Date? = nil) {
        self.id = id
        self.title = title
        self.completed = completed
        self.dueDate = dueDate
        
        var fields: [String: BlazeDocumentField] = [
            "id": .uuid(id),
            "title": .string(title),
            "completed": .bool(completed)
        ]
        
        if let dueDate = dueDate {
            fields["dueDate"] = .date(dueDate)
        }
        
        self._storage = BlazeDataRecord(fields)
    }
}

// MARK: - Usage Examples

extension Bug {
    /// Example: Create a high-priority bug
    static func highPriority(title: String, assignee: String? = nil) -> Bug {
        return Bug(
            title: title,
            priority: 8,
            status: "open",
            assignee: assignee
        )
    }
    
    /// Example: Create a low-priority bug
    static func lowPriority(title: String) -> Bug {
        return Bug(
            title: title,
            priority: 2,
            status: "open"
        )
    }
}

extension Task {
    /// Example: Add custom metadata
    mutating func addMetadata(key: String, value: BlazeDocumentField) {
        self[key] = value
    }
    
    /// Example: Get custom metadata
    func getMetadata(key: String) -> BlazeDocumentField? {
        return self[key]
    }
}

