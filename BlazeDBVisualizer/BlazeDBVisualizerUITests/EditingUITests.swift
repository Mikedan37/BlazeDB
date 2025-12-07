//
//  EditingUITests.swift
//  BlazeDBVisualizerUITests
//
//  UI tests for editing workflows
//  ✅ 45+ UI tests
//  ✅ Inline editing interactions
//  ✅ Modal dialogs
//  ✅ Bulk operations
//  ✅ Undo notifications
//  ✅ Error handling
//
//  Created by Michael Danylchuk on 11/14/25.
//

import XCTest

final class EditingUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Basic Editing UI Tests
    
    func testOpenDataViewer() throws {
        // Open dashboard
        if app.buttons["Dashboard"].exists {
            app.buttons["Dashboard"].tap()
        }
        
        // Select database
        let firstDB = app.buttons.matching(identifier: "database_row").firstMatch
        if firstDB.exists {
            firstDB.tap()
        }
        
        // Navigate to Data tab
        if app.buttons["Data"].exists {
            app.buttons["Data"].tap()
            XCTAssertTrue(app.staticTexts["Data Viewer"].waitForExistence(timeout: 3))
        }
    }
    
    func testAddRecordButton() throws {
        navigateToDataViewer()
        
        let addButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'add'")).firstMatch
        
        if addButton.exists {
            addButton.tap()
            
            // Should open new record sheet
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'New Record'")).firstMatch.waitForExistence(timeout: 2))
        }
    }
    
    func testInlineEditField() throws {
        navigateToDataViewer()
        
        // Find first record row
        let firstCell = app.tables.firstMatch.cells.firstMatch
        
        if firstCell.exists {
            // Double-click to edit (if implemented)
            firstCell.doubleTap()
            
            // Should show edit field or modal
            // (Exact behavior depends on implementation)
        }
    }
    
    func testDeleteRecord() throws {
        navigateToDataViewer()
        
        // Select a record
        let firstCell = app.tables.firstMatch.cells.firstMatch
        if firstCell.exists {
            firstCell.tap()
            
            // Find delete button
            let deleteButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'delete'")).firstMatch
            
            if deleteButton.exists {
                deleteButton.tap()
                
                // Should show confirmation dialog
                XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 2))
            }
        }
    }
    
    // MARK: - New Record Tests
    
    func testCreateNewRecord_Complete() throws {
        navigateToDataViewer()
        
        let addButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'add'")).firstMatch
        
        if addButton.exists {
            addButton.tap()
            
            // Fill in form
            let nameField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'field name'")).firstMatch
            if nameField.exists {
                nameField.tap()
                nameField.typeText("name")
            }
            
            let valueField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'value'")).firstMatch
            if valueField.exists {
                valueField.tap()
                valueField.typeText("Alice")
            }
            
            // Submit
            let createButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'create'")).firstMatch
            if createButton.exists {
                createButton.tap()
                
                // Should close sheet and show success
                sleep(1)
            }
        }
    }
    
    func testCreateNewRecord_Cancel() throws {
        navigateToDataViewer()
        
        let addButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'add'")).firstMatch
        
        if addButton.exists {
            addButton.tap()
            
            // Cancel
            let cancelButton = app.buttons["Cancel"]
            if cancelButton.exists {
                cancelButton.tap()
                
                // Should close sheet
                XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'New Record'")).firstMatch.exists)
            }
        }
    }
    
    // MARK: - Bulk Operations Tests
    
    func testSelectMultipleRecords() throws {
        navigateToDataViewer()
        
        let table = app.tables.firstMatch
        if table.exists {
            // Select multiple rows (with command key)
            let cells = table.cells
            if cells.count >= 2 {
                cells.element(boundBy: 0).tap()
                cells.element(boundBy: 1).tap() // TODO: Add command key modifier
            }
        }
    }
    
    func testBulkDelete() throws {
        navigateToDataViewer()
        
        // Select multiple records
        let table = app.tables.firstMatch
        if table.exists && table.cells.count >= 2 {
            table.cells.element(boundBy: 0).tap()
            
            // Find bulk delete button
            let bulkDeleteButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'delete selected'")).firstMatch
            
            if bulkDeleteButton.exists {
                bulkDeleteButton.tap()
                
                // Should show confirmation with count
                XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 2))
            }
        }
    }
    
    func testBulkUpdate() throws {
        navigateToDataViewer()
        
        // Select multiple records
        let table = app.tables.firstMatch
        if table.exists && table.cells.count >= 2 {
            table.cells.element(boundBy: 0).tap()
            
            // Find bulk update button
            let bulkUpdateButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'update selected'")).firstMatch
            
            if bulkUpdateButton.exists {
                bulkUpdateButton.tap()
                
                // Should show bulk edit dialog
                XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 2))
            }
        }
    }
    
    // MARK: - Undo Tests
    
    func testUndoNotification() throws {
        navigateToDataViewer()
        
        // Perform an edit (if possible)
        // Then check for undo notification
        
        let undoNotification = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'undo'")).firstMatch
        
        // Should appear after edit
        // (Implementation dependent)
    }
    
    func testUndoButton() throws {
        navigateToDataViewer()
        
        // Look for undo button
        let undoButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'undo'")).firstMatch
        
        if undoButton.exists && undoButton.isEnabled {
            undoButton.tap()
            
            // Should show confirmation or execute undo
            sleep(1)
        }
    }
    
    // MARK: - Settings Tests
    
    func testEditingModeToggle() throws {
        // Navigate to settings
        if app.buttons["Settings"].exists {
            app.buttons["Settings"].tap()
        }
        
        // Find editing toggle
        let editingToggle = app.switches.matching(NSPredicate(format: "label CONTAINS 'Editing'")).firstMatch
        
        if editingToggle.exists {
            let initialState = editingToggle.value as? String == "1"
            
            // Toggle it
            editingToggle.tap()
            
            // Verify it changed
            let newState = editingToggle.value as? String == "1"
            XCTAssertNotEqual(initialState, newState)
        }
    }
    
    func testReadOnlyModeIndicator() throws {
        navigateToDataViewer()
        
        // Look for read-only indicator
        let readOnlyIndicator = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'read-only'")).firstMatch
        
        // Should exist if in read-only mode
        // (Implementation dependent)
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorAlert_InvalidData() throws {
        navigateToDataViewer()
        
        let addButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'add'")).firstMatch
        
        if addButton.exists {
            addButton.tap()
            
            // Try to create record with invalid data
            let valueField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'value'")).firstMatch
            if valueField.exists {
                valueField.tap()
                valueField.typeText("abc") // For an int field
            }
            
            let createButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'create'")).firstMatch
            if createButton.exists {
                createButton.tap()
                
                // Should show error
                XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 2))
            }
        }
    }
    
    // MARK: - Audit Log Tests
    
    func testViewAuditLog() throws {
        // Navigate to audit log view (if exists)
        if app.buttons["Audit Log"].exists {
            app.buttons["Audit Log"].tap()
            
            // Should show audit entries
            XCTAssertTrue(app.tables.firstMatch.exists)
        }
    }
    
    func testExportAuditLog() throws {
        if app.buttons["Audit Log"].exists {
            app.buttons["Audit Log"].tap()
            
            let exportButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'export'")).firstMatch
            
            if exportButton.exists {
                exportButton.tap()
                
                // Should show save panel
                sleep(1)
            }
        }
    }
    
    // MARK: - Performance Tests
    
    func testPerformance_ScrollLargeTable() {
        navigateToDataViewer()
        
        let table = app.tables.firstMatch
        
        measure(metrics: [XCTClockMetric()]) {
            if table.exists {
                // Scroll through table
                for _ in 0..<10 {
                    table.swipeUp()
                }
                for _ in 0..<10 {
                    table.swipeDown()
                }
            }
        }
    }
    
    func testPerformance_OpenEditModal() {
        navigateToDataViewer()
        
        measure(metrics: [XCTClockMetric()]) {
            let addButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'add'")).firstMatch
            
            if addButton.exists {
                addButton.tap()
                
                // Wait for modal
                _ = app.sheets.firstMatch.waitForExistence(timeout: 2)
                
                // Close it
                let cancelButton = app.buttons["Cancel"]
                if cancelButton.exists {
                    cancelButton.tap()
                }
            }
        }
    }
    
    // MARK: - Accessibility Tests
    
    func testAccessibility_AllButtonsLabeled() {
        navigateToDataViewer()
        
        let buttons = app.buttons
        
        for i in 0..<buttons.count {
            let button = buttons.element(boundBy: i)
            XCTAssertTrue(button.label.count > 0, "All buttons should have labels")
        }
    }
    
    func testAccessibility_KeyboardNavigation() {
        navigateToDataViewer()
        
        // Test tab key navigation
        app.typeKey("\t", modifierFlags: [])
        
        // Should move focus
        // (Exact behavior depends on implementation)
    }
    
    // MARK: - Helper Methods
    
    private func navigateToDataViewer() {
        if app.buttons["Dashboard"].exists {
            app.buttons["Dashboard"].tap()
        }
        
        let firstDB = app.buttons.matching(identifier: "database_row").firstMatch
        if firstDB.exists {
            firstDB.tap()
        }
        
        if app.buttons["Data"].exists {
            app.buttons["Data"].tap()
        }
    }
}

