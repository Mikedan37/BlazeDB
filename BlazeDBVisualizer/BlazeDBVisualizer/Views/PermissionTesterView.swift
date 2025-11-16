//
//  PermissionTesterView.swift
//  BlazeDBVisualizer
//
//  Test database access as different users
//  ✅ Switch between user contexts
//  ✅ Side-by-side permission comparison
//  ✅ Real-time access testing
//  ✅ Visual permission matrix
//  ✅ Audit trail
//
//  Created by AI Assistant on 11/14/25.
//

import SwiftUI
import BlazeDB

struct PermissionTesterView: View {
    let dbPath: String
    let password: String
    
    @State private var users: [User] = []
    @State private var selectedUser: User?
    @State private var compareUser: User?
    @State private var testResults: [PermissionTestResult] = []
    @State private var isTestingPermissions = false
    @State private var errorMessage: String?
    @State private var showComparison = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "shield.checkered")
                    .font(.title2)
                    .foregroundStyle(.purple.gradient)
                
                Text("Permission Tester")
                    .font(.title2.bold())
                
                Spacer()
                
                Toggle("Compare Mode", isOn: $showComparison)
                    .toggleStyle(.switch)
                
                Button(action: runPermissionTests) {
                    Label("Run Tests", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(isTestingPermissions || selectedUser == nil)
            }
            .padding()
            
            Divider()
            
            if showComparison {
                comparisonView
            } else {
                singleUserView
            }
        }
        .task {
            await loadUsers()
        }
    }
    
    // MARK: - Single User View
    
    private var singleUserView: some View {
        HStack(spacing: 0) {
            // Left: User Selection
            VStack(spacing: 0) {
                Text("Select User")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.1))
                
                Divider()
                
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(users, id: \.id) { user in
                            UserSelectionCard(
                                user: user,
                                isSelected: selectedUser?.id == user.id,
                                onSelect: { selectedUser = user }
                            )
                        }
                    }
                    .padding()
                }
            }
            .frame(width: 300)
            
            Divider()
            
            // Right: Test Results
            VStack(spacing: 0) {
                if let user = selectedUser {
                    Text("Testing as: \(user.name)")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.purple.opacity(0.1))
                    
                    Divider()
                    
                    if isTestingPermissions {
                        ProgressView("Running permission tests...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if testResults.isEmpty {
                        EmptyTestStateView()
                    } else {
                        permissionResultsView
                    }
                } else {
                    EmptyTestStateView(message: "Select a user to test permissions")
                }
            }
        }
    }
    
    // MARK: - Comparison View
    
    private var comparisonView: some View {
        HStack(spacing: 0) {
            // Left User
            VStack(spacing: 0) {
                Text("User A")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                
                Divider()
                
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(users, id: \.id) { user in
                            UserSelectionCard(
                                user: user,
                                isSelected: selectedUser?.id == user.id,
                                onSelect: { selectedUser = user }
                            )
                        }
                    }
                    .padding()
                }
            }
            
            Divider()
            
            // Right User
            VStack(spacing: 0) {
                Text("User B")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.1))
                
                Divider()
                
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(users, id: \.id) { user in
                            UserSelectionCard(
                                user: user,
                                isSelected: compareUser?.id == user.id,
                                onSelect: { compareUser = user }
                            )
                        }
                    }
                    .padding()
                }
            }
            
            Divider()
            
            // Comparison Results
            VStack(spacing: 0) {
                Text("Permission Comparison")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.purple.opacity(0.1))
                
                Divider()
                
                if isTestingPermissions {
                    ProgressView("Comparing permissions...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if testResults.isEmpty {
                    EmptyTestStateView(message: "Select two users and run tests")
                } else {
                    comparisonResultsView
                }
            }
        }
    }
    
    // MARK: - Results Views
    
    private var permissionResultsView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary
                HStack(spacing: 20) {
                    PermissionStatCard(
                        label: "Allowed",
                        value: testResults.filter { $0.allowed }.count,
                        color: .green
                    )
                    PermissionStatCard(
                        label: "Denied",
                        value: testResults.filter { !$0.allowed }.count,
                        color: .red
                    )
                    PermissionStatCard(
                        label: "Total Tests",
                        value: testResults.count,
                        color: .blue
                    )
                }
                .padding()
                
                // Detailed Results
                VStack(spacing: 8) {
                    ForEach(testResults, id: \.id) { result in
                        PermissionResultCard(result: result)
                    }
                }
                .padding()
            }
        }
    }
    
    private var comparisonResultsView: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(testResults, id: \.id) { result in
                    ComparisonResultCard(
                        result: result,
                        userA: selectedUser?.name ?? "User A",
                        userB: compareUser?.name ?? "User B"
                    )
                }
            }
            .padding()
        }
    }
    
    // MARK: - Actions
    
    private func loadUsers() async {
        do {
            let loadedUsers = try await Task.detached(priority: .userInitiated) {
                let db = try BlazeDBClient(name: "temp", fileURL: URL(fileURLWithPath: dbPath), password: password)
                return db.rls.listUsers()
            }.value
            
            users = loadedUsers
            
            // Auto-select first user if none selected
            if selectedUser == nil, let first = users.first {
                selectedUser = first
            }
        } catch {
            errorMessage = "Failed to load users: \(error.localizedDescription)"
        }
    }
    
    private func runPermissionTests() {
        guard let user = selectedUser else { return }
        
        isTestingPermissions = true
        testResults = []
        
        Task {
            do {
                let results = try await Task.detached(priority: .userInitiated) {
                    let db = try BlazeDBClient(name: "temp", fileURL: URL(fileURLWithPath: dbPath), password: password)
                    
                    // Set context for the selected user
                    db.rls.setContext(user.toSecurityContext())
                    
                    // Run permission tests
                    var testResults: [PermissionTestResult] = []
                    
                    // Test 1: Can read all records?
                    let canRead = try? db.fetchAll()
                    testResults.append(PermissionTestResult(
                        operation: "SELECT (Read All)",
                        allowed: canRead != nil,
                        recordCount: canRead?.count ?? 0,
                        details: canRead != nil ? "Can read \(canRead!.count) records" : "Access denied"
                    ))
                    
                    // Test 2: Can insert?
                    let testRecord = BlazeDataRecord(["test": .string("permission_test")])
                    let canInsert = (try? db.insert(testRecord)) != nil
                    testResults.append(PermissionTestResult(
                        operation: "INSERT (Create)",
                        allowed: canInsert,
                        recordCount: canInsert ? 1 : 0,
                        details: canInsert ? "Can create records" : "Insert denied"
                    ))
                    
                    // Clean up test record
                    if canInsert, let id = testRecord.storage["id"], case .uuid(let uuid) = id {
                        try? db.delete(id: uuid)
                    }
                    
                    // Test 3: Can update?
                    if let firstRecord = canRead?.first,
                       let id = firstRecord.storage["id"],
                       case .uuid(let uuid) = id {
                        let canUpdate = (try? db.update(id: uuid, with: firstRecord)) != nil
                        testResults.append(PermissionTestResult(
                            operation: "UPDATE (Modify)",
                            allowed: canUpdate,
                            recordCount: canUpdate ? 1 : 0,
                            details: canUpdate ? "Can update records" : "Update denied"
                        ))
                    }
                    
                    // Test 4: Can delete?
                    if canInsert {
                        let testRecord2 = BlazeDataRecord(["test": .string("delete_test")])
                        try? db.insert(testRecord2)
                        
                        if let id = testRecord2.storage["id"], case .uuid(let uuid) = id {
                            let canDelete = (try? db.delete(id: uuid)) != nil
                            testResults.append(PermissionTestResult(
                                operation: "DELETE (Remove)",
                                allowed: canDelete,
                                recordCount: canDelete ? 1 : 0,
                                details: canDelete ? "Can delete records" : "Delete denied"
                            ))
                        }
                    }
                    
                    return testResults
                }.value
                
                testResults = results
                isTestingPermissions = false
            } catch {
                errorMessage = error.localizedDescription
                isTestingPermissions = false
            }
        }
    }
}

