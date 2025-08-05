//  ProjectModel.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.

import Foundation

struct ProjectModel: Codable {
    var name: String
    var blocks: [Block]
}
