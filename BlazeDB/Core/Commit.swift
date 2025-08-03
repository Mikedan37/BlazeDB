//  Commit.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.

import Foundation

struct Commit: BlazeRecord {
    static let collection = "commits"
    let id: UUID
    let createdAt: Date
    let message: String
    let author: String
}
