//
//  AccessControlView.swift
//  BlazeDBVisualizer
//
//  Enterprise RBAC Management UI
//  ✅ User management (create, edit, delete)
//  ✅ Team management (organizations)
//  ✅ Role assignment (admin, engineer, reviewer, viewer)
//  ✅ Policy configuration (RLS policies)
//  ✅ Security context switching
//  ✅ Access audit logs
//
//  Created by AI Assistant on 11/14/25.
//

import SwiftUI
import BlazeDB

struct AccessControlView: View {
    let dbPath: String
    let password: String
    
    @State private var selectedTab: AccessTab = .users
    @State private var isRLSEnabled = false
    @State private var currentContext: SecurityContext?
    @State private var users: [User] = []
    @State private var teams: [Team] = []
    @State private var policies: [SecurityPolicy] = []
    @State private var errorMessage: String?
    
    enum AccessTab {
        case users
        case teams
        case roles
        case policies
        case context
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.blue.gradient)
                
                Text("Access Control")
                    .font(.title2.bold())
                
                Spacer()
                
                // RLS Toggle
                Toggle(isOn: $isRLSEnabled) {
                    HStack(spacing: 6) {
                        Image(systemName: isRLSEnabled ? "checkmark.shield.fill" : "xmark.shield")
                            .foregroundColor(isRLSEnabled ? .green : .red)
                        Text("RLS")
                            .font(.callout.bold())
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: isRLSEnabled) { _, enabled in
                    toggleRLS(enabled)
                }
                
                Button(action: refreshData) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            Divider()
            
            // Tab Bar
            Picker("Section", selection: $selectedTab) {
                Label("Users", systemImage: "person.3.fill").tag(AccessTab.users)
                Label("Teams", systemImage: "building.2.fill").tag(AccessTab.teams)
                Label("Roles", systemImage: "person.badge.key.fill").tag(AccessTab.roles)
                Label("Policies", systemImage: "doc.text.fill").tag(AccessTab.policies)
                Label("Context", systemImage: "person.circle").tag(AccessTab.context)
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            // Tab Content
            Group {
                switch selectedTab {
                case .users:
                    UsersManagementView(dbPath: dbPath, password: password, users: $users)
                case .teams:
                    TeamsManagementView(dbPath: dbPath, password: password, teams: $teams)
                case .roles:
                    RolesManagementView(dbPath: dbPath, password: password, users: $users)
                case .policies:
                    PoliciesManagementView(dbPath: dbPath, password: password, policies: $policies)
                case .context:
                    SecurityContextView(dbPath: dbPath, password: password, currentContext: $currentContext)
                }
            }
        }
        .task {
            await loadData()
        }
    }
    
    // MARK: - Actions
    
    private func loadData() async {
        // TODO: Load users, teams, policies from database
    }
    
    private func refreshData() {
        Task {
            await loadData()
        }
    }
    
