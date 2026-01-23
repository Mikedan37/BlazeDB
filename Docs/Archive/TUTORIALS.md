# BlazeDB Tutorials

Complete guides to get you started with BlazeDB in minutes.

---

## Tutorial 1: Todo App (10 minutes)

Build a simple todo list app with BlazeDB + SwiftUI.

### Step 1: Setup

```swift
import SwiftUI
import BlazeDB

// 1. Initialize database (in your App struct or view)
let url = FileManager.default.urls(for:.documentDirectory, in:.userDomainMask)[0]
.appendingPathComponent("todos.blazedb")

guard let db = BlazeDBClient(name: "TodoApp", at: url, password: "my-secure-password") else {
 fatalError("Failed to initialize database")
}
```

### Step 2: Create the Model

```swift
struct Todo: Codable, Identifiable {
 let id: UUID
 var title: String
 var isCompleted: Bool
 var createdAt: Date
}
```

### Step 3: Build the View

```swift
struct TodoListView: View {
 // Auto-updating query - no manual state management!
 @BlazeQueryTyped(db: db, type: Todo.self)
 var todos: [Todo]

 @State private var newTodoTitle = ""

 var body: some View {
 NavigationView {
 List {
 ForEach(todos) { todo in
 HStack {
 Image(systemName: todo.isCompleted? "checkmark.circle.fill": "circle")
.foregroundColor(todo.isCompleted?.green:.gray)
.onTapGesture {
 toggleTodo(todo)
 }

 Text(todo.title)
.strikethrough(todo.isCompleted)
 }
 }
.onDelete(perform: deleteTodos)
 }
.navigationTitle("My Todos (\(todos.count))")
.toolbar {
 ToolbarItem(placement:.primaryAction) {
 addButton
 }
 }
 }
 }

 private var addButton: some View {
 Button {
 addTodo()
 } label: {
 Image(systemName: "plus")
 }
 }

 private func addTodo() {
 let todo = Todo(
 id: UUID(),
 title: "New Todo",
 isCompleted: false,
 createdAt: Date()
 )

 Task {
 try await db.insert(todo)
 // View automatically updates!
 }
 }

 private func toggleTodo(_ todo: var Todo) {
 Task {
 todo.isCompleted.toggle()
 try await db.update(todo)
 // View automatically updates!
 }
 }

 private func deleteTodos(at offsets: IndexSet) {
 Task {
 for index in offsets {
 try await db.delete(id: todos[index].id)
 }
 // View automatically updates!
 }
 }
}
```

**That's it!** You now have a fully functional todo app with:
- Data persistence
- ACID transactions
- Encryption
- Crash recovery
- Auto-updating UI

---

## Tutorial 2: Note-Taking App (15 minutes)

Build a notes app with full-text search.

### Step 1: Setup Database

```swift
let url = FileManager.default.urls(for:.documentDirectory, in:.userDomainMask)[0]
.appendingPathComponent("notes.blazedb")

guard let db = BlazeDBClient(name: "NotesApp", at: url, password: "secure-password") else {
 fatalError("Failed to initialize database")
}

// Enable full-text search on title and content
try db.collection.enableSearch(on: ["title", "content"])
```

### Step 2: Create the Model

```swift
struct Note: Codable, Identifiable {
 let id: UUID
 var title: String
 var content: String
 var createdAt: Date
 var updatedAt: Date
 var tags: [String]
}
```

### Step 3: Build the List View

```swift
struct NotesListView: View {
 @BlazeQueryTyped(
 db: db,
 type: Note.self,
 sortBy: "updatedAt",
 descending: true
 )
 var notes: [Note]

 @State private var searchText = ""

 var filteredNotes: [Note] {
 if searchText.isEmpty {
 return notes
 } else {
 // Use full-text search (instant!)
 return (try? db.query(Note.self)
.search(searchText, in: ["title", "content"])
.all())?? []
 }
 }

 var body: some View {
 NavigationView {
 List(filteredNotes) { note in
 NavigationLink(destination: NoteDetailView(note: note, db: db)) {
 VStack(alignment:.leading, spacing: 4) {
 Text(note.title)
.font(.headline)

 Text(note.content)
.font(.caption)
.foregroundColor(.secondary)
.lineLimit(2)

 Text(note.updatedAt, style:.relative)
.font(.caption2)
.foregroundColor(.tertiary)
 }
 }
 }
.searchable(text: $searchText, prompt: "Search notes")
.navigationTitle("Notes")
.toolbar {
 Button("New", action: createNote)
 }
 }
 }

 private func createNote() {
 let note = Note(
 id: UUID(),
 title: "New Note",
 content: "",
 createdAt: Date(),
 updatedAt: Date(),
 tags: []
 )

 Task {
 try await db.insert(note)
 }
 }
}
```

