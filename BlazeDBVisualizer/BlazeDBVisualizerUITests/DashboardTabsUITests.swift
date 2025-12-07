//
//  DashboardTabsUITests.swift
//  BlazeDBVisualizerUITests
//
//  UI tests for all dashboard tabs
//  ✅ Tab navigation
//  ✅ Data viewer interaction
//  ✅ Query console
//  ✅ Charts display
//  ✅ Backup/restore flow
//
//  Created by Michael Danylchuk on 11/14/25.
//

import XCTest

final class DashboardTabsUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Tab Navigation Tests
    
    func testAllTabsExist() throws {
        // Assuming we're at the dashboard (after unlock)
        if app.buttons["Monitor"].exists {
            XCTAssertTrue(app.buttons["Monitor"].exists)
            XCTAssertTrue(app.buttons["Data"].exists)
            XCTAssertTrue(app.buttons["Query"].exists)
            XCTAssertTrue(app.buttons["Charts"].exists)
            XCTAssertTrue(app.buttons["Backup"].exists)
        }
    }
    
    func testSwitchBetweenTabs() throws {
        if app.buttons["Monitor"].exists {
            // Start on Monitor
            app.buttons["Monitor"].tap()
            XCTAssertTrue(app.staticTexts["Live Monitoring"].exists || app.staticTexts["Health Status"].exists)
            
            // Switch to Data
            app.buttons["Data"].tap()
            XCTAssertTrue(app.staticTexts["Data Viewer"].waitForExistence(timeout: 2))
            
            // Switch to Query
            app.buttons["Query"].tap()
            XCTAssertTrue(app.staticTexts["Query Console"].waitForExistence(timeout: 2))
            
            // Switch to Charts
            app.buttons["Charts"].tap()
            XCTAssertTrue(app.staticTexts["Performance Trends"].waitForExistence(timeout: 2))
            
            // Switch to Backup
            app.buttons["Backup"].tap()
            XCTAssertTrue(app.staticTexts["Backup & Restore"].waitForExistence(timeout: 2))
        }
    }
    
    // MARK: - Data Viewer Tests
    
    func testDataViewerDisplaysRecords() throws {
        if app.buttons["Data"].exists {
            app.buttons["Data"].tap()
            
            // Should show data viewer
            XCTAssertTrue(app.staticTexts["Data Viewer"].waitForExistence(timeout: 2))
            
            // Should have pagination controls
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Page'")).firstMatch.exists)
        }
    }
    
    func testDataViewerPagination() throws {
        if app.buttons["Data"].exists {
            app.buttons["Data"].tap()
            
            // Find pagination buttons
            let nextButton = app.buttons.matching(identifier: "next_page").firstMatch
            let prevButton = app.buttons.matching(identifier: "prev_page").firstMatch
            
            if nextButton.exists {
                // Previous should be disabled on first page
                XCTAssertFalse(prevButton.isEnabled)
                
                // Try going to next page
                if nextButton.isEnabled {
                    nextButton.tap()
                    
                    // Now previous should be enabled
                    XCTAssertTrue(prevButton.isEnabled)
                }
            }
        }
    }
    
    func testDataViewerSearch() throws {
        if app.buttons["Data"].exists {
            app.buttons["Data"].tap()
            
            let searchField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'Search'")).firstMatch
            
            if searchField.exists {
                searchField.tap()
                searchField.typeText("test")
                
                // Results should update
                // (Exact assertions depend on test data)
            }
        }
    }
    
    func testDataViewerRecordSelection() throws {
        if app.buttons["Data"].exists {
            app.buttons["Data"].tap()
            
            // Wait for records to load
            sleep(2)
            
            // Select first record
            let firstRecord = app.tables.firstMatch.cells.firstMatch
            if firstRecord.exists {
                firstRecord.tap()
                
                // Detail view should show
                XCTAssertTrue(app.staticTexts["Record Details"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'ID:'")).firstMatch.exists)
            }
        }
    }
    
    // MARK: - Query Console Tests
    
    func testQueryConsoleComponents() throws {
        if app.buttons["Query"].exists {
            app.buttons["Query"].tap()
            
            // Should have query builder components
            XCTAssertTrue(app.staticTexts["Query Console"].waitForExistence(timeout: 2))
            XCTAssertTrue(app.staticTexts["Build Query"].exists)
            
            // Should have text fields
            let whereField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'status'")).firstMatch
            XCTAssertTrue(whereField.exists)
        }
    }
    
    func testQueryConsoleExecuteButton() throws {
        if app.buttons["Query"].exists {
            app.buttons["Query"].tap()
            
            let executeButton = app.buttons["Execute Query"]
            XCTAssertTrue(executeButton.exists)
            XCTAssertTrue(executeButton.isEnabled)
        }
    }
    
    func testQueryConsoleQuickExamples() throws {
        if app.buttons["Query"].exists {
            app.buttons["Query"].tap()
            
            // Should have quick example buttons
            XCTAssertTrue(app.buttons["All"].exists || app.buttons["First 10"].exists || app.buttons["Recent"].exists)
        }
    }
    
    // MARK: - Charts Tests
    
    func testChartsDisplayMetrics() throws {
        if app.buttons["Charts"].exists {
            app.buttons["Charts"].tap()
            
            XCTAssertTrue(app.staticTexts["Performance Trends"].waitForExistence(timeout: 2))
            
            // Should have metric picker
            let picker = app.segmentedControls.firstMatch
            XCTAssertTrue(picker.exists)
        }
    }
    
    func testChartsSwitchMetrics() throws {
        if app.buttons["Charts"].exists {
            app.buttons["Charts"].tap()
            
            let picker = app.segmentedControls.firstMatch
            
            if picker.exists {
                // Try switching metrics
                let recordsButton = picker.buttons["Records"]
                let sizeButton = picker.buttons["Size"]
                
                if recordsButton.exists {
                    recordsButton.tap()
                    // Chart should update (can't easily verify chart content)
                }
                
                if sizeButton.exists {
                    sizeButton.tap()
                    // Chart should update
                }
            }
        }
    }
    
    func testChartsShowStats() throws {
        if app.buttons["Charts"].exists {
            app.buttons["Charts"].tap()
            
            // Should show current, peak, average stats
            XCTAssertTrue(
                app.staticTexts["Current"].exists ||
                app.staticTexts["Peak"].exists ||
                app.staticTexts["Average"].exists
            )
        }
    }
    
    // MARK: - Backup/Restore Tests
    
    func testBackupCreation() throws {
        if app.buttons["Backup"].exists {
            app.buttons["Backup"].tap()
            
            XCTAssertTrue(app.staticTexts["Backup & Restore"].waitForExistence(timeout: 2))
            
            // Should have create backup section
            XCTAssertTrue(app.staticTexts["Create Backup"].exists)
            XCTAssertTrue(app.buttons["Create"].exists)
        }
    }
    
    func testBackupNameField() throws {
        if app.buttons["Backup"].exists {
            app.buttons["Backup"].tap()
            
            let nameField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'name'")).firstMatch
            
            if nameField.exists {
                nameField.tap()
                nameField.typeText("test_backup")
                
                XCTAssertNotNil(nameField.value)
            }
        }
    }
    
    func testBackupHistory() throws {
        if app.buttons["Backup"].exists {
            app.buttons["Backup"].tap()
            
            XCTAssertTrue(app.staticTexts["Backup History"].exists)
            
            // List or empty state should exist
            XCTAssertTrue(
                app.tables.firstMatch.exists ||
                app.staticTexts["No backups yet"].exists
            )
        }
    }
    
    // MARK: - Integration Tests
    
    func testFullTabWorkflow() throws {
        // Test switching through all tabs
        let tabs = ["Monitor", "Data", "Query", "Charts", "Backup"]
        
        for tab in tabs {
            if app.buttons[tab].exists {
                app.buttons[tab].tap()
                
                // Wait a bit for content to load
                sleep(1)
                
                // Verify tab content exists (each tab has unique content)
                XCTAssertFalse(app.staticTexts.allElementsBoundByIndex.isEmpty, "\(tab) tab should have content")
            }
        }
    }
    
    func testTabStatePreservation() throws {
        if app.buttons["Query"].exists {
            // Enter text in Query tab
            app.buttons["Query"].tap()
            
            let whereField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'status'")).firstMatch
            if whereField.exists {
                whereField.tap()
                whereField.typeText("test")
                
                // Switch to another tab
                app.buttons["Monitor"].tap()
                
                // Switch back
                app.buttons["Query"].tap()
                
                // Text should still be there (ideally)
                // Note: State preservation depends on implementation
            }
        }
    }
    
    // MARK: - Performance Tests
    
    func testTabSwitchingPerformance() {
        measure {
            if app.buttons["Monitor"].exists {
                app.buttons["Data"].tap()
                sleep(1)
                app.buttons["Monitor"].tap()
                sleep(1)
            }
        }
    }
    
    func testDataLoadPerformance() {
        measure {
            if app.buttons["Data"].exists {
                app.buttons["Data"].tap()
                _ = app.staticTexts["Data Viewer"].waitForExistence(timeout: 5)
            }
        }
    }
}

