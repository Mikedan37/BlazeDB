//
//  OperationalConfidenceTests.swift
//  BlazeDBTests
//
//  Tests for operational confidence features
//  Health classification, stats interpretation
//

import Foundation
import XCTest
@testable import BlazeDBCore

final class OperationalConfidenceTests: XCTestCase {
    
    // MARK: - Health Classification Tests
    
    func testHealth_OK_AllMetricsNormal() {
        let stats = DatabaseStats(
            pageCount: 100,
            walSize: 1_000_000, // 1 MB
            lastCheckpoint: Date(),
            cacheHitRate: 0.85,
            indexCount: 5,
            recordCount: 1000,
            databaseSize: 10_000_000 // 10 MB
        )
        
        let health = HealthAnalyzer.analyze(stats)
        XCTAssertEqual(health.status, .ok, "All metrics normal should be OK")
    }
    
    func testHealth_WARN_LargeWAL() {
        let stats = DatabaseStats(
            pageCount: 100,
            walSize: 5_000_000, // 5 MB
            lastCheckpoint: Date(),
            cacheHitRate: 0.85,
            indexCount: 5,
            recordCount: 1000,
            databaseSize: 10_000_000 // 10 MB (WAL is 50%)
        )
        
        let health = HealthAnalyzer.analyze(stats)
        XCTAssertEqual(health.status, .warn, "Large WAL should be WARN")
        XCTAssertTrue(health.reasons.contains { $0.contains("WAL size") })
        XCTAssertTrue(health.suggestedActions.contains { $0.contains("checkpoint") })
    }
    
    func testHealth_WARN_LowCacheHitRate() {
        let stats = DatabaseStats(
            pageCount: 100,
            walSize: nil,
            lastCheckpoint: nil,
            cacheHitRate: 0.6, // 60% - below warn threshold
            indexCount: 5,
            recordCount: 1000,
            databaseSize: 10_000_000
        )
        
        let health = HealthAnalyzer.analyze(stats)
        XCTAssertEqual(health.status, .warn, "Low cache hit rate should be WARN")
        XCTAssertTrue(health.reasons.contains { $0.contains("Cache hit rate") })
    }
    
    func testHealth_WARN_Fragmentation() {
        let stats = DatabaseStats(
            pageCount: 1000,
            walSize: nil,
            lastCheckpoint: nil,
            cacheHitRate: 0.85,
            indexCount: 5,
            recordCount: 5000, // 5 records per page - fragmentation
            databaseSize: 10_000_000
        )
        
        let health = HealthAnalyzer.analyze(stats)
        XCTAssertEqual(health.status, .warn, "Fragmentation should be WARN")
        XCTAssertTrue(health.reasons.contains { $0.contains("fragmentation") })
        XCTAssertTrue(health.suggestedActions.contains { $0.contains("vacuum") })
    }
    
    func testHealth_ERROR_VeryLowCacheHitRate() {
        let stats = DatabaseStats(
            pageCount: 100,
            walSize: nil,
            lastCheckpoint: nil,
            cacheHitRate: 0.3, // 30% - below error threshold
            indexCount: 5,
            recordCount: 1000,
            databaseSize: 10_000_000
        )
        
        let health = HealthAnalyzer.analyze(stats)
        XCTAssertEqual(health.status, .error, "Very low cache hit rate should be ERROR")
        XCTAssertTrue(health.reasons.contains { $0.contains("Cache hit rate") })
    }
    
    // MARK: - Stats Interpretation Tests
    
    func testStatsInterpretation_EmptyDatabase() {
        let stats = DatabaseStats(
            pageCount: 0,
            walSize: nil,
            lastCheckpoint: nil,
            cacheHitRate: 0,
            indexCount: 0,
            recordCount: 0,
            databaseSize: 0
        )
        
        let interpretation = stats.interpretation
        XCTAssertTrue(interpretation.contains("empty database"))
    }
    
    func testStatsInterpretation_LargeDatabase() {
        let stats = DatabaseStats(
            pageCount: 1000,
            walSize: nil,
            lastCheckpoint: nil,
            cacheHitRate: 0.85,
            indexCount: 10,
            recordCount: 1_500_000,
            databaseSize: 1_000_000_000
        )
        
        let interpretation = stats.interpretation
        XCTAssertTrue(interpretation.contains("very large database"))
    }
    
    func testStatsInterpretation_Fragmentation() {
        let stats = DatabaseStats(
            pageCount: 1000,
            walSize: nil,
            lastCheckpoint: nil,
            cacheHitRate: 0.85,
            indexCount: 5,
            recordCount: 5000, // 5 records per page
            databaseSize: 10_000_000
        )
        
        let interpretation = stats.interpretation
        XCTAssertTrue(interpretation.contains("fragmentation"))
    }
    
    func testStatsInterpretation_NoIndexes() {
        let stats = DatabaseStats(
            pageCount: 100,
            walSize: nil,
            lastCheckpoint: nil,
            cacheHitRate: 0.85,
            indexCount: 0,
            recordCount: 1000,
            databaseSize: 10_000_000
        )
        
        let interpretation = stats.interpretation
        XCTAssertTrue(interpretation.contains("no indexes"))
    }
    
    // MARK: - Health Report Summary Tests
    
    func testHealthReport_SummaryFormat() {
        let health = HealthReport(
            status: .warn,
            reasons: ["WAL size is large", "Cache hit rate is moderate"],
            suggestedActions: ["Run checkpoint", "Monitor cache"]
        )
        
        let summary = health.summary
        XCTAssertTrue(summary.contains("WARN"))
        XCTAssertTrue(summary.contains("WAL size"))
        XCTAssertTrue(summary.contains("Run checkpoint"))
    }
}
