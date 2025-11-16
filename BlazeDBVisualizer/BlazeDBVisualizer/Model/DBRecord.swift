//  DBRecord.swift
//  BlazeDBVisualizer
//  Created by Michael Danylchuk on 6/29/25.
//
//  ✅ UPGRADED: Now includes full BlazeDB monitoring data
//  ✅ Health status, performance metrics, schema info
//  ✅ Perfect for dashboard and management features
//

import Foundation
import BlazeDB

/// Enriched database record with monitoring metadata
/// Contains all information needed for database management UI
struct DBRecord: Identifiable {
    // MARK: - Basic Info
    var id: UUID
    var name: String
    var path: String
    var appName: String
    var sizeInBytes: Int
    var recordCount: Int
    var modifiedDate: Date
    var isEncrypted: Bool
    
    // MARK: - Health & Performance
    var healthStatus: String  // "healthy", "warning", "critical", "unknown"
    var fragmentationPercent: Double?
    var needsVacuum: Bool
    var mvccEnabled: Bool?
    var indexCount: Int?
    
    // MARK: - Extended Monitoring (optional, requires unlock)
    var warnings: [String]?
    var formatVersion: String?
    var totalPages: Int?
    var orphanedPages: Int?
    var gcRunCount: Int?
    var obsoleteVersions: Int?
    
    var fileURL: URL {
        URL(fileURLWithPath: path)
    }
    
    // MARK: - Computed Properties
    
    var healthColor: String {
        switch healthStatus {
        case "healthy": return "green"
        case "warning": return "yellow"
        case "critical": return "red"
        default: return "gray"
        }
    }
    
    var healthIcon: String {
        switch healthStatus {
        case "healthy": return "checkmark.circle.fill"
        case "warning": return "exclamationmark.triangle.fill"
        case "critical": return "xmark.octagon.fill"
        default: return "questionmark.circle"
        }
    }
    
    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeInBytes), countStyle: .file)
    }
    
    var needsMaintenance: Bool {
        needsVacuum || (fragmentationPercent ?? 0) > 30 || (obsoleteVersions ?? 0) > 1000
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        appName: String,
        sizeInBytes: Int,
        recordCount: Int = 0,
        modifiedDate: Date,
        isEncrypted: Bool = false,
        healthStatus: String = "unknown",
        fragmentationPercent: Double? = nil,
        needsVacuum: Bool = false,
        mvccEnabled: Bool? = nil,
        indexCount: Int? = nil,
        warnings: [String]? = nil,
        formatVersion: String? = nil,
        totalPages: Int? = nil,
        orphanedPages: Int? = nil,
        gcRunCount: Int? = nil,
        obsoleteVersions: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.appName = appName
        self.sizeInBytes = sizeInBytes
        self.recordCount = recordCount
        self.modifiedDate = modifiedDate
        self.isEncrypted = isEncrypted
        self.healthStatus = healthStatus
        self.fragmentationPercent = fragmentationPercent
        self.needsVacuum = needsVacuum
        self.mvccEnabled = mvccEnabled
        self.indexCount = indexCount
        self.warnings = warnings
        self.formatVersion = formatVersion
        self.totalPages = totalPages
        self.orphanedPages = orphanedPages
        self.gcRunCount = gcRunCount
        self.obsoleteVersions = obsoleteVersions
    }
}
