//  ProjectMapper.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.

import Foundation
import BlazeDB

/// ProjectMapper maps code structure into a visual graph model for Blaze Studio.
/// It identifies files, functions, and relationships between them.
final class ProjectMapper {
    private let fileManager = FileManager.default

    /// Scans the given directory for Swift files and maps project structure.
    func mapProject(at rootURL: URL) throws -> [ProjectComponent] {
        let fileURLs = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        var components: [ProjectComponent] = []

        for fileURL in fileURLs {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let component = parseFile(source: source, filename: fileURL.lastPathComponent)
            components.append(component)
        }

        return components
    }

    /// Parses a single Swift file into a ProjectComponent.
    private func parseFile(source: String, filename: String) -> ProjectComponent {
        let functionMatches = source.components(separatedBy: "\n")
            .filter { $0.contains("func ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }

        return ProjectComponent(
            id: UUID(),
            filename: filename,
            functions: functionMatches
        )
    }
}

/// A basic model representing a Swift file and its functions.
struct ProjectComponent: Identifiable {
    let id: UUID
    let filename: String
    let functions: [String]
}