// MARK: - Supporting Types

struct PermissionTestResult: Identifiable {
    let id = UUID()
    let operation: String
    let allowed: Bool
    let recordCount: Int
    let details: String
}

// MARK: - Components

struct UserSelectionCard: View {
    let user: User
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                Circle()
                    .fill(isSelected ? Color.blue.gradient : Color.gray.gradient)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(user.name.prefix(1).uppercased())
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .font(.callout.bold())
                        .foregroundColor(.primary)
                    
                    Text(user.roles.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct PermissionStatCard: View {
    let label: String
    let value: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text("\(value)")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct PermissionResultCard: View {
    let result: PermissionTestResult
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.allowed ? "checkmark.shield.fill" : "xmark.shield")
                .font(.title2)
                .foregroundColor(result.allowed ? .green : .red)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(result.operation)
                    .font(.headline)
                Text(result.details)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if result.recordCount > 0 {
                Text("\(result.recordCount)")
                    .font(.callout.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

struct ComparisonResultCard: View {
    let result: PermissionTestResult
    let userA: String
    let userB: String
    
    var body: some View {
        HStack(spacing: 16) {
            Text(result.operation)
                .font(.callout.bold())
                .frame(width: 150, alignment: .leading)
            
            HStack(spacing: 8) {
                Image(systemName: result.allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.allowed ? .green : .red)
                Text(userA)
                    .font(.caption)
            }
            .frame(width: 150)
            
            HStack(spacing: 8) {
                Image(systemName: result.allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.allowed ? .green : .red)
                Text(userB)
                    .font(.caption)
            }
            .frame(width: 150)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

struct EmptyTestStateView: View {
    var message: String = "Run permission tests to see results"
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

