import Foundation

public enum BlazeDocumentField: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case uuid(UUID)
    case data(Data)
    case array([BlazeDocumentField])
    case dictionary([String: BlazeDocumentField])
    case vector([Double])
    case null
    
    public var value: Any {
        switch self {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .date(let v): return v
        case .uuid(let v): return v
        case .data(let v): return v
        case .array(let v): return v
        case .dictionary(let v): return v
        case .vector(let v): return v
        case .null: return NSNull()
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
            return
        }
        
        // Try to decode as Int first (most common type, and avoids Bool false positives)
        // Then try Bool, then Double, etc.
        // This order prevents issues where numbers are incorrectly decoded as Bool
        if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(UUID.self) {
            self = .uuid(v)
        } else if let v = try? container.decode(Date.self) {
            self = .date(v)
        } else if let v = try? container.decode([Double].self) {
            self = .vector(v)
        } else if let v = try? container.decode([BlazeDocumentField].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: BlazeDocumentField].self) {
            self = .dictionary(v)
        } else if let stringValue = try? container.decode(String.self) {
            if !stringValue.isEmpty {
                let hasPadding = stringValue.hasSuffix("=") || stringValue.hasSuffix("==")
                let isBase64Chars = stringValue.allSatisfy { char in
                    char.isLetter || char.isNumber || char == "+" || char == "/" || char == "="
                }
                let uniqueChars = Set(stringValue)
                let hasLowEntropy = uniqueChars.count < 4
                
                let isLikelyBase64: Bool
                if hasPadding && isBase64Chars && !hasLowEntropy {
                    isLikelyBase64 = true
                } else if !hasPadding && isBase64Chars && stringValue.count > 16 && !hasLowEntropy {
                    isLikelyBase64 = true
                } else {
                    isLikelyBase64 = false
                }
                
                if isLikelyBase64, let data = Data(base64Encoded: stringValue) {
                    self = .data(data)
                } else {
                    self = .string(stringValue)
                }
            } else {
                self = .string(stringValue)
            }
        } else {
            throw DecodingError.typeMismatch(
                BlazeDocumentField.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid value type for BlazeDocumentField"
                )
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .date(let v): try container.encode(v)
        case .uuid(let v): try container.encode(v)
        case .data(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        case .vector(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

public extension BlazeDocumentField {
    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }
    
    var intValue: Int? {
        switch self {
        case let .int(value):
            return value
        case let .double(value):
            guard value.isFinite else { return nil }
            let truncated = value.rounded(.towardZero)
            guard truncated >= Double(Int.min), truncated <= Double(Int.max) else {
                return nil
            }
            return Int(truncated)
        default:
            return nil
        }
    }
    
    var doubleValue: Double? {
        if case let .double(value) = self { return value }
        if case let .int(value) = self { return Double(value) }
        return nil
    }
    
    var dateValue: Date? {
        if case let .date(value) = self { return value }
        if case let .double(timestamp) = self { return Date(timeIntervalSinceReferenceDate: timestamp) }
        if case let .int(timestamp) = self { return Date(timeIntervalSinceReferenceDate: Double(timestamp)) }
        if case let .string(isoString) = self {
            return DynamicCollection.cachedISO8601Formatter.date(from: isoString)
        }
        return nil
    }
    
    var dataValue: Data? {
        if case let .data(value) = self { return value }
        if case let .string(value) = self {
            if value.isEmpty {
                return Data()
            }
            if let data = Data(base64Encoded: value) {
                return data
            }
        }
        return nil
    }
    
    var uuidValue: UUID? {
        if case let .uuid(value) = self { return value }
        if case let .string(value) = self { return UUID(uuidString: value) }
        return nil
    }
    
    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        if case let .int(value) = self { return value != 0 }
        return nil
    }
    
    var arrayValue: [BlazeDocumentField]? {
        if case let .array(value) = self { return value }
        return nil
    }
    
    var dictionaryValue: [String: BlazeDocumentField]? {
        if case let .dictionary(value) = self { return value }
        return nil
    }
}

