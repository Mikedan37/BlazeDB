import Foundation

// MARK: - Direct Codable Support for BlazeDB

/// Allows any Codable type to be used directly with BlazeDB
/// WITHOUT needing BlazeDocument conformance or manual conversion
public protocol BlazeStorable: Codable, Identifiable where ID == UUID {
    var id: UUID { get set }
}

// MARK: - Automatic Conversion Helpers

extension BlazeStorable {
    
    /// Convert any Codable to BlazeDataRecord
    internal func toBlazeRecord() throws -> BlazeDataRecord {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let jsonData = try encoder.encode(self)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        
        guard let jsonObject = jsonObject else {
            throw BlazeDBError.transactionFailed("Failed to convert Codable to JSON")
        }
        
        var storage: [String: BlazeDocumentField] = [:]
        
        for (key, value) in jsonObject {
            storage[key] = try convertToBlazeField(value)
        }
        
        return BlazeDataRecord(storage)
    }
    
    /// Convert BlazeDataRecord back to Codable
    internal static func fromBlazeRecord(_ record: BlazeDataRecord) throws -> Self {
        var jsonObject: [String: Any] = [:]
        
        BlazeLogger.debug("fromBlazeRecord: Converting \(record.storage.count) fields")
        
        for (key, field) in record.storage {
            BlazeLogger.debug("  Processing field '\(key)': \(String(describing: field).prefix(100))...")
            // Handle dates stored as TimeInterval (Double)
            if case .double(let timestamp) = field, 
               (key.contains("At") || key.contains("Date") || key == "created" || key == "updated" || key == "timestamp") {
                // Convert timestamp back to Date, then to ISO8601 string for Codable
                let date = Date(timeIntervalSinceReferenceDate: timestamp)
                jsonObject[key] = ISO8601DateFormatter().string(from: date)
            }
            // Handle bools stored as integers (0/1)
            else if case .int(let intValue) = field,
                    (key.contains("is") || key.contains("has") || key.contains("can") || 
                     key.contains("should") || key == "active" || key == "enabled" || key == "disabled") {
                // Convert to actual bool for Codable
                jsonObject[key] = intValue != 0
            }
            else {
                jsonObject[key] = try convertToJSON(field)
            }
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: jsonObject)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(Self.self, from: jsonData)
    }
}

// MARK: - Conversion Helpers

private func convertToBlazeField(_ value: Any) throws -> BlazeDocumentField {
    switch value {
    case let str as String:
        return .string(str)
    case let num as Int:
        return .int(num)
    case let num as Double:
        return .double(num)
    case let bool as Bool:
        return .bool(bool)
    case let date as Date:
        return .date(date)
    case let uuid as UUID:
        return .uuid(uuid)
    case let data as Data:
        return .data(data)
    case let array as [Any]:
        let fields = try array.map { try convertToBlazeField($0) }
        return .array(fields)
    case let dict as [String: Any]:
        // Nested objects encoded as JSON strings
        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        return .string(jsonString)
    default:
        // Handle ISO8601 date strings
        if let str = value as? String, let date = ISO8601DateFormatter().date(from: str) {
            return .date(date)
        }
        throw BlazeDBError.transactionFailed("Unsupported type during Codable conversion: \(type(of: value))")
    }
}

private func convertToJSON(_ field: BlazeDocumentField) throws -> Any {
    switch field {
    case .string(let str):
        // Try to parse as nested JSON
        if let data = str.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            return json
        }
        return str
    case .int(let num):
        return num
    case .double(let num):
        return num
    case .bool(let bool):
        return bool
    case .date(let date):
        return ISO8601DateFormatter().string(from: date)
    case .uuid(let uuid):
        return uuid.uuidString
    case .data(let data):
        return data.base64EncodedString()
    case .array(let array):
        return try array.map { try convertToJSON($0) }
    case .dictionary(let dict):
        var jsonDict: [String: Any] = [:]
        for (key, value) in dict {
            jsonDict[key] = try convertToJSON(value)
        }
        return jsonDict
    case .vector(let vector):
        return vector.map { $0 }
    case .null:
        return NSNull()
    }
}

// MARK: - BlazeDBClient Codable Extensions

extension BlazeDBClient {
    
    // MARK: - Insert
    
    /// Insert any Codable type directly
    ///
    /// Example:
    /// ```swift
    /// struct Bug: Codable, Identifiable {
    ///     var id: UUID
    ///     var title: String
    ///     var priority: Int
    /// }
    ///
    /// let bug = Bug(id: UUID(), title: "Login broken", priority: 5)
    /// try db.insert(bug)
    /// ```
    public func insert<T: BlazeStorable>(_ object: T) throws -> UUID {
        let record = try object.toBlazeRecord()
        return try self.insert(record)
    }
    
    /// Insert Codable async
    public func insert<T: BlazeStorable>(_ object: T) async throws -> UUID {
        let record = try object.toBlazeRecord()
        return try await self.insert(record)
    }
    
    /// Insert many Codable objects
    public func insertMany<T: BlazeStorable>(_ objects: [T]) throws -> [UUID] {
        let records = try objects.map { try $0.toBlazeRecord() }
        return try self.insertMany(records)
    }
    
    /// Insert many async
    public func insertMany<T: BlazeStorable>(_ objects: [T]) async throws -> [UUID] {
        let records = try objects.map { try $0.toBlazeRecord() }
        return try await self.insertMany(records)
    }
    
    // MARK: - Fetch
    
    /// Fetch Codable type by ID
    ///
    /// Example:
    /// ```swift
    /// let bug = try db.fetch(Bug.self, id: bugID)
    /// print(bug?.title)
    /// ```
    public func fetch<T: BlazeStorable>(_ type: T.Type, id: UUID) throws -> T? {
        guard let record = try self.fetch(id: id) else {
            return nil
        }
        return try T.fromBlazeRecord(record)
    }
    
    /// Fetch async
    public func fetch<T: BlazeStorable>(_ type: T.Type, id: UUID) async throws -> T? {
        guard let record = try await self.fetch(id: id) else {
            return nil
        }
        return try T.fromBlazeRecord(record)
    }
    
    /// Fetch all as Codable type
    public func fetchAll<T: BlazeStorable>(_ type: T.Type) throws -> [T] {
        let records = try self.fetchAll()
        return try records.map { try T.fromBlazeRecord($0) }
    }
    
    /// Fetch all async
    public func fetchAll<T: BlazeStorable>(_ type: T.Type) async throws -> [T] {
        let records = try await self.fetchAll()
        return try records.map { try T.fromBlazeRecord($0) }
    }
    
    // MARK: - Update
    
    /// Update Codable object
    public func update<T: BlazeStorable>(_ object: T) throws {
        let record = try object.toBlazeRecord()
        try self.update(id: object.id, with: record)
    }
    
    /// Update async
    public func update<T: BlazeStorable>(_ object: T) async throws {
        let record = try object.toBlazeRecord()
        try await self.update(id: object.id, data: record)
    }
    
    /// Update many Codable objects
    public func updateMany<T: BlazeStorable>(_ objects: [T]) throws {
        for object in objects {
            try self.update(object)
        }
    }
    
    /// Update many async
    public func updateMany<T: BlazeStorable>(_ objects: [T]) async throws {
        for object in objects {
            try await self.update(object)
        }
    }
    
    // Note: Type-safe query builder is defined in QueryBuilderKeyPath.swift
    // This avoids duplication and uses the KeyPath-enabled builder
}

