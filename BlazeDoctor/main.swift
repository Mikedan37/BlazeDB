//
//  main.swift
//  BlazeDoctor
//
//  Health check CLI tool for BlazeDB databases
//  Zero core changes - uses public APIs only
//

import Foundation
import BlazeDBCore

struct DoctorReport: Codable {
    let healthy: Bool
    let database: String
    let path: String
    let checks: [CheckResult]
    let stats: StatsSnapshot?
    let errors: [String]
    
    struct CheckResult: Codable {
        let name: String
        let passed: Bool
        let message: String
    }
    
    struct StatsSnapshot: Codable {
        let pageCount: Int
        let recordCount: Int
        let databaseSize: Int64
        let isEncrypted: Bool
        let walSize: Int64?
        let lastCheckpoint: String?
        let cacheHitRate: Double
        let indexCount: Int
    }
}

func runDoctor(dbPath: String, password: String, jsonOutput: Bool) {
    var healthy = true
    var databaseName = ""
    var checks: [DoctorReport.CheckResult] = []
    var errors: [String] = []
    
    do {
        let url = URL(fileURLWithPath: dbPath)
        
        // Check 1: Database file exists
        if !FileManager.default.fileExists(atPath: dbPath) {
            checks.append(DoctorReport.CheckResult(
                name: "File Exists",
                passed: false,
                message: "Database file not found at path"
            ))
            healthy = false
            errors.append("Database file not found")
        } else {
            checks.append(DoctorReport.CheckResult(
                name: "File Exists",
                passed: true,
                message: "Database file found"
            ))
        }
        
        // Check 2: Open database (validates encryption key)
        let client: BlazeDBClient
        do {
            client = try BlazeDBClient(name: "doctor-check", fileURL: url, password: password)
            checks.append(DoctorReport.CheckResult(
                name: "Encryption Key",
                passed: true,
                message: "Encryption key valid, database opened successfully"
            ))
            databaseName = client.name
        } catch {
            checks.append(DoctorReport.CheckResult(
                name: "Encryption Key",
                passed: false,
                message: "Failed to open database: \(error.localizedDescription)"
            ))
            healthy = false
            errors.append("Encryption key validation failed: \(error.localizedDescription)")
            
            // Can't continue without valid client
            if jsonOutput {
                let report = DoctorReport(
                    healthy: healthy,
                    database: databaseName,
                    path: dbPath,
                    checks: checks,
                    stats: nil,
                    errors: errors
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                if let data = try? encoder.encode(report),
                   let json = String(data: data, encoding: .utf8) {
                    print(json)
                }
            } else {
                print("❌ Database Health Check Failed")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                for check in checks {
                    let icon = check.passed ? "✅" : "❌"
                    print("\(icon) \(check.name): \(check.message)")
                }
            }
            exit(1)
        }
        
        // Check 3: Layout integrity (try to read metadata)
        do {
            _ = try client.count()
            checks.append(DoctorReport.CheckResult(
                name: "Layout Integrity",
                passed: true,
                message: "Layout metadata readable and valid"
            ))
        } catch {
            checks.append(DoctorReport.CheckResult(
                name: "Layout Integrity",
                passed: false,
                message: "Layout corruption detected: \(error.localizedDescription)"
            ))
            healthy = false
            errors.append("Layout integrity check failed: \(error.localizedDescription)")
        }
        
        // Check 4: Read/Write cycle
        do {
            let testID = UUID()
            let testRecord = BlazeDataRecord([
                "_doctor_test": .bool(true),
                "_timestamp": .date(Date())
            ])
            
            // Write
            let insertedID = try client.insert(testRecord)
            
            // Read back
            if let readRecord = try client.fetch(id: insertedID),
               readRecord.storage["_doctor_test"] == .bool(true) {
                // Clean up test record
                try? client.delete(id: insertedID)
                
                checks.append(DoctorReport.CheckResult(
                    name: "Read/Write Cycle",
                    passed: true,
                    message: "Read/write cycle successful, test record inserted and deleted"
                ))
            } else {
                checks.append(DoctorReport.CheckResult(
                    name: "Read/Write Cycle",
                    passed: false,
                    message: "Read/write cycle failed - data mismatch"
                ))
                healthy = false
                errors.append("Read/write cycle validation failed")
            }
        } catch {
            checks.append(DoctorReport.CheckResult(
                name: "Read/Write Cycle",
                passed: false,
                message: "Read/write cycle failed: \(error.localizedDescription)"
            ))
            healthy = false
            errors.append("Read/write cycle failed: \(error.localizedDescription)")
        }
        
        // Gather stats (using safe APIs that don't require telemetry)
        var statsSnapshot: DoctorReport.StatsSnapshot? = nil
        do {
            let stats = try client.stats()
            
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            statsSnapshot = DoctorReport.StatsSnapshot(
                pageCount: stats.pageCount,
                recordCount: stats.recordCount,
                databaseSize: stats.databaseSize,
                isEncrypted: true,
                walSize: stats.walSize,
                lastCheckpoint: stats.lastCheckpoint.map { formatter.string(from: $0) },
                cacheHitRate: stats.cacheHitRate,
                indexCount: stats.indexCount
            )
        } catch {
            // Stats gathering failed, but not critical
            errors.append("Could not gather all statistics: \(error.localizedDescription)")
        }
        
        // Build final report
        let report = DoctorReport(
            healthy: healthy,
            database: databaseName,
            path: dbPath,
            checks: checks,
            stats: statsSnapshot,
            errors: errors
        )
        
        // Output
        if jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(report),
               let json = String(data: data, encoding: .utf8) {
                print(json)
            }
        } else {
            print("🔍 BlazeDB Doctor - Health Check Report")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("Database: \(report.database)")
            print("Path: \(report.path)")
            print("")
            
            for check in checks {
                let icon = check.passed ? "✅" : "❌"
                print("\(icon) \(check.name): \(check.message)")
            }
            
            // Health summary
            if !jsonOutput {
                do {
                    let health = try client.health()
                    print("")
                    print("🏥 Health Status: \(health.status.rawValue)")
                    if !health.reasons.isEmpty {
                        print("")
                        for reason in health.reasons {
                            print("  • \(reason)")
                        }
                    }
                    if !health.suggestedActions.isEmpty {
                        print("")
                        print("💡 Suggested Actions:")
                        for action in health.suggestedActions {
                            print("  • \(action)")
                        }
                    }
                } catch {
                    // Health check failed, but not critical
                    errors.append("Could not determine health: \(error.localizedDescription)")
                }
            }
            
            if let stats = report.stats {
                print("")
                if !jsonOutput {
                    // Pretty print stats with interpretation
                    print("📊 Statistics:")
                    // Use DatabaseStats interpretation if available
                    if let dbStats = try? client.stats() {
                        print(dbStats.interpretation)
                    }
                    print("  Encrypted: \(stats.isEncrypted ? "Yes" : "No")")
                }
            }
            
            if !errors.isEmpty {
                print("")
                print("⚠️  Issues Found:")
                for error in errors {
                    print("  - \(error)")
                }
                print("")
                print("💡 For detailed error guidance, run with --verbose")
            }
            
            print("")
            if report.healthy {
                print("✅ Database is healthy")
            } else {
                print("❌ Database health check failed")
            }
        }
        
        exit(report.healthy ? 0 : 1)
        
        } catch {
            // Build error report
            let report = DoctorReport(
                healthy: false,
                database: "",
                path: dbPath,
                checks: [],
                stats: nil,
                errors: [error.localizedDescription]
            )
            
            let errorMsg: String
            let errorGuidance: String
            
            if let blazeError = error as? BlazeDBError {
                errorMsg = blazeError.errorDescription ?? error.localizedDescription
                errorGuidance = blazeError.guidance
            } else {
                errorMsg = error.localizedDescription
                errorGuidance = "See error details above."
            }
            
            errors.append(errorMsg)
            
            // Build error report
            let errorReport = DoctorReport(
                healthy: false,
                database: "",
                path: dbPath,
                checks: [],
                stats: nil,
                errors: errors
            )
            
            if jsonOutput {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                if let data = try? encoder.encode(errorReport),
                   let json = String(data: data, encoding: .utf8) {
                    print(json)
                }
            } else {
                if let blazeError = error as? BlazeDBError {
                    print(blazeError.formattedDescription)
                } else {
                    print("❌ Error: \(errorMsg)")
                    print("   💡 \(errorGuidance)")
                }
            }
            
            exit(1)
        }
}

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

// Parse command line arguments
let args = CommandLine.arguments

if args.contains("--help") || args.contains("-h") {
    print("""
    BlazeDB Doctor - Health Check Tool
    
    Usage:
      blazedb doctor <db-path> <password> [--json]
    
    Options:
      --json    Output results as JSON (for scripting)
      -h, --help    Show this help message
    
    Examples:
      blazedb doctor /path/to/db.blazedb mypassword
      blazedb doctor /path/to/db.blazedb mypassword --json
    
    Exit codes:
      0    Database is healthy
      1    Database health check failed
    """)
    exit(0)
}

let jsonOutput = args.contains("--json")

guard args.count >= 3 else {
    print("Error: Missing required arguments")
    print("Usage: blazedb doctor <db-path> <password> [--json]")
    print("Use --help for more information")
    exit(1)
}

let dbPath = args[1]
let password = args[2]

runDoctor(dbPath: dbPath, password: password, jsonOutput: jsonOutput)
