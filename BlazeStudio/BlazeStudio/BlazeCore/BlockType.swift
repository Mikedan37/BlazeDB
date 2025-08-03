//  BlockType.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.

enum BlockType: Codable, Equatable {
    case structure(StructureType)
    case logic(LogicType)

    var displayName: String {
        switch self {
        case .structure(let type): return type.displayName
        case .logic(let type): return type.displayName
        }
    }

    enum StructureType: String, Codable, CaseIterable {
        case `class`
        case connector

        var displayName: String {
            switch self {
            case .class: return "Class"
            case .connector: return "Connector"
            }
        }
    }

    enum LogicType: String, Codable, CaseIterable {
        case function
        case variable
        case constant
        case condition
        case loop

        var displayName: String {
            switch self {
            case .function: return "Function"
            case .variable: return "Variable"
            case .constant: return "Constant"
            case .condition: return "Condition"
            case .loop: return "Loop"
            }
        }
    }
    func encode() -> String {
        switch self {
        case .structure(let type):
            return "structure:\(type.rawValue)"
        case .logic(let type):
            return "logic:\(type.rawValue)"
        }
    }

    static func decode(from string: String) -> BlockType? {
        let components = string.split(separator: ":", maxSplits: 1).map(String.init)
        guard components.count == 2 else { return nil }

        switch components[0] {
        case "structure":
            return StructureType(rawValue: components[1]).map { .structure($0) }
        case "logic":
            return LogicType(rawValue: components[1]).map { .logic($0) }
        default:
            return nil
        }
    }
}