### Step 4: Build the Detail View

```swift
struct NoteDetailView: View {
 @State var note: Note
 let db: BlazeDBClient

 var body: some View {
 Form {
 Section("Title") {
 TextField("Title", text: $note.title)
 }

 Section("Content") {
 TextEditor(text: $note.content)
.frame(minHeight: 200)
 }

 Section("Tags") {
 // Tag editing UI here
 }
 }
.navigationTitle("Edit Note")
.toolbar {
 Button("Save") {
 saveNote()
 }
 }
 }

 private func saveNote() {
 note.updatedAt = Date()

 Task {
 try await db.update(note)
 }
 }
}
```

**Features:**
- Full-text search across all notes
- Auto-save on edit
- Organized by recent updates
- Tag support
- Encrypted storage

---

## Tutorial 3: Bug Tracker (20 minutes)

Build a collaborative bug tracker with relationships.

### Step 1: Setup

```swift
// Two databases: bugs and users
let bugsURL = // path to bugs.blazedb
let usersURL = // path to users.blazedb

guard let bugsDB = BlazeDBClient(name: "Bugs", at: bugsURL, password: "pass"),
 let usersDB = BlazeDBClient(name: "Users", at: usersURL, password: "pass") else {
 fatalError("Failed to initialize databases")
}
```

### Step 2: Create Models

```swift
struct Bug: Codable, Identifiable {
 let id: UUID
 var title: String
 var description: String
 var status: BugStatus
 var priority: Int
 var authorId: UUID // Foreign key to User
 var assigneeId: UUID?
 var createdAt: Date
 var updatedAt: Date
}

enum BugStatus: String, Codable {
 case open, inProgress, closed
}

struct User: Codable, Identifiable {
 let id: UUID
 var name: String
 var email: String
}
```

### Step 3: Build the Bug List

```swift
struct BugListView: View {
 @BlazeQueryTyped(
 db: bugsDB,
 type: Bug.self,
 where: "status", notEquals:.string("closed"),
 sortBy: "priority",
 descending: true
 )
 var openBugs: [Bug]

 var body: some View {
 List(openBugs) { bug in
 BugRowView(bug: bug, usersDB: usersDB)
 }
 }
}
```

### Step 4: Display with JOIN

```swift
struct BugRowView: View {
 let bug: Bug
 let usersDB: BlazeDBClient

 @State private var author: User?

 var body: some View {
 VStack(alignment:.leading, spacing: 4) {
 Text(bug.title)
.font(.headline)

 HStack {
 PriorityBadge(priority: bug.priority)

 if let author = author {
 Text("by \(author.name)")
.font(.caption)
.foregroundColor(.secondary)
 }
 }
 }
.task {
 author = try? await usersDB.fetch(User.self, id: bug.authorId)
 }
 }
}
```

**Or use JOIN for better performance:**

```swift
// Fetch all bugs with their authors in ONE query
let bugsWithAuthors = try bugsDB.join(
 with: usersDB,
 on: "authorId",
 equals: "id",
 type:.inner
)

for joined in bugsWithAuthors {
 let bug = try Bug(from: joined.left)
 let author = try User(from: joined.right!)
 print("\(bug.title) by \(author.name)")
}
```

**Features:**
- Multiple related databases
- Efficient JOINs
- Priority sorting
- Status filtering
- User assignments

---

## Next Steps

- **Performance:** Add indexes with `db.collection.createIndex(on: ["status", "priority"])`
- **Analytics:** Use aggregations `db.query().groupBy("status").count().execute()`
- **Real-time:** Enable auto-refresh with `$bugs.enableAutoRefresh(interval: 5.0)`
- **Security:** Add Row-Level Security with `db.setSecurityPolicy(...)`

See full documentation in `README.md` and `Docs/` folder.

