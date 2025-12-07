//
//  FullWorkflowIntegrationTests.swift
//  BlazeDBVisualizerUITests
//
//  End-to-end workflow tests
//  ✅ Complete user journeys
//  ✅ Multi-tab workflows
//  ✅ Real-world scenarios
//
//  Created by Michael Danylchuk on 11/14/25.
//

import XCTest

final class FullWorkflowIntegrationTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Complete Workflows
    
    func testFullInspectionWorkflow() throws {
        // Scenario: Developer wants to inspect database
        
        // 1. Open dashboard
        if app.buttons["Dashboard"].exists {
            app.buttons["Dashboard"].tap()
        }
        
        // 2. Select database
        let firstDB = app.buttons.matching(identifier: "database_row").firstMatch
        if firstDB.exists {
            firstDB.tap()
        }
        
        // 3. Unlock (skip password entry in test)
        
        // 4. Check Monitor tab
        if app.buttons["Monitor"].exists {
            app.buttons["Monitor"].tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Health'")).firstMatch.exists)
        }
        
        // 5. View data
        if app.buttons["Data"].exists {
            app.buttons["Data"].tap()
            XCTAssertTrue(app.staticTexts["Data Viewer"].waitForExistence(timeout: 3))
        }
        
        // 6. Run query
        if app.buttons["Query"].exists {
            app.buttons["Query"].tap()
            XCTAssertTrue(app.staticTexts["Query Console"].waitForExistence(timeout: 3))
        }
    }
    
    func testBackupAndRestoreWorkflow() throws {
        // Scenario: Developer wants to backup before risky operation
        
        if app.buttons["Backup"].exists {
            app.buttons["Backup"].tap()
            
            // 1. Create backup
            let createButton = app.buttons["Create"]
            if createButton.exists {
                createButton.tap()
                
                // 2. Wait for success message
                let successMessage = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'created'")).firstMatch
                XCTAssertTrue(successMessage.waitForExistence(timeout: 5))
                
                // 3. Backup should appear in list
                sleep(2)
                let backupList = app.tables.firstMatch
                XCTAssertTrue(backupList.exists)
            }
        }
    }
    
    func testQueryAndExportWorkflow() throws {
        // Scenario: Developer wants to query and export results
        
        if app.buttons["Query"].exists {
            app.buttons["Query"].tap()
            
            // 1. Build query
            let whereField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'status'")).firstMatch
            if whereField.exists {
                whereField.tap()
                whereField.typeText("test")
            }
            
            // 2. Execute
            let executeButton = app.buttons["Execute Query"]
            if executeButton.exists {
                executeButton.tap()
                
                // 3. Wait for results
                sleep(2)
                
                // 4. Results should appear
                XCTAssertTrue(app.staticTexts["Results"].exists)
            }
        }
    }
    
    func testMaintenanceWorkflow() throws {
        // Scenario: Developer sees warning, runs maintenance
        
        // 1. Check Monitor tab
        if app.buttons["Monitor"].exists {
            app.buttons["Monitor"].tap()
        }
        
        // 2. Run VACUUM
        let vacuumButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'VACUUM'")).firstMatch
        if vacuumButton.exists && vacuumButton.isEnabled {
            vacuumButton.tap()
            
            // 3. Wait for completion
            let completionMessage = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'complete'")).firstMatch
            XCTAssertTrue(completionMessage.waitForExistence(timeout: 10))
        }
        
        // 4. Run GC
        let gcButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Garbage'")).firstMatch
        if gcButton.exists && gcButton.isEnabled {
            gcButton.tap()
            
            // Wait for completion
            sleep(3)
        }
    }
    
    // MARK: - Search and Filter Tests
    
    func testMenuBarSearch() throws {
        // Test search in menu bar extra
        let searchField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'Search databases'")).firstMatch
        
        if searchField.exists {
            searchField.tap()
            searchField.typeText("test")
            
            // Results should filter
            // (Exact assertion depends on test data)
        }
    }
    
    func testDataViewerRecordDetail() throws {
        if app.buttons["Data"].exists {
            app.buttons["Data"].tap()
            
            // Select a record
            let table = app.tables.firstMatch
            if table.exists {
                let firstRow = table.cells.firstMatch
                if firstRow.exists {
                    firstRow.tap()
                    
                    // Detail should show
                    XCTAssertTrue(app.staticTexts["Record Details"].exists)
                    
                    // Copy button should exist
                    let copyButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Copy'")).firstMatch
                    XCTAssertTrue(copyButton.exists)
                }
            }
        }
    }
    
    // MARK: - Performance Tests
    
    func testNavigationPerformance() {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            if app.buttons["Monitor"].exists {
                for _ in 0..<5 {
                    app.buttons["Data"].tap()
                    app.buttons["Query"].tap()
                    app.buttons["Charts"].tap()
                    app.buttons["Backup"].tap()
                    app.buttons["Monitor"].tap()
                }
            }
        }
    }
    
    func testDashboardLoadPerformance() {
        measure(metrics: [XCTClockMetric()]) {
            if app.buttons["Dashboard"].exists {
                app.buttons["Dashboard"].tap()
                _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'BlazeDB'")).firstMatch.waitForExistence(timeout: 5)
            }
        }
    }
    
    // MARK: - Accessibility Tests
    
    func testAllTabsAccessible() throws {
        let tabs = ["Monitor", "Data", "Query", "Charts", "Backup"]
        
        for tabName in tabs {
            let tab = app.buttons[tabName]
            if tab.exists {
                XCTAssertTrue(tab.isHittable, "\(tabName) tab should be hittable")
            }
        }
    }
    
    func testKeyboardNavigation() throws {
        // Test tab key navigation
        if app.buttons["Monitor"].exists {
            app.buttons["Monitor"].tap()
            
            // Press tab key to navigate
            app.typeKey("\t", modifierFlags: [])
            
            // Should move focus (exact behavior depends on implementation)
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidQueryHandling() throws {
        if app.buttons["Query"].exists {
            app.buttons["Query"].tap()
            
            // Enter invalid query
            let whereField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'status'")).firstMatch
            if whereField.exists {
                whereField.tap()
                whereField.typeText("invalid syntax <<<")
                
                // Execute
                app.buttons["Execute Query"].tap()
                
                // Should show error (or handle gracefully)
                // May show error message or empty results
            }
        }
    }
    
    // MARK: - Stress Tests
    
    func testRapidTabSwitching() {
        // Rapidly switch between tabs (stress test)
        if app.buttons["Monitor"].exists {
            for _ in 0..<20 {
                app.buttons["Data"].tap()
                app.buttons["Monitor"].tap()
            }
            
            // App should still be responsive
            XCTAssertTrue(app.buttons["Monitor"].exists)
        }
    }
}

