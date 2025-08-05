//  StorageDashboardStats.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/21/25.
import Foundation

public struct StorageDashboardStats: Codable {
    public let totalPages: Int
    public let orphanedPages: Int
    public let estimatedDBSizeKB: Int
    public let recordCount: Int
    public let maxRecordSizeBytes: Int
    public let lastCleanup: Date?
    public let pageWarnings: Int
}
