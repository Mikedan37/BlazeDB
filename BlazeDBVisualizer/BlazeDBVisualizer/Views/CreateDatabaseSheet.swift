//
//  CreateDatabaseSheet.swift
//  BlazeDBVisualizer
//
//  Create new BlazeDB databases from the UI
//  ✅ Choose name & location
//  ✅ Set encryption password
//  ✅ Define initial schema
//  ✅ Add sample data
//
//  Created by Michael Danylchuk on 11/14/25.
//

import SwiftUI
import BlazeDB

struct CreateDatabaseSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onDatabaseCreated: () -> Void
    
    @State private var databaseName = ""
    @State private var location: DatabaseLocation = .desktop
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var enableEncryption = true
    @State private var createSampleData = false
    @State private var isCreating = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    
    // Schema definition
    @State private var fields: [(String, NewRecordSheet.FieldType)] = []
    @State private var fieldName = ""
    @State private var fieldType: NewRecordSheet.FieldType = .string
    
    enum DatabaseLocation: String, CaseIterable, Identifiable {
        case desktop = "Desktop"
        case documents = "Documents"
        case applicationSupport = "Application Support"
        case custom = "Custom..."
        
        var id: String { rawValue }
        
        var path: String {
            let home = FileManager.default.homeDirectoryForCurrentUser
            switch self {
            case .desktop:
                return home.appendingPathComponent("Desktop").path
            case .documents:
                return home.appendingPathComponent("Documents").path
            case .applicationSupport:
                return home.appendingPathComponent("Library/Application Support/BlazeDB").path
            case .custom:
                return home.appendingPathComponent("Desktop").path  // Default for custom
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom header
            HStack {
                Text("Create New Database")
                    .font(.title2.bold())
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header Icon
                    VStack(spacing: 8) {
                        Image(systemName: "cylinder.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.orange.gradient)
                        
                        Text("Set up a new BlazeDB database with encryption and schema")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)
                    
                    // Basic settings
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Database Settings")
                            .font(.headline)
                        
                        // Name
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Database Name")
                                .font(.callout.bold())
                            TextField("e.g., my_app_data", text: $databaseName)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        // Location
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Location")
                                .font(.callout.bold())
                            Picker("Location", selection: $location) {
                                ForEach(DatabaseLocation.allCases) { loc in
                                    Text(loc.rawValue).tag(loc)
                                }
                            }
                            .pickerStyle(.menu)
                            
                            Text(fullPath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    
                    // Encryption settings
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle(isOn: $enableEncryption) {
                            HStack {
                                Text("Enable Encryption")
                                    .font(.headline)
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                        .toggleStyle(.switch)
                        
                        if enableEncryption {
                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Password")
                                        .font(.callout.bold())
                                    SecureField("Enter password", text: $password)
                                        .textFieldStyle(.roundedBorder)
                                    Text("Minimum 8 characters recommended")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Confirm Password")
                                        .font(.callout.bold())
                                    SecureField("Re-enter password", text: $confirmPassword)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    if !password.isEmpty && !confirmPassword.isEmpty {
                                        if password == confirmPassword {
                                            Label("Passwords match", systemImage: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        } else {
                                            Label("Passwords don't match", systemImage: "xmark.circle.fill")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    
                    // Schema definition
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Schema Definition (Optional)")
                            .font(.headline)
                        
                        Text("Define fields for your database. You can always add more later.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Add field
                        HStack(spacing: 12) {
                            TextField("Field name", text: $fieldName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 150)
                            
                            Picker("Type", selection: $fieldType) {
                                ForEach(NewRecordSheet.FieldType.allCases) { type in
                                    Label(type.rawValue, systemImage: type.icon)
                                        .tag(type)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 140)
                            
                            Button(action: addField) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            .disabled(fieldName.isEmpty)
                        }
                        
                        // Field list
                        if !fields.isEmpty {
                            VStack(spacing: 6) {
                                ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                                    HStack {
                                        Image(systemName: field.1.icon)
                                            .foregroundColor(.blue)
                                            .frame(width: 20)
                                        
                                        Text(field.0)
                                            .font(.callout.bold())
                                        
                                        Text("(\(field.1.rawValue))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                        
                                        Button(action: { removeField(at: index) }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(Color.secondary.opacity(0.05))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(8)
                    
                    // Sample data option
                    Toggle(isOn: $createSampleData) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Create Sample Data")
                                .font(.callout.bold())
                            Text("Adds 10 sample records for testing")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    
                    // Error message
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.callout)
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer with Create button
            HStack {
                Spacer()
                
                if isCreating {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 8)
                    Text("Creating database...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    Button("Create Database") {
                        createDatabase()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(!canCreate)
                    .keyboardShortcut(.return)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 600, height: 700)
        .overlay {
            if showSuccess {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.green)
                            .scaleEffect(showSuccess ? 1.0 : 0.1)
                        
                        Text("Database Created!")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                    }
                    .scaleEffect(showSuccess ? 1.0 : 0.5)
                    .opacity(showSuccess ? 1.0 : 0)
                }
                .transition(.opacity)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var fullPath: String {
        "\(location.path)/\(databaseName.isEmpty ? "database" : databaseName).blazedb"
    }
    
    private var canCreate: Bool {
        !databaseName.isEmpty &&
        (!enableEncryption || (password.count >= 4 && password == confirmPassword))
    }
    
    // MARK: - Actions
    
    private func addField() {
        guard !fieldName.isEmpty else { return }
        fields.append((fieldName, fieldType))
        fieldName = ""
        errorMessage = nil
    }
    
    private func removeField(at index: Int) {
        fields.remove(at: index)
    }
    
    private func createDatabase() {
        guard canCreate else { return }
        
        isCreating = true
        errorMessage = nil
        
        let databaseNameCopy = databaseName
        let locationCopy = location
        let enableEncryptionCopy = enableEncryption
        let passwordCopy = password
        let createSampleDataCopy = createSampleData
        let fieldsCopy = fields
        
        Task {
            do {
                // Offload synchronous operations to background
                try await Task.detached(priority: .userInitiated) {
                    // Create directory if needed
                    let locationURL = URL(fileURLWithPath: locationCopy.path)
                    try FileManager.default.createDirectory(at: locationURL, withIntermediateDirectories: true)
                    
                    // Create database file
                    let dbURL = locationURL.appendingPathComponent("\(databaseNameCopy).blazedb")
                    
                    // Check if exists
                    if FileManager.default.fileExists(atPath: dbURL.path) {
                        throw DatabaseCreationError.alreadyExists(name: databaseNameCopy)
                    }
                    
                    // Create database
                    let db = try BlazeDBClient(
                        name: databaseNameCopy,
                        fileURL: dbURL,
                        password: enableEncryptionCopy ? passwordCopy : ""
                    )
                    
                    // Add sample data if requested
                    if createSampleDataCopy {
                        try self.createSampleRecords(db: db, fields: fieldsCopy)
                    }
                    
                    // Persist
                    try db.persist()
                    
                    print("✅ Database created: \(dbURL.path)")
                }.value
                
                // Success animation!
                withAnimation(BlazeAnimation.elastic) {
                    showSuccess = true
                }
                
                // Wait for animation, then dismiss
                try? await Task.sleep(nanoseconds: 800_000_000)  // 0.8s
                
                onDatabaseCreated()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
    
    private func createSampleRecords(db: BlazeDBClient, fields: [(String, NewRecordSheet.FieldType)]) throws {
        for i in 1...10 {
            var storage: [String: BlazeDocumentField] = [:]
            
            for (name, type) in fields {
                storage[name] = sampleValue(for: type, index: i)
            }
            
            // Add some default fields if none specified
            if fields.isEmpty {
                storage["name"] = .string("Sample \(i)")
                storage["index"] = .int(i)
                storage["created"] = .date(Date())
                storage["active"] = .bool(i % 2 == 0)
            }
            
            _ = try db.insert(BlazeDataRecord(storage))
        }
    }
    
    private func sampleValue(for type: NewRecordSheet.FieldType, index: Int) -> BlazeDocumentField {
        switch type {
        case .string:
            return .string("Sample \(index)")
        case .int:
            return .int(index * 10)
        case .double:
            return .double(Double(index) * 3.14)
        case .bool:
            return .bool(index % 2 == 0)
        case .date:
            return .date(Date())
        case .uuid:
            return .uuid(UUID())
        }
    }
}

// MARK: - Database Creation Error

enum DatabaseCreationError: LocalizedError {
    case alreadyExists(name: String)
    case invalidName
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .alreadyExists(let name):
            return "Database '\(name)' already exists at this location"
        case .invalidName:
            return "Invalid database name. Use letters, numbers, and underscores only."
        case .permissionDenied:
            return "Permission denied. Choose a different location."
        }
    }
}

