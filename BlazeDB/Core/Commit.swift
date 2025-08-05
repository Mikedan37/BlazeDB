//  Commit.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
import Foundation

public struct Commit: BlazeRecord, Equatable{
    public static let collection = "commits"
    public let id: UUID
    public let createdAt: Date
    public let message: String
    public let author: String

    public init(id: UUID, createdAt: Date, message: String, author: String) {
        self.id = id
        self.createdAt = createdAt
        self.message = message
        self.author = author
    }
}