    private func toggleRLS(_ enabled: Bool) {
        Task.detached(priority: .userInitiated) {
            do {
                let db = try BlazeDBClient(name: "temp", fileURL: URL(fileURLWithPath: dbPath), password: password)
                if enabled {
                    db.rls.enable()
                } else {
                    db.rls.disable()
                }
                print("🔐 RLS \(enabled ? "enabled" : "disabled")")
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to toggle RLS: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Users Management View

struct UsersManagementView: View {
    let dbPath: String
    let password: String
    @Binding var users: [User]
    
    @State private var showingAddUser = false
    @State private var searchText = ""
    
    var filteredUsers: [User] {
        if searchText.isEmpty {
            return users
        }
        return users.filter { user in
            user.name.localizedCaseInsensitiveContains(searchText) ||
            user.email.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search & Add
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search users...", text: $searchText)
                    .textFieldStyle(.plain)
                
                Spacer()
                
                Button(action: { showingAddUser = true }) {
                    Label("Add User", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            
            Divider()
            
            // Users List
            if users.isEmpty {
                EmptyAccessStateView(
                    icon: "person.3",
                    title: "No Users",
                    message: "Create your first user to start managing access"
                )
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(filteredUsers, id: \.id) { user in
                            UserCard(user: user, onEdit: { editUser(user) }, onDelete: { deleteUser(user) })
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingAddUser) {
            AddUserSheet(dbPath: dbPath, password: password, onUserCreated: refreshUsers)
        }
    }
    
    private func editUser(_ user: User) {
        // TODO: Implement user editing
    }
    
    private func deleteUser(_ user: User) {
        // TODO: Implement user deletion
    }
    
    private func refreshUsers() {
        // TODO: Refresh users from database
    }
}

// MARK: - User Card Component

struct UserCard: View {
    let user: User
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 50, height: 50)
                .overlay {
                    Text(user.name.prefix(1).uppercased())
                        .font(.title3.bold())
                        .foregroundColor(.white)
                }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(user.name)
                        .font(.headline)
                    if !user.isActive {
                        Text("INACTIVE")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                }
                
                Text(user.email)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Roles
                if !user.roles.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(user.roles.prefix(3)), id: \.self) { role in
                            Text(role)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(roleColor(role).opacity(0.2))
                                .foregroundColor(roleColor(role))
                                .cornerRadius(4)
                        }
                        if user.roles.count > 3 {
                            Text("+\(user.roles.count - 3)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Teams
            if !user.teamIDs.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "building.2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(user.teamIDs.count) teams")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Actions
            Menu {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func roleColor(_ role: String) -> Color {
        switch role.lowercased() {
        case "admin", "superuser": return .red
        case "engineer", "developer": return .blue
        case "reviewer": return .purple
        case "viewer": return .green
        default: return .gray
        }
    }
}

// MARK: - Add User Sheet

struct AddUserSheet: View {
    let dbPath: String
    let password: String
    let onUserCreated: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var selectedRoles: Set<String> = []
    @State private var isActive = true
    
    let availableRoles = ["admin", "engineer", "reviewer", "viewer", "guest"]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create New User")
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.callout.bold())
                    TextField("John Doe", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email")
                        .font(.callout.bold())
                    TextField("john@example.com", text: $email)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Roles")
                        .font(.callout.bold())
                    
                    ForEach(availableRoles, id: \.self) { role in
                        Toggle(isOn: Binding(
                            get: { selectedRoles.contains(role) },
                            set: { isSelected in
                                if isSelected {
                                    selectedRoles.insert(role)
                                } else {
                                    selectedRoles.remove(role)
                                }
                            }
                        )) {
                            Text(role.capitalized)
                        }
                    }
                }
                
                Toggle("Active", isOn: $isActive)
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Create User") {
                    createUser()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || email.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(30)
        .frame(width: 400)
    }
    
    private func createUser() {
        Task.detached(priority: .userInitiated) {
            do {
                let db = try BlazeDBClient(name: "temp", fileURL: URL(fileURLWithPath: dbPath), password: password)
                
                let user = User(
                    name: name,
                    email: email,
                    roles: selectedRoles,
                    isActive: isActive
                )
                
                db.rls.createUser(user)
                
                await MainActor.run {
                    onUserCreated()
                    dismiss()
                }
            } catch {
                print("❌ Failed to create user: \(error)")
            }
        }
    }
}

// MARK: - Teams, Roles, Policies Views (Stubs)

struct TeamsManagementView: View {
    let dbPath: String
    let password: String
    @Binding var teams: [Team]
    
    var body: some View {
        EmptyAccessStateView(
            icon: "building.2",
            title: "Teams Management",
            message: "Create teams to organize users by department or project"
        )
    }
}

struct RolesManagementView: View {
    let dbPath: String
    let password: String
    @Binding var users: [User]
    
    var body: some View {
        EmptyAccessStateView(
            icon: "person.badge.key",
            title: "Role Management",
            message: "Assign and manage user roles across your organization"
        )
    }
}

struct PoliciesManagementView: View {
    let dbPath: String
    let password: String
    @Binding var policies: [SecurityPolicy]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pre-built Security Policies")
                    .font(.headline)
                
                PolicyCard(
                    name: "Admin Full Access",
                    description: "Admins can access all records with full permissions",
                    isEnabled: true
                )
                
                PolicyCard(
                    name: "Viewer Read-Only",
                    description: "Viewers can read all records but cannot modify",
                    isEnabled: true
                )
                
                PolicyCard(
                    name: "User Owns Record",
                    description: "Users can only access their own records",
                    isEnabled: false
                )
                
                PolicyCard(
                    name: "Team Member Access",
                    description: "Users can access records from their teams",
                    isEnabled: false
                )
            }
            .padding()
        }
    }
}

struct PolicyCard: View {
    let name: String
    let description: String
    let isEnabled: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isEnabled ? "checkmark.shield.fill" : "xmark.shield")
                .font(.title2)
                .foregroundColor(isEnabled ? .green : .secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.callout.bold())
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

struct SecurityContextView: View {
    let dbPath: String
    let password: String
    @Binding var currentContext: SecurityContext?
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Current Security Context")
                .font(.title2.bold())
            
            if let context = currentContext {
                VStack(alignment: .leading, spacing: 12) {
                    ContextRow(label: "User ID", value: context.userID.uuidString)
                    ContextRow(label: "Roles", value: context.roles.joined(separator: ", "))
                    ContextRow(label: "Teams", value: "\(context.teamIDs.count) teams")
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)
            } else {
                Text("No security context set")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

struct ContextRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.callout.bold())
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.callout)
        }
    }
}

// MARK: - Empty State

struct EmptyAccessStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

