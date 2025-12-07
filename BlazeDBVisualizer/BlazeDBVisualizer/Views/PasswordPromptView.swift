//
//  PasswordPromptView.swift
//  BlazeDBVisualizer
//
//  Password prompt with biometric unlock support
//  ✅ Face ID/Touch ID integration
//  ✅ Remember password option
//  ✅ Beautiful, user-friendly UI
//
//  Created by Michael Danylchuk on 11/13/25.
//

import SwiftUI
import BlazeDB

struct PasswordPromptView: View {
    let dbRecord: DBRecord
    let onUnlock: (String) -> Void
    let onCancel: () -> Void
    
    @State private var password: String = ""
    @State private var rememberPassword: Bool = true
    @State private var isUnlocking = false
    @State private var errorMessage: String?
    @State private var showPassword: Bool = false
    
    @FocusState private var isPasswordFieldFocused: Bool
    
    private let vault = PasswordVaultService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.orange.gradient)
                
                Text("Unlock Database")
                    .font(.title.bold())
                
                Text(dbRecord.name)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)
            
            // Password field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if showPassword {
                        TextField("Enter password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .focused($isPasswordFieldFocused)
                    } else {
                        SecureField("Enter password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .focused($isPasswordFieldFocused)
                    }
                    
                    Button(action: { showPassword.toggle() }) {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(showPassword ? "Hide password" : "Show password")
                }
                
                // Remember password toggle
                Toggle(isOn: $rememberPassword) {
                    HStack(spacing: 4) {
                        Text("Remember password")
                            .font(.callout)
                        if vault.isBiometricsAvailable() {
                            Text("(\(vault.biometricType()))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
            
            // Error message
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
            }
            
            // Biometric unlock button (if available)
            if vault.hasStoredPassword(for: dbRecord.path) {
                Button(action: unlockWithBiometrics) {
                    HStack {
                        Image(systemName: "faceid")
                        Text("Unlock with \(vault.biometricType())")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
                .disabled(isUnlocking)
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button(action: unlockWithPassword) {
                    if isUnlocking {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 100)
                    } else {
                        Text("Unlock")
                            .frame(width: 100)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(password.isEmpty || isUnlocking)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        .onAppear {
            // Auto-focus password field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPasswordFieldFocused = true
            }
            
            // Try biometric unlock immediately if available
            if vault.hasStoredPassword(for: dbRecord.path) && rememberPassword {
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
                    unlockWithBiometrics()
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func unlockWithPassword() {
        guard !password.isEmpty else { return }
        
        isUnlocking = true
        errorMessage = nil
        
        Task { @MainActor in
            do {
                // Attempt to open database with password
                // This validates the password
                let url = URL(fileURLWithPath: dbRecord.path)
                let name = url.deletingPathExtension().lastPathComponent
                _ = try BlazeDBClient(name: name, fileURL: url, password: password)
                
                // Save password if requested
                if rememberPassword {
                    try? vault.savePassword(password, for: dbRecord.path, useBiometrics: true)
                }
                
                // Success!
                onUnlock(password)
                
            } catch {
                // Wrong password or database error
                errorMessage = "Invalid password or corrupted database"
                isUnlocking = false
            }
        }
    }
    
    private func unlockWithBiometrics() {
        guard vault.hasStoredPassword(for: dbRecord.path) else { return }
        
        isUnlocking = true
        errorMessage = nil
        
        Task { @MainActor in
            do {
                let storedPassword = try vault.getPassword(
                    for: dbRecord.path,
                    reason: "Unlock \(dbRecord.name)"
                )
                
                // Validate password by attempting to open database
                let url = URL(fileURLWithPath: dbRecord.path)
                let name = url.deletingPathExtension().lastPathComponent
                _ = try BlazeDBClient(name: name, fileURL: url, password: storedPassword)
                
                // Success!
                onUnlock(storedPassword)
                
            } catch PasswordVaultError.userCancelled {
                // User cancelled Face ID prompt, just reset state
                isUnlocking = false
            } catch {
                // Biometric unlock failed
                errorMessage = "Biometric unlock failed. Please enter password manually."
                isUnlocking = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PasswordPromptView(
        dbRecord: DBRecord(
            name: "test_database",
            path: "/Users/test/test_database.blazedb",
            appName: "TestApp",
            sizeInBytes: 1_024_000,
            recordCount: 100,
            modifiedDate: Date()
        ),
        onUnlock: { _ in },
        onCancel: {}
    )
    .padding(40)
    .background(Color.gray.opacity(0.3))
}

