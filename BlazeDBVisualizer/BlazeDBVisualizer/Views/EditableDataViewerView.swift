//
//  EditableDataViewerView.swift
//  BlazeDBVisualizer
//
//  Full-featured data editor with inline editing
//  ✅ Double-click to edit fields
//  ✅ Type validation
//  ✅ Add new records
//  ✅ Delete with confirmation
//  ✅ Bulk operations
//  ✅ Undo support
//
//  Created by Michael Danylchuk on 11/14/25.
//

import SwiftUI
import BlazeDB

struct RecordWrapper: Identifiable, Equatable {
    let id: UUID
    let record: BlazeDataRecord
    
    init(record: BlazeDataRecord) {
        self.record = record
        // Extract ID from storage
        if case .uuid(let uuid) = record.storage["id"] {
            self.id = uuid
        } else {
            self.id = UUID() // Fallback
        }
    }
    
    static func == (lhs: RecordWrapper, rhs: RecordWrapper) -> Bool {
        lhs.id == rhs.id
    }
}

struct EditableDataViewerView: View {
    let dbPath: String
    let password: String
    
    @StateObject private var editingService = EditingService()
    @State private var records: [BlazeDataRecord] = []
    @State private var selectedRecords: Set<UUID> = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var sortField: String?
    @State private var sortAscending = true
    @State private var editingEnabled = false
    
    // UI state
    @State private var showingNewRecordSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingBulkEditSheet = false
    @State private var showUndoToast = false
    @State private var errorMessage: String?
    
