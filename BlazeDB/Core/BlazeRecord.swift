//  BlazeRecord.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
import Foundation

public protocol BlazeRecord: Codable {
    static var collection: String { get }
    var id: UUID { get }
    var createdAt: Date { get }
}
