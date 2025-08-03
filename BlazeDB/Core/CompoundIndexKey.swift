import Foundation

//extension BlazeDB_CompoundIndexKey: Codable {
//    public func encode(to encoder: Encoder) throws {
//        var container = encoder.unkeyedContainer()
//        for value in components {
//            switch value {
//            case let v as String:
//                try container.encode("str")
//                try container.encode(v)
//            case let v as Int:
//                try container.encode("int")
//                try container.encode(v)
//            case let v as Double:
//                try container.encode("dbl")
//                try container.encode(v)
//            case let v as Bool:
//                try container.encode("bool")
//                try container.encode(v)
//            case let v as Date:
//                try container.encode("date")
//                try container.encode(v.timeIntervalSince1970)
//            case let v as UUID:
//                try container.encode("uuid")
//                try container.encode(v.uuidString)
//            default:
//                throw EncodingError.invalidValue(value, .init(codingPath: container.codingPath, debugDescription: "Unsupported key component: \(type(of: value))"))
//            }
//        }
//    }
//
//    public init(from decoder: Decoder) throws {
//        var container = try decoder.unkeyedContainer()
//        var comps: [AnyHashable] = []
//        while !container.isAtEnd {
//            let type = try container.decode(String.self)
//            switch type {
//            case "str":
//                comps.append(try container.decode(String.self))
//            case "int":
//                comps.append(try container.decode(Int.self))
//            case "dbl":
//                comps.append(try container.decode(Double.self))
//            case "bool":
//                comps.append(try container.decode(Bool.self))
//            case "date":
//                comps.append(Date(timeIntervalSince1970: try container.decode(Double.self)))
//            case "uuid":
//                comps.append(UUID(uuidString: try container.decode(String.self)) ?? UUID())
//            default:
//                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown key type \(type)")
//            }
//        }
//        self.init(comps)
//    }
//}
