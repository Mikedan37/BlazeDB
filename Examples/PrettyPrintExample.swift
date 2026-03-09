//
//  PrettyPrintExample.swift
//  Example of pretty-printing database to text file for debugging
//

import Foundation
import BlazeDB

func runPrettyPrintExample() {
    print("🖨️  Pretty Print Example - Debug Database Export\n")
    
    do {
        // Create database
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("example.blazedb")
        
        let db = try BlazeDBClient.open(at: dbURL, password: "TestPass-123456!")
        
        // Insert sample data
        print("Creating sample bugs...")
        
        try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("App crashes on startup"),
            "description": .string("Users report immediate crash when launching app"),
            "priority": .int(5),
            "status": .string("open"),
            "createdAt": .date(Date()),
            "tags": .array([.string("crash"), .string("critical"), .string("p0")]),
            "metadata": .dictionary([
                "version": .string("1.0.3"),
                "platform": .string("iOS"),
                "deviceCount": .int(15)
            ])
        ]))
        
        try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Login button not responding"),
            "description": .string("Tap on login button does nothing"),
            "priority": .int(3),
            "status": .string("in_progress"),
            "createdAt": .date(Date()),
            "tags": .array([.string("ui"), .string("login")])
        ]))
        
        try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Typo in settings"),
            "description": .string("'Prefernces' instead of 'Preferences'"),
            "priority": .int(1),
            "status": .string("open"),
            "createdAt": .date(Date()),
            "tags": .array([.string("typo"), .string("ui")])
        ]))
        
        print("✅ Created 3 sample bugs\n")
        
        // EXAMPLE 1: Pretty-print to file
        print("═══════════════════════════════════════════════════════")
        print("EXAMPLE 1: Pretty-Print to Text File")
        print("═══════════════════════════════════════════════════════\n")
        
        let textFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bugs_debug.txt")
        
        try db.prettyPrintToFile(textFileURL, options: .default)
        
        print("✅ Exported to: \(textFileURL.path)\n")
        
        // Show content
        let content = try String(contentsOf: textFileURL)
        print("File preview:")
        print(content.prefix(500))
        print("...\n")
        
        // EXAMPLE 2: Quick console dump
        print("\n═══════════════════════════════════════════════════════")
        print("EXAMPLE 2: Quick Console Dump")
        print("═══════════════════════════════════════════════════════\n")
        
        try db.prettyPrint(limit: 10)
        
        // EXAMPLE 3: Debug dump
        print("\n═══════════════════════════════════════════════════════")
        print("EXAMPLE 3: Debug Dump (Quick View)")
        print("═══════════════════════════════════════════════════════\n")
        
        try db.debugDump(limit: 3)
        
        // EXAMPLE 4: Export schema
        print("\n═══════════════════════════════════════════════════════")
        print("EXAMPLE 4: Export Database Schema")
        print("═══════════════════════════════════════════════════════\n")
        
        let schemaURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema.txt")
        
        try db.exportSchema(schemaURL)
        
        let schemaContent = try String(contentsOf: schemaURL)
        print(schemaContent)
        
        // EXAMPLE 5: Export as Markdown table
        print("\n═══════════════════════════════════════════════════════")
        print("EXAMPLE 5: Export as Markdown Table")
        print("═══════════════════════════════════════════════════════\n")
        
        let markdownURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bugs.md")
        
        try db.exportAsMarkdownTable(markdownURL, fields: ["title", "priority", "status"])
        
        let markdown = try String(contentsOf: markdownURL)
        print(markdown)
        
        // EXAMPLE 6: Export as CSV
        print("\n═══════════════════════════════════════════════════════")
        print("EXAMPLE 6: Export as CSV")
        print("═══════════════════════════════════════════════════════\n")
        
        let csvURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bugs.csv")
        
        try db.exportAsCSV(csvURL, fields: ["title", "priority", "status", "createdAt"])
        
        let csv = try String(contentsOf: csvURL)
        print(csv)
        
        // Cleanup
        try? FileManager.default.removeItem(at: dbURL)
        
        print("\n✅ Pretty Print Example Complete!")
        print("\nUseful commands:")
        print("  • db.prettyPrintToFile(url) - Full export to text file")
        print("  • db.prettyPrint(limit: 10) - Quick console view")
        print("  • db.debugDump(limit: 5) - Quick debug dump")
        print("  • db.exportSchema(url) - Database structure")
        print("  • db.exportAsMarkdownTable(url, fields:) - Markdown table")
        print("  • db.exportAsCSV(url, fields:) - CSV export")
        
    } catch {
        print("❌ Error: \(error)")
    }
}

// Run example
// runPrettyPrintExample()

