//
//  ResourceLimitsTests.swift
//  BlazeDBTests
//
//  Tests for resource bounds and warnings: WAL growth, page count, disk usage
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import XCTest
@testable import BlazeDBCore

final class ResourceLimitsTests: XCTestCase {
    
    func testResourceLimits_WALSizeWarning() {
        let stats = DatabaseStats(
            pageCount: 100,
            walSize: 6_000_000, // 6 MB
            lastCheckpoint: Date(),
            cacheHitRate: 0.85,
            indexCount: 5,
            recordCount: 1000,
            databaseSize: 10_000_000 // 10 MB (WAL is 60%)
        )
        
        let warnings = DatabaseHealth.checkResourceLimits(stats: stats)
        XCTAssertFalse(warnings.isEmpty, "Should warn about large WAL")
        XCTAssertTrue(warnings.contains { $0.contains("WAL size") }, "Warning should mention WAL size")
        XCTAssertTrue(warnings.contains { $0.contains("checkpoint") || $0.contains("vacuum") }, "Warning should suggest action")
    }
    
    func testResourceLimits_PageCountWarning() {
        let stats = DatabaseStats(
            pageCount: 1_500_000, // Exceeds default limit of 1M
            walSize: 1_000_000,
            lastCheckpoint: Date(),
            cacheHitRate: 0.85,
            indexCount: 5,
            recordCount: 1000,
            databaseSize: 10_000_000
        )
        
        let warnings = DatabaseHealth.checkResourceLimits(stats: stats)
        XCTAssertFalse(warnings.isEmpty, "Should warn about high page count")
        XCTAssertTrue(warnings.contains { $0.contains("Page count") }, "Warning should mention page count")
    }
    
    func testResourceLimits_DiskUsageWarning() {
        let stats = DatabaseStats(
            pageCount: 100,
            walSize: 1_000_000,
            lastCheckpoint: Date(),
            cacheHitRate: 0.85,
            indexCount: 5,
            recordCount: 1000,
            databaseSize: 15_000_000_000 // 15 GB (exceeds default 10GB limit)
        )
        
        let warnings = DatabaseHealth.checkResourceLimits(stats: stats)
        XCTAssertFalse(warnings.isEmpty, "Should warn about large database size")
        XCTAssertTrue(warnings.contains { $0.contains("Database size") }, "Warning should mention database size")
    }
    
    func testResourceLimits_NoWarningsWhenNormal() {
        let stats = DatabaseStats(
            pageCount: 100,
            walSize: 1_000_000, // 1 MB (10% of DB size)
            lastCheckpoint: Date(),
            cacheHitRate: 0.85,
            indexCount: 5,
            recordCount: 1000,
            databaseSize: 10_000_000 // 10 MB
        )
        
        let warnings = DatabaseHealth.checkResourceLimits(stats: stats)
        XCTAssertTrue(warnings.isEmpty, "Should not warn when limits are normal")
    }
    
    func testResourceLimits_CustomLimits() {
        let customLimits = DatabaseHealth.ResourceLimits(
            maxWALSizeRatio: 0.3, // 30% instead of 50%
            maxPageCount: 500_000,
            maxDiskUsageBytes: 5_000_000_000 // 5 GB instead of 10 GB
        )
        
        let stats = DatabaseStats(
            pageCount: 100,
            walSize: 4_000_000, // 4 MB (40% of DB size - exceeds 30% limit)
            lastCheckpoint: Date(),
            cacheHitRate: 0.85,
            indexCount: 5,
            recordCount: 1000,
            databaseSize: 10_000_000
        )
        
        let warnings = DatabaseHealth.checkResourceLimits(stats: stats, limits: customLimits)
        XCTAssertFalse(warnings.isEmpty, "Should warn with custom limits")
    }
    
    func testResourceLimits_RefuseWritesWhenEnabled() {
        let limits = DatabaseHealth.ResourceLimits(
            maxWALSizeRatio: 0.5,
            maxPageCount: 1_000_000,
            maxDiskUsageBytes: 10_000_000_000,
            refuseWritesOnLimit: true
        )
        
        let stats = DatabaseStats(
            pageCount: 1_500_000, // Exceeds limit
            walSize: 1_000_000,
            lastCheckpoint: Date(),
            cacheHitRate: 0.85,
            indexCount: 5,
            recordCount: 1000,
            databaseSize: 10_000_000
        )
        
        let shouldRefuse = DatabaseHealth.shouldRefuseWrites(stats: stats, limits: limits)
        XCTAssertTrue(shouldRefuse, "Should refuse writes when limit exceeded and refuseWritesOnLimit is true")
    }
    
    func testResourceLimits_DoNotRefuseWhenDisabled() {
        let limits = DatabaseHealth.ResourceLimits(
            maxWALSizeRatio: 0.5,
            maxPageCount: 1_000_000,
            maxDiskUsageBytes: 10_000_000_000,
            refuseWritesOnLimit: false // Default
        )
        
        let stats = DatabaseStats(
            pageCount: 1_500_000, // Exceeds limit
            walSize: 1_000_000,
            lastCheckpoint: Date(),
            cacheHitRate: 0.85,
            indexCount: 5,
            recordCount: 1000,
            databaseSize: 10_000_000
        )
        
        let shouldRefuse = DatabaseHealth.shouldRefuseWrites(stats: stats, limits: limits)
        XCTAssertFalse(shouldRefuse, "Should not refuse writes when refuseWritesOnLimit is false")
    }
}
