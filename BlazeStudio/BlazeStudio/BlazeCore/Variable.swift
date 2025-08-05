//  Variable.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.

import Foundation

struct Variable: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var type: String
    var defaultValue: String?
    var description: String?
}