    // Helper to get UUID from record
    private func getRecordID(_ record: BlazeDataRecord) -> UUID {
        if case .uuid(let uuid) = record.storage["id"] {
            return uuid
        }
        return UUID() // Fallback
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with editing toggle
            headerView
            
            Divider()
            
            // Undo toast notification
            if showUndoToast, let lastOp = editingService.lastOperation,
               editingService.canUndo() {
                undoToastView(operation: lastOp)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(BlazeAnimation.smooth, value: showUndoToast)
            }
            
            // Main content
            if isLoading {
                LoadingView(message: "Loading records...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.animation(BlazeAnimation.gentle))
            } else if records.isEmpty {
                emptyStateView
                    .transition(.scaleAndFade)
            } else {
                dataTableView
                    .transition(.opacity.animation(BlazeAnimation.smooth))
            }
            
            // Bottom toolbar
            if editingEnabled && !selectedRecords.isEmpty {
                selectionToolbar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(BlazeAnimation.smooth, value: selectedRecords.isEmpty)
            }
        }
        .sheet(isPresented: $showingNewRecordSheet) {
            NewRecordSheet(
                dbPath: dbPath,
                password: password,
                onRecordCreated: {
                    loadRecords()
                }
            )
        }
        .alert("Delete Records?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSelectedRecords()
            }
        } message: {
            Text("Delete \(selectedRecords.count) record(s)? This can be undone within 30 seconds.")
        }
        .sheet(isPresented: $showingBulkEditSheet) {
            BulkEditSheet(
                selectedIDs: Array(selectedRecords),
                records: records.filter { selectedRecords.contains(getRecordID($0)) },
                onUpdate: { field, value in
                    bulkUpdateField(field: field, value: value)
                }
            )
        }
        .task {
            do {
                print("🔌 Connecting EditingService to: \(dbPath)")
                try editingService.connect(dbPath: dbPath, password: password)
                print("✅ EditingService connected successfully")
                
                loadRecords()
            } catch {
                print("❌ Failed to connect EditingService: \(error)")
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Image(systemName: "tablecells")
                .font(.title2)
                .foregroundStyle(.blue.gradient)
            
            Text("Data Viewer")
                .font(.title2.bold())
            
            Text("\(records.count) records")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
            
            Spacer()
            
            // Editing mode toggle
            Toggle(isOn: $editingEnabled) {
                HStack(spacing: 4) {
                    Image(systemName: editingEnabled ? "lock.open" : "lock")
                    Text(editingEnabled ? "Editing" : "Read-Only")
                }
                .font(.caption.bold())
            }
            .toggleStyle(.button)
            .tint(editingEnabled ? .orange : .gray)
            .controlSize(.small)
            
            // Search
            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            
            // Add record button (only when editing)
            if editingEnabled {
                Button(action: { showingNewRecordSheet = true }) {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            // Refresh
            Button(action: loadRecords) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isLoading)
        }
        .padding()
    }
    
    // MARK: - Data Table View
    
    private var dataTableView: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                // Table header
                tableHeaderView
                
                Divider()
                
                // Table rows
                ForEach(filteredRecords.map { RecordWrapper(record: $0) }) { wrapper in
                    EditableRecordRow(
                        record: wrapper.record,
                        recordID: wrapper.id,
                        isSelected: selectedRecords.contains(wrapper.id),
                        editingEnabled: editingEnabled,
                        onToggleSelection: {
                            toggleSelection(wrapper.id)
                        },
                        onUpdateField: { field, value in
                            updateRecordField(id: wrapper.id, field: field, value: value)
                        },
                        onDelete: {
                            selectedRecords = [wrapper.id]
                            showingDeleteConfirmation = true
                        }
                    )
                    
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var tableHeaderView: some View {
        HStack(spacing: 0) {
            if editingEnabled {
                // Checkbox column
                Button(action: toggleSelectAll) {
                    Image(systemName: selectedRecords.count == records.count ? "checkmark.square.fill" : "square")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .frame(width: 40)
            }
            
            // ID column
            HeaderCell(title: "ID", width: 120, onSort: { sortBy("id") })
            
            // Dynamic columns based on first record
            if let firstRecord = records.first {
                ForEach(Array(firstRecord.storage.keys.sorted()), id: \.self) { key in
                    HeaderCell(title: key, width: 150, onSort: { sortBy(key) })
                }
            }
            
            // Actions column (when editing)
            if editingEnabled {
                Text("Actions")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
            
            Spacer()
        }
        .background(Color.secondary.opacity(0.1))
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: editingEnabled ? "plus.circle" : "tray")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text(editingEnabled ? "No records yet" : "No data to display")
                .font(.title2.bold())
            
            Text(editingEnabled ? "Click 'Add' to create your first record" : "This database is empty")
                .foregroundColor(.secondary)
            
            if editingEnabled {
                Button(action: { showingNewRecordSheet = true }) {
                    Label("Add Record", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Undo Toast
    
    private func undoToastView(operation: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            
            Text(operation)
                .font(.callout)
            
            if let entry = editingService.undoStack.last {
                Text("(\(Int(entry.timeRemaining))s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Undo") {
                Task {
                    try? await editingService.undo()
                    loadRecords()
                    showUndoToast = false
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Button(action: { showUndoToast = false }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    // MARK: - Selection Toolbar
    
    private var selectionToolbar: some View {
        HStack {
            Text("\(selectedRecords.count) selected")
                .font(.callout.bold())
            
            Spacer()
            
            Button(action: { showingBulkEditSheet = true }) {
                Label("Update Selected", systemImage: "pencil")
            }
            .buttonStyle(.bordered)
            
            Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                Label("Delete Selected", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            
            Button("Clear Selection") {
                selectedRecords.removeAll()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.blue.opacity(0.05))
    }
    
    // MARK: - Actions
    
    private func loadRecords() {
        print("🔄 loadRecords() called")
        isLoading = true
        
        Task {
            do {
                print("📖 Fetching all records...")
                
                // Fetch records in background to avoid blocking UI
                let fetchedRecords = try await Task.detached(priority: .userInitiated) {
                    let db = try BlazeDBClient(name: "temp", fileURL: URL(fileURLWithPath: dbPath), password: password)
                    return try db.fetchAll()
                }.value
                
                print("✅ Fetched \(fetchedRecords.count) records, updating UI")
                records = fetchedRecords
                isLoading = false
            } catch {
                print("❌ Failed to load records: \(error)")
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func toggleSelection(_ id: UUID) {
        if selectedRecords.contains(id) {
            selectedRecords.remove(id)
        } else {
            selectedRecords.insert(id)
        }
    }
    
    private func toggleSelectAll() {
        if selectedRecords.count == records.count {
            selectedRecords.removeAll()
        } else {
            selectedRecords = Set(records.map { getRecordID($0) })
        }
    }
    
    private func sortBy(_ field: String) {
        if sortField == field {
            sortAscending.toggle()
        } else {
            sortField = field
            sortAscending = true
        }
        // TODO: Implement sorting
    }
    
    private func updateRecordField(id: UUID, field: String, value: BlazeDocumentField) {
        print("🔧 updateRecordField called: id=\(id.uuidString.prefix(8)), field=\(field), value=\(value)")
        
        Task {
            do {
                print("🔧 Calling editingService.updateField...")
                try await editingService.updateField(id: id, field: field, value: value)
                
                print("✅ Field updated in database!")
                
                // Immediate UI update: modify the record in-place without reloading
                if let index = records.firstIndex(where: { getRecordID($0) == id }) {
                    records[index].storage[field] = value
                    print("✅ UI updated immediately (no reload, maintaining order)")
                }
                
                showUndoToast = true
                
                // Auto-hide toast after 30 seconds
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                showUndoToast = false
            } catch {
                print("❌ Update failed: \(error)")
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func deleteSelectedRecords() {
        Task {
            do {
                try await editingService.bulkDelete(ids: Array(selectedRecords))
                selectedRecords.removeAll()
                loadRecords()
                showUndoToast = true
                
                // Auto-hide toast after 30 seconds
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                showUndoToast = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func bulkUpdateField(field: String, value: BlazeDocumentField) {
        Task {
            do {
                try await editingService.bulkUpdateField(ids: Array(selectedRecords), field: field, value: value)
                selectedRecords.removeAll()
                loadRecords()
                showUndoToast = true
                showingBulkEditSheet = false
                
                // Auto-hide toast after 30 seconds
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                showUndoToast = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private var filteredRecords: [BlazeDataRecord] {
        guard !searchText.isEmpty else { return records }
        
        return records.filter { record in
            record.storage.values.contains { value in
                Self.displayValue(value).lowercased().contains(searchText.lowercased())
            }
        }
    }
    
    // Helper to convert BlazeDocumentField to display string
    private static func displayValue(_ value: BlazeDocumentField) -> String {
        switch value {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .date(let d): return ISO8601DateFormatter().string(from: d)
        case .uuid(let u): return u.uuidString
        case .data(let d): return "<Data: \(d.count) bytes>"
        case .array(let arr): return "[\(arr.count) items]"
        case .dictionary(let dict): return "{\(dict.count) fields}"
        }
    }
}

// MARK: - Editable Record Row

struct EditableRecordRow: View {
    let record: BlazeDataRecord
    let recordID: UUID
    let isSelected: Bool
    let editingEnabled: Bool
    let onToggleSelection: () -> Void
    let onUpdateField: (String, BlazeDocumentField) -> Void
    let onDelete: () -> Void
    
    @State private var editingField: String?
    @State private var editValue: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            // Checkbox (when editing)
            if editingEnabled {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 40)
            }
            
            // ID column (read-only)
            Text(recordID.uuidString.prefix(8))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
                .padding(.horizontal, 8)
            
            // Field columns
            ForEach(Array(record.storage.keys.sorted()), id: \.self) { key in
                fieldCell(key: key, value: record.storage[key]!)
            }
            
            // Actions column
            if editingEnabled {
                HStack(spacing: 8) {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 80, alignment: .leading)
                .padding(.horizontal, 8)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private func fieldCell(key: String, value: BlazeDocumentField) -> some View {
        if editingEnabled && editingField == key {
            // Edit mode - maintain consistent height
            TextField("", text: $editValue)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .frame(width: 150, height: 22, alignment: .leading) // Fixed height!
                .padding(.horizontal, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)
                .onSubmit {
                    saveEdit(field: key, value: value)
                }
                .onAppear {
                    isFocused = true
                }
        } else {
            // Display mode
            Text(EditableRecordRow.displayValue(value))
                .font(.callout)
                .frame(width: 150, height: 22, alignment: .leading) // Fixed height!
                .padding(.horizontal, 8)
                .onTapGesture(count: 2) {
                    startEditing(field: key, currentValue: value)
                }
        }
    }
    
    private func startEditing(field: String, currentValue: BlazeDocumentField) {
        print("✏️ startEditing: field=\(field), value=\(currentValue), editingEnabled=\(editingEnabled)")
        
        guard editingEnabled else {
            print("⚠️ Editing disabled - ignoring double-click")
            return
        }
        
        editingField = field
        editValue = EditableRecordRow.displayValue(currentValue)
        print("✅ Edit mode activated for field '\(field)'")
    }
    
    private func saveEdit(field: String, value: BlazeDocumentField) {
        print("💾 saveEdit called: field=\(field), editValue=\(editValue), editingEnabled=\(editingEnabled)")
        
        defer {
            editingField = nil
            editValue = ""
        }
        
        guard editingEnabled else {
            print("⚠️ Not saving - editing disabled")
            return
        }
        
        // Parse value based on type
        let newValue: BlazeDocumentField
        
        switch value {
        case .string:
            newValue = .string(editValue)
            print("📝 Parsed as string: \(editValue)")
        case .int:
            guard let int = Int(editValue) else {
                print("❌ Invalid int: \(editValue)")
                return
            }
            newValue = .int(int)
            print("📝 Parsed as int: \(int)")
        case .double:
            guard let double = Double(editValue) else {
                print("❌ Invalid double: \(editValue)")
                return
            }
            newValue = .double(double)
            print("📝 Parsed as double: \(double)")
        case .bool:
            newValue = .bool(editValue.lowercased() == "true" || editValue == "1")
            print("📝 Parsed as bool: \(editValue)")
        case .date:
            guard let date = ISO8601DateFormatter().date(from: editValue) else {
                print("❌ Invalid date: \(editValue)")
                return
            }
            newValue = .date(date)
            print("📝 Parsed as date: \(date)")
        default:
            newValue = .string(editValue)
            print("📝 Defaulted to string: \(editValue)")
        }
        
        print("✅ Calling onUpdateField with: \(newValue)")
        onUpdateField(field, newValue)
    }
    
    static func displayValue(_ value: BlazeDocumentField) -> String {
        switch value {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .date(let d): return ISO8601DateFormatter().string(from: d)
        case .uuid(let u): return u.uuidString
        case .data(let d): return "<Data: \(d.count) bytes>"
        case .array(let arr): return "[\(arr.count) items]"
        case .dictionary(let dict): return "{\(dict.count) fields}"
        }
    }
}

// MARK: - Header Cell

struct HeaderCell: View {
    let title: String
    let width: CGFloat
    let onSort: () -> Void
    
    var body: some View {
        Button(action: onSort) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.primary)
                .frame(width: width, alignment: .leading)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
    }
}

