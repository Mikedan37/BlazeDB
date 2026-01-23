# BlazeStudio - Visual Editor Documentation

**Visual block-based editor for building database schemas and queries.**

---

## **Overview**

BlazeStudio is a visual block-based editor that lets you design database schemas, build queries, and create data models using a drag-and-drop interface.

---

## **Features**

### **Block-Based Design:**
- **Structure Blocks** - Define classes, entities, relationships
- **Logic Blocks** - Functions, variables, conditions, loops
- **Visual Connections** - Connect blocks to define relationships
- **Real-time Preview** - See results as you build

### **Schema Design:**
- Visual schema editor
- Relationship mapping
- Field type definitions
- Index creation

### **Query Builder:**
- Visual query construction
- Filter conditions
- Sorting and pagination
- Join operations

---

## **Getting Started**

1. **Launch BlazeStudio**
 - Open the BlazeStudio app
 - Create a new project or open existing

2. **Create Blocks**
 - Drag blocks from the palette
 - Connect blocks to define relationships
 - Set block properties

3. **Generate Code**
 - Export schema to Swift
 - Generate BlazeDB code
 - Copy to your project

---

## **Block Types**

### **Structure Blocks:**

#### **Class Block**
Defines a data model/class.

**Properties:**
- Name
- Fields (name, type, optional)
- Relationships

**Example:**
```
Class: User
Fields:
 - id: UUID
 - name: String
 - email: String
```

#### **Connector Block**
Defines relationships between classes.

**Properties:**
- Source class
- Target class
- Relationship type (one-to-one, one-to-many, many-to-many)
- Foreign key field

---

### **Logic Blocks:**

#### **Function Block**
Defines a function/operation.

**Properties:**
- Name
- Parameters
- Return type
- Body (code)

#### **Variable Block**
Defines a variable.

**Properties:**
- Name
- Type
- Initial value

#### **Condition Block**
Defines conditional logic.

**Properties:**
- Condition expression
- True branch
- False branch

#### **Loop Block**
Defines iteration logic.

**Properties:**
- Iteration variable
- Collection
- Body

---

## **Workflow**

### **1. Design Schema:**

1. Create Class blocks for each entity
2. Add fields to each class
3. Connect classes with Connector blocks
4. Define relationships

### **2. Build Queries:**

1. Create Query blocks
2. Add filter conditions
3. Set sorting and pagination
4. Connect to data sources

### **3. Generate Code:**

1. Select blocks to export
2. Choose output format (Swift, JSON, etc.)
3. Copy generated code
4. Paste into your project

---

## **Integration with BlazeDB**

### **Export Schema:**

BlazeStudio can export schemas directly to BlazeDB:

```swift
// Generated from BlazeStudio
struct User: BlazeRecord {
 var id: UUID
 var name: String
 var email: String
}

// Use in BlazeDB
let user = User(id: UUID(), name: "John", email: "john@example.com")
let id = try db.insert(user)
```

### **Export Queries:**

```swift
// Generated query from BlazeStudio
let users = try db.queryTyped(User.self)
.where(\.name, contains: "John")
.orderBy(\.email)
.all()
```

---

## **UI Components**

### **Canvas:**
- Main workspace
- Drag-and-drop interface
- Zoom and pan
- Grid alignment

### **Palette:**
- Block library
- Search and filter
- Categories

### **Properties Panel:**
- Block properties
- Field definitions
- Relationship settings

### **Preview Panel:**
- Generated code preview
- Schema visualization
- Query results

---

## **Keyboard Shortcuts**

- **⌘N** - New block
- **⌘D** - Duplicate block
- **⌘Delete** - Delete block
- **⌘C** - Copy block
- **⌘V** - Paste block
- **⌘Z** - Undo
- **⌘⇧Z** - Redo
- **⌘S** - Save project
- **⌘E** - Export code

---

## **File Format**

BlazeStudio projects are saved as JSON:

```json
{
 "version": "1.0",
 "blocks": [
 {
 "type": "class",
 "id": "block-1",
 "name": "User",
 "fields": [...],
 "position": {"x": 100, "y": 100}
 }
 ],
 "connections": [...]
}
```

---

## **Examples**

### **Example 1: User Schema**

1. Create Class block "User"
2. Add fields: id (UUID), name (String), email (String)
3. Create Class block "Post"
4. Add fields: id (UUID), title (String), userId (UUID)
5. Connect User to Post (one-to-many)
6. Export to Swift

### **Example 2: Query Builder**

1. Create Query block
2. Add filter: "status == 'active'"
3. Add sort: "createdAt DESC"
4. Add limit: 10
5. Connect to User class
6. Preview results

---

## **Tips & Tricks**

1. **Use Templates** - Start from templates for common patterns
2. **Group Blocks** - Organize related blocks
3. **Use Colors** - Color-code blocks by type
4. **Export Regularly** - Save your work frequently
5. **Version Control** - Commit project files to git

---

## **Limitations**

- **Visual Only** - No direct database connection
- **Code Generation** - Requires manual integration
- **Complex Queries** - May need manual code for advanced queries

---

## **Future Features**

- Direct BlazeDB connection
- Real-time schema sync
- Query execution
- Data visualization
- Collaboration features

---

**BlazeStudio makes database design visual and intuitive!**

