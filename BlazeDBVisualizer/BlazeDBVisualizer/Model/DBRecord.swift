//  DBRecord.swift
//  BlazeDBVisualizer
//  Created by Michael Danylchuk on 6/29/25.
//

import Foundation
import BlazeDB

struct DBRecord {
    var id: UUID
    var path: String
    var appName: String
    var sizeInBytes: Int
    var modifiedDate: Date
    var isEncrypted: Bool

    var fileURL: URL {
        URL(fileURLWithPath: path)
    }

    init(
        id: UUID = UUID(),
        path: String,
        appName: String,
        sizeInBytes: Int,
        modifiedDate: Date,
        isEncrypted: Bool = false
    ) {
        self.id = id
        self.path = path
        self.appName = appName
        self.sizeInBytes = sizeInBytes
        self.modifiedDate = modifiedDate
        self.isEncrypted = isEncrypted
    }

    init?(from document: [String: BlazeDocumentField]) {
        guard
            case let .string(idStr)? = document["id"],
            let id = UUID(uuidString: idStr),
            case let .string(path)? = document["path"],
            case let .string(appName)? = document["appName"],
            case let .int(size)? = document["sizeInBytes"],
            case let .string(dateStr)? = document["modifiedDate"],
            let modifiedDate = ISO8601DateFormatter().date(from: dateStr),
            case let .bool(isEncrypted)? = document["isEncrypted"]
        else {
            return nil
        }

        self.id = id
        self.path = path
        self.appName = appName
        self.sizeInBytes = size
        self.modifiedDate = modifiedDate
        self.isEncrypted = isEncrypted
    }

    func toDocument() -> [String: BlazeDocumentField] {
        return [
            "id": .string(id.uuidString),
            "path": .string(path),
            "appName": .string(appName),
            "sizeInBytes": .int(sizeInBytes),
            "modifiedDate": .string(ISO8601DateFormatter().string(from: modifiedDate)),
            "isEncrypted": .bool(isEncrypted)
        ]
    }
}
