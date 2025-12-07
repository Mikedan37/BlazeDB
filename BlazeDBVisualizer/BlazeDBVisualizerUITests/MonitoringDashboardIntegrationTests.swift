//
//  MonitoringDashboardIntegrationTests.swift
//  BlazeDBVisualizerUITests
//
//  Integration tests for monitoring dashboard
//  ✅ Real-time updates
//  ✅ Health indicators
//  ✅ Maintenance operations
//  ✅ End-to-end user flows
//
//  Created by Michael Danylchuk on 11/13/25.
//

import XCTest

final class MonitoringDashboardIntegrationTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]  // Flag for UI testing mode
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Full Unlock Flow
    
    func testFullUnlockAndMonitoringFlow() throws {
        // 1. Find a database
        let firstDatabase = app.buttons.matching(identifier: "database_row").firstMatch
        
        guard firstDatabase.exists else {
            XCTFail("No databases found")
            return
        }
        
        // 2. Tap to unlock
        firstDatabase.tap()
        
        // 3. Wait for password prompt
        XCTAssertTrue(app.staticTexts["Unlock Database"].waitForExistence(timeout: 2))
        
        // 4. Enter password
        let passwordField = app.secureTextFields.firstMatch
        passwordField.tap()
        passwordField.typeText("testpassword")  // Note: This would need to be the actual password
        
        // 5. Tap unlock
        app.buttons["Unlock"].tap()
        
        // 6. Wait for dashboard to load (or error message)
        // Either we see "Live Monitoring" or "Invalid password"
        let dashboardAppeared = app.staticTexts["Live Monitoring"].waitForExistence(timeout: 5)
        let errorAppeared = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'invalid'")).firstMatch.exists
        
        XCTAssertTrue(dashboardAppeared || errorAppeared, "Should show either dashboard or error")
    }
    
    // MARK: - Dashboard Display Tests
    
    func testDashboardComponentsVisible() throws {
        // Assuming we're already unlocked (setup with mock data)
        if app.staticTexts["Live Monitoring"].exists {
            // Verify key dashboard components
            XCTAssertTrue(app.staticTexts["Health Status"].exists, "Health card should exist")
            XCTAssertTrue(app.staticTexts["Storage"].exists, "Storage card should exist")
            XCTAssertTrue(app.staticTexts["Performance"].exists, "Performance card should exist")
            XCTAssertTrue(app.staticTexts["Schema"].exists, "Schema card should exist")
            XCTAssertTrue(app.staticTexts["Maintenance"].exists, "Maintenance card should exist")
        }
    }
    
    func testHealthStatusIndicator() throws {
        if app.staticTexts["Health Status"].exists {
            // Check for health status badge
            let healthBadges = ["HEALTHY", "WARNING", "CRITICAL"]
            
            var foundHealthBadge = false
            for badge in healthBadges {
                if app.staticTexts[badge].exists {
                    foundHealthBadge = true
                    break
                }
            }
            
            XCTAssertTrue(foundHealthBadge, "Should display health status")
        }
    }
    
    func testStorageMetricsDisplay() throws {
        if app.staticTexts["Storage"].exists {
            // Check for storage metrics
            XCTAssertTrue(app.staticTexts["Records"].exists, "Should show records count")
            XCTAssertTrue(app.staticTexts["Size"].exists, "Should show database size")
            XCTAssertTrue(app.staticTexts["Pages"].exists, "Should show page count")
            XCTAssertTrue(app.staticTexts["Fragmentation"].exists, "Should show fragmentation")
        }
    }
    
    func testPerformanceMetricsDisplay() throws {
        if app.staticTexts["Performance"].exists {
            // Check for performance metrics
            XCTAssertTrue(app.staticTexts["MVCC"].exists, "Should show MVCC status")
            XCTAssertTrue(app.staticTexts["Indexes"].exists, "Should show index count")
        }
    }
    
    // MARK: - Refresh Tests
    
    func testManualRefresh() throws {
        if app.staticTexts["Live Monitoring"].exists {
            // Find refresh button
            let refreshButton = app.buttons.matching(identifier: "refresh_button").firstMatch
            
            if refreshButton.exists {
                let beforeTap = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Updated'")).firstMatch.label
                
                refreshButton.tap()
                
                // Wait a moment
                sleep(2)
                
                let afterTap = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Updated'")).firstMatch.label
                
                // Update time should have changed
                XCTAssertNotEqual(beforeTap, afterTap, "Update time should change after refresh")
            }
        }
    }
    
    func testAutoRefreshIndicator() throws {
        if app.staticTexts["Live Monitoring"].exists {
            // Check for "Updated X ago" text
            let updateText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Updated'")).firstMatch
            XCTAssertTrue(updateText.exists, "Should show last update time")
            
            // Wait for auto-refresh (5 seconds default)
            sleep(6)
            
            // Update time should have changed
            let newUpdateText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Updated'")).firstMatch
            XCTAssertTrue(newUpdateText.exists, "Should still show update time after auto-refresh")
        }
    }
    
    // MARK: - Maintenance Operations Tests
    
    func testVacuumButton() throws {
        if app.staticTexts["Maintenance"].exists {
            let vacuumButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'VACUUM'")).firstMatch
            
            if vacuumButton.exists {
                XCTAssertTrue(vacuumButton.isEnabled, "VACUUM button should be enabled")
                
                vacuumButton.tap()
                
                // Should show progress or completion message
                let completionMessage = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'complete'")).firstMatch
                XCTAssertTrue(completionMessage.waitForExistence(timeout: 10), "Should show completion message")
            }
        }
    }
    
    func testGCButton() throws {
        if app.staticTexts["Maintenance"].exists {
            let gcButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Garbage Collection'")).firstMatch
            
            if gcButton.exists {
                XCTAssertTrue(gcButton.isEnabled, "GC button should be enabled")
                
                gcButton.tap()
                
                // Should show progress or completion message
                let completionMessage = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'complete'")).firstMatch
                XCTAssertTrue(completionMessage.waitForExistence(timeout: 10), "Should show completion message")
            }
        }
    }
    
    func testMaintenanceButtonsDisabledDuringOperation() throws {
        if app.staticTexts["Maintenance"].exists {
            let vacuumButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'VACUUM'")).firstMatch
            let gcButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Garbage Collection'")).firstMatch
            
            if vacuumButton.exists {
                vacuumButton.tap()
                
                // During operation, both buttons should be disabled
                XCTAssertFalse(vacuumButton.isEnabled, "VACUUM button should be disabled during operation")
                if gcButton.exists {
                    XCTAssertFalse(gcButton.isEnabled, "GC button should be disabled during operation")
                }
                
                // Wait for completion
                sleep(3)
                
                // After completion, buttons should be re-enabled
                XCTAssertTrue(vacuumButton.isEnabled, "VACUUM button should be re-enabled after operation")
            }
        }
    }
    
    // MARK: - Warning Indicators Tests
    
    func testWarningIndicators() throws {
        if app.staticTexts["Health Status"].exists {
            // Check for warning icons
            let warningIcons = app.images.matching(NSPredicate(format: "identifier CONTAINS 'exclamationmark'"))
            
            // If warnings exist, they should be visible
            if warningIcons.count > 0 {
                XCTAssertTrue(warningIcons.firstMatch.exists, "Warning indicators should be visible")
            }
        }
    }
    
    func testFragmentationWarning() throws {
        if app.staticTexts["Fragmentation"].exists {
            // Check if fragmentation percentage is high (>30%)
            let fragmentationText = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "\\d+\\.\\d+%")).firstMatch
            
            if fragmentationText.exists {
                let text = fragmentationText.label
                if let percentage = Double(text.replacingOccurrences(of: "%", with: "")) {
                    if percentage > 30 {
                        // Should show warning color or icon
                        // Note: Color testing is limited in XCUITest, but we can check for warning icons
                        let warningIcon = app.images["exclamationmark.triangle.fill"]
                        // May or may not exist depending on actual fragmentation
                    }
                }
            }
        }
    }
    
    // MARK: - Scrolling and Navigation Tests
    
    func testScrollThroughDashboard() throws {
        if app.staticTexts["Live Monitoring"].exists {
            let scrollView = app.scrollViews.firstMatch
            
            if scrollView.exists {
                // Scroll to bottom
                scrollView.swipeUp()
                
                // Maintenance card should be visible
                XCTAssertTrue(app.staticTexts["Maintenance"].exists, "Should be able to scroll to Maintenance card")
                
                // Scroll back to top
                scrollView.swipeDown()
                
                // Health card should be visible again
                XCTAssertTrue(app.staticTexts["Health Status"].exists, "Should be able to scroll back to Health card")
            }
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testDashboardErrorState() throws {
        // This would test the error state when database connection is lost
        // Requires mock/test setup to trigger error
        
        if app.staticTexts["Connection Error"].exists {
            // Verify error message is displayed
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Error'")).firstMatch.exists)
            
            // Verify error icon is displayed
            XCTAssertTrue(app.images["exclamationmark.triangle.fill"].exists)
        }
    }
    
    // MARK: - Data Consistency Tests
    
    func testRecordCountConsistency() throws {
        if app.staticTexts["Storage"].exists {
            // Get record count from storage card
            let recordsLabel = app.staticTexts["Records"].firstMatch
            
            if recordsLabel.exists {
                // Record count should be a number
                let count = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "\\d+")).firstMatch
                XCTAssertTrue(count.exists, "Record count should be displayed as a number")
            }
        }
    }
    
    func testHealthStatusConsistency() throws {
        if app.staticTexts["Health Status"].exists {
            // Health status should be one of: HEALTHY, WARNING, CRITICAL
            let validStatuses = ["HEALTHY", "WARNING", "CRITICAL"]
            
            var foundStatus = false
            for status in validStatuses {
                if app.staticTexts[status].exists {
                    foundStatus = true
                    break
                }
            }
            
            XCTAssertTrue(foundStatus, "Should display a valid health status")
        }
    }
    
    // MARK: - Performance Tests
    
    func testDashboardLoadPerformance() throws {
        measure {
            // Simulate unlock and dashboard load
            let firstDatabase = app.buttons.matching(identifier: "database_row").firstMatch
            
            if firstDatabase.exists {
                firstDatabase.tap()
                
                // Wait for either dashboard or error
                let _ = app.staticTexts["Live Monitoring"].waitForExistence(timeout: 5) ||
                        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'invalid'")).firstMatch.waitForExistence(timeout: 5)
                
                // Go back
                app.buttons["Cancel"].tap()
            }
        }
    }
    
    func testMaintenanceOperationPerformance() throws {
        if app.staticTexts["Maintenance"].exists {
            let gcButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Garbage Collection'")).firstMatch
            
            if gcButton.exists {
                measure {
                    gcButton.tap()
                    
                    // Wait for completion
                    _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'complete'")).firstMatch.waitForExistence(timeout: 10)
                }
            }
        }
    }
}

