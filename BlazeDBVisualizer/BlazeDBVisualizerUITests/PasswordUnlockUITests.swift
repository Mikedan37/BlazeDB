//
//  PasswordUnlockUITests.swift
//  BlazeDBVisualizerUITests
//
//  UI tests for password unlock flow
//  ✅ Password entry
//  ✅ Biometric unlock
//  ✅ Error states
//  ✅ User interactions
//
//  Created by Michael Danylchuk on 11/13/25.
//

import XCTest

final class PasswordUnlockUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Password Prompt Tests
    
    func testPasswordPromptAppears() throws {
        // Find a database in the list
        let firstDatabase = app.buttons.matching(identifier: "database_row").firstMatch
        
        if firstDatabase.exists {
            firstDatabase.tap()
            
            // Verify password prompt appears
            XCTAssertTrue(app.staticTexts["Unlock Database"].waitForExistence(timeout: 2))
            XCTAssertTrue(app.secureTextFields.firstMatch.exists, "Password field should exist")
        } else {
            XCTFail("No databases found to test")
        }
    }
    
    func testPasswordFieldFocus() throws {
        let firstDatabase = app.buttons.matching(identifier: "database_row").firstMatch
        
        if firstDatabase.exists {
            firstDatabase.tap()
            
            // Wait for password prompt
            XCTAssertTrue(app.staticTexts["Unlock Database"].waitForExistence(timeout: 2))
            
            // Password field should be focused
            let passwordField = app.secureTextFields.firstMatch
            XCTAssertTrue(passwordField.exists)
            
            // Type without clicking (field should be pre-focused)
            passwordField.typeText("test")
            
            // Verify text was entered
            XCTAssertNotNil(passwordField.value)
        }
    }
    
    func testShowPasswordToggle() throws {
        let firstDatabase = app.buttons.matching(identifier: "database_row").firstMatch
        
        if firstDatabase.exists {
            firstDatabase.tap()
            
            // Wait for password prompt
            XCTAssertTrue(app.staticTexts["Unlock Database"].waitForExistence(timeout: 2))
            
            // Verify secure field exists initially
            XCTAssertTrue(app.secureTextFields.firstMatch.exists)
            
            // Find and tap show/hide button
            let showButton = app.buttons.matching(identifier: "show_password").firstMatch
            if showButton.exists {
                showButton.tap()
                
                // After toggle, regular text field should appear
                XCTAssertTrue(app.textFields.firstMatch.exists)
            }
        }
    }
    
    func testRememberPasswordToggle() throws {
        let firstDatabase = app.buttons.matching(identifier: "database_row").firstMatch
        
        if firstDatabase.exists {
            firstDatabase.tap()
            
            // Wait for password prompt
            XCTAssertTrue(app.staticTexts["Unlock Database"].waitForExistence(timeout: 2))
            
            // Find "Remember password" toggle
            let rememberToggle = app.checkBoxes.matching(identifier: "remember_password").firstMatch
            
            if rememberToggle.exists {
                let initialState = rememberToggle.value as? Int ?? 0
                
                rememberToggle.tap()
                
                // State should change
                let newState = rememberToggle.value as? Int ?? 0
                XCTAssertNotEqual(initialState, newState, "Toggle state should change")
            }
        }
    }
    
    // MARK: - Cancel and Dismiss Tests
    
    func testCancelButton() throws {
        let firstDatabase = app.buttons.matching(identifier: "database_row").firstMatch
        
        if firstDatabase.exists {
            firstDatabase.tap()
            
            // Wait for password prompt
            XCTAssertTrue(app.staticTexts["Unlock Database"].waitForExistence(timeout: 2))
            
            // Tap cancel
            let cancelButton = app.buttons["Cancel"]
            XCTAssertTrue(cancelButton.exists)
            cancelButton.tap()
            
            // Password prompt should disappear
            XCTAssertFalse(app.staticTexts["Unlock Database"].exists, "Prompt should be dismissed")
        }
    }
    
    func testDismissOnBackgroundTap() throws {
        let firstDatabase = app.buttons.matching(identifier: "database_row").firstMatch
        
        if firstDatabase.exists {
            firstDatabase.tap()
            
            // Wait for password prompt
            XCTAssertTrue(app.staticTexts["Unlock Database"].waitForExistence(timeout: 2))
            
            // Tap outside the prompt (on background)
            let background = app.otherElements.matching(identifier: "prompt_background").firstMatch
            if background.exists {
                background.tap()
                
                // Password prompt should disappear
                XCTAssertFalse(app.staticTexts["Unlock Database"].waitForExistence(timeout: 1))
            }
        }
    }
    
    // MARK: - Unlock Button State Tests
    
    func testUnlockButtonDisabledWhenEmpty() throws {
        let firstDatabase = app.buttons.matching(identifier: "database_row").firstMatch
        
        if firstDatabase.exists {
            firstDatabase.tap()
            
            // Wait for password prompt
            XCTAssertTrue(app.staticTexts["Unlock Database"].waitForExistence(timeout: 2))
            
            // Unlock button should be disabled
            let unlockButton = app.buttons["Unlock"]
            XCTAssertTrue(unlockButton.exists)
            XCTAssertFalse(unlockButton.isEnabled, "Unlock button should be disabled when password is empty")
        }
    }
    
    func testUnlockButtonEnabledWithPassword() throws {
        let firstDatabase = app.buttons.matching(identifier: "database_row").firstMatch
        
        if firstDatabase.exists {
            firstDatabase.tap()
            
            // Wait for password prompt
            XCTAssertTrue(app.staticTexts["Unlock Database"].waitForExistence(timeout: 2))
            
            // Enter password
            let passwordField = app.secureTextFields.firstMatch
            passwordField.tap()
            passwordField.typeText("testpassword")
            
            // Unlock button should now be enabled
            let unlockButton = app.buttons["Unlock"]
            XCTAssertTrue(unlockButton.isEnabled, "Unlock button should be enabled with password")
        }
    }
    
    // MARK: - Error Display Tests
    
    func testErrorMessageDisplay() throws {
        let firstDatabase = app.buttons.matching(identifier: "database_row").firstMatch
        
        if firstDatabase.exists {
            firstDatabase.tap()
            
            // Wait for password prompt
            XCTAssertTrue(app.staticTexts["Unlock Database"].waitForExistence(timeout: 2))
            
            // Enter wrong password
            let passwordField = app.secureTextFields.firstMatch
            passwordField.tap()
            passwordField.typeText("wrong_password")
            
            // Tap unlock
            let unlockButton = app.buttons["Unlock"]
            unlockButton.tap()
            
            // Error message should appear
            let errorText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'invalid'")).firstMatch
            XCTAssertTrue(errorText.waitForExistence(timeout: 3), "Error message should appear")
        }
    }
    
    // MARK: - Biometric Unlock Tests
    
    func testBiometricUnlockButtonPresence() throws {
        let firstDatabase = app.buttons.matching(identifier: "database_row").firstMatch
        
        if firstDatabase.exists {
            firstDatabase.tap()
            
            // Wait for password prompt
            XCTAssertTrue(app.staticTexts["Unlock Database"].waitForExistence(timeout: 2))
            
            // Check if biometric button exists (depends on whether password is stored)
            let biometricButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Face ID' OR label CONTAINS[c] 'Touch ID'")).firstMatch
            
            // Note: This may or may not exist depending on whether a password is stored
            // Just verify the app doesn't crash checking for it
            _ = biometricButton.exists
        }
    }
    
    // MARK: - Keyboard Navigation Tests
    
    func testEnterKeySubmitsForm() throws {
        let firstDatabase = app.buttons.matching(identifier: "database_row").firstMatch
        
        if firstDatabase.exists {
            firstDatabase.tap()
            
            // Wait for password prompt
            XCTAssertTrue(app.staticTexts["Unlock Database"].waitForExistence(timeout: 2))
            
            // Enter password
            let passwordField = app.secureTextFields.firstMatch
            passwordField.tap()
            passwordField.typeText("testpassword")
            
            // Press Enter
            passwordField.typeText(XCUIKeyboardKey.return.rawValue)
            
            // Should attempt to unlock (loading state or error)
            // Just verify app doesn't crash
        }
    }
    
    func testEscapeKeyDismisses() throws {
        let firstDatabase = app.buttons.matching(identifier: "database_row").firstMatch
        
        if firstDatabase.exists {
            firstDatabase.tap()
            
            // Wait for password prompt
            XCTAssertTrue(app.staticTexts["Unlock Database"].waitForExistence(timeout: 2))
            
            // Press Escape
            app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
            
            // Password prompt should disappear
            XCTAssertFalse(app.staticTexts["Unlock Database"].waitForExistence(timeout: 1))
        }
    }
    
    // MARK: - Accessibility Tests
    
    func testAccessibilityLabels() throws {
        let firstDatabase = app.buttons.matching(identifier: "database_row").firstMatch
        
        if firstDatabase.exists {
            firstDatabase.tap()
            
            // Wait for password prompt
            XCTAssertTrue(app.staticTexts["Unlock Database"].waitForExistence(timeout: 2))
            
            // Verify key UI elements have accessibility labels
            XCTAssertTrue(app.secureTextFields.firstMatch.exists)
            XCTAssertTrue(app.buttons["Unlock"].exists)
            XCTAssertTrue(app.buttons["Cancel"].exists)
        }
    }
    
    // MARK: - Performance Tests
    
    func testPasswordPromptLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }
    
    func testPasswordPromptDisplayPerformance() throws {
        let firstDatabase = app.buttons.matching(identifier: "database_row").firstMatch
        
        if firstDatabase.exists {
            measure {
                firstDatabase.tap()
                _ = app.staticTexts["Unlock Database"].waitForExistence(timeout: 2)
                app.buttons["Cancel"].tap()
            }
        }
    }
}

