# BlazeDBVisualizer - Complete Documentation

**Comprehensive database monitoring and management tool.**

---

## **Overview**

BlazeDBVisualizer is a powerful macOS application for monitoring, managing, and visualizing BlazeDB databases. It provides real-time insights, data editing, query building, and performance monitoring.

---

## **Features**

### **Core Features:**
- **Real-time Dashboard** - Live database metrics
- **Data Viewer** - Browse and edit records
- **Query Builder** - Visual query construction
- **Schema Editor** - Manage database schema
- **Performance Monitor** - Track performance metrics
- **Security Dashboard** - View security policies
- **Sync Monitor** - Monitor sync operations
- **Telemetry Dashboard** - View telemetry data
- **Test Runner** - Run tests from UI
- **Charts & Visualization** - Visualize data

---

## **Getting Started**

### **1. Launch BlazeDBVisualizer**

- Open the app from Applications
- Or click the menu bar icon (flame icon)
- Main window opens automatically

### **2. Discover Databases**

BlazeDBVisualizer automatically scans for databases:
- `~/Library/Application Support/`
- `~/Documents/`
- `~/Desktop/`
- Custom paths (add in settings)

### **3. Unlock Database**

- Click on a database in the list
- Enter password
- Click "Unlock"
- Database opens in main window

---

## **Main Window Tabs**

### **1. Overview Tab**

**Database Summary:**
- Record count
- Database size
- Last modified
- Health status

**Quick Actions:**
- Create backup
- Run VACUUM
- Validate integrity
- Export data

---

### **2. Data Tab**

**Features:**
- Browse all records
- Search and filter
- Edit records inline
- Create new records
- Delete records
- Bulk operations

**Usage:**
1. Select "Data" tab
2. Records displayed in table
3. Click record to edit
4. Use "+" button to create new record
5. Use "Delete" to remove records

**Bulk Operations:**
- Select multiple records
- Click "Bulk Edit"
- Update fields in batch
- Apply changes

---

### **3. Queries Tab**

**Features:**
- Visual query builder
- Query console
- Saved queries
- Query history
- Performance metrics

**Visual Query Builder:**
1. Click "New Query"
2. Add filter conditions
3. Set sorting
4. Set pagination
5. Execute query
6. View results

**Query Console:**
- Type queries directly
- Use BlazeDB query syntax
- Save queries for reuse
- View execution time

---

### **4. Schema Tab**

**Features:**
- View schema structure
- Edit field definitions
- Create indexes
- Manage foreign keys
- Export schema

**Schema Editor:**
1. View all fields
2. Click field to edit
3. Change type, add constraints
4. Create indexes
5. Save changes

---

### **5. Performance Tab**

**Features:**
- Real-time performance metrics
- Operation throughput
- Query performance
- Storage statistics
- Performance charts

**Metrics:**
- Operations per second
- Average latency
- Query execution time
- Storage usage
- Cache hit rate

**Charts:**
- Throughput over time
- Latency distribution
- Query performance
- Storage growth

---

### **6. Security Tab**

**Features:**
- View security policies
- Manage RLS rules
- Test permissions
- Audit logs
- Security reports

**Permission Tester:**
1. Select user/role
2. Test operations
3. View allowed/denied
4. Debug policies

---

### **7. Sync Tab**

**Features:**
- View sync status
- Monitor sync operations
- Configure sync
- View sync history
- Performance metrics

**Sync Status:**
- Connected databases
- Sync direction
- Last sync time
- Pending operations
- Error logs

---

### **8. Telemetry Tab**

**Features:**
- View telemetry metrics
- Operation breakdown
- Error tracking
- Performance trends
- Export metrics

**Metrics:**
- Total operations
- Success rate
- Average latency
- Error count
- Operation types

---

## **Menu Bar Extra**

### **Quick Access:**
- Click flame icon in menu bar
- Quick database list
- Recent databases
- Quick actions

### **Actions:**
- Open database
- Create new database
- Scan for databases
- Settings
- Quit

---

## **Services**

### **EditingService:**
- Inline editing
- Bulk operations
- Undo/redo
- Audit logging

### **MonitoringService:**
- Real-time metrics
- Performance tracking
- Health monitoring

### **BackupRestoreService:**
- Create backups
- Restore from backup
- Backup scheduling

### **ExportService:**
- Export to JSON
- Export to CSV
- Export to SQL

### **PasswordVaultService:**
- Secure password storage
- Keychain integration
- Auto-unlock

---

## **Views**

### **MainWindowView:**
- Main application window
- Tab navigation
- Database selection

### **MonitoringDashboardView:**
- All monitoring tabs
- Real-time updates
- Interactive charts

### **DataViewerView:**
- Record browser
- Search and filter
- Pagination

### **EditableDataViewerView:**
- Inline editing
- Create/update/delete
- Bulk operations

### **QueryConsoleView:**
- Query input
- Results display
- Query history

### **VisualQueryBuilderView:**
- Visual query construction
- Drag-and-drop filters
- Preview results

### **SchemaEditorView:**
- Schema editing
- Field management
- Index creation

### **PerformanceChartsView:**
- Performance visualization
- Interactive charts
- Time series data

### **AccessControlView:**
- Security management
- Policy editor
- Permission tester

### **TelemetryDashboardView:**
- Telemetry visualization
- Metrics display
- Trend analysis

---

## **Keyboard Shortcuts**

- **⌘O** - Open database
- **⌘N** - New database
- **⌘S** - Save
- **⌘F** - Search
- **⌘E** - Export
- **⌘B** - Backup
- **⌘R** - Refresh
- **⌘T** - New tab
- **⌘W** - Close tab
- **⌘Q** - Quit

---

## **Settings**

### **General:**
- Auto-scan paths
- Default database location
- Theme (light/dark)
- Language

### **Performance:**
- Refresh interval
- Cache size
- Query timeout
- Batch size

### **Security:**
- Password storage
- Auto-lock timeout
- Audit logging
- Encryption settings

---

## **Use Cases**

### **1. Database Development:**
- Browse data during development
- Test queries
- Validate schema
- Monitor performance

### **2. Production Monitoring:**
- Monitor database health
- Track performance
- View telemetry
- Debug issues

### **3. Data Management:**
- Edit records
- Bulk operations
- Export data
- Import data

### **4. Security Auditing:**
- Review policies
- Test permissions
- View audit logs
- Security reports

---

## **Tips & Tricks**

1. **Use Search** - Quickly find records
2. **Save Queries** - Reuse common queries
3. **Monitor Performance** - Track metrics over time
4. **Use Bulk Operations** - Efficient data updates
5. **Export Regularly** - Backup your data

---

## **Limitations**

- **macOS Only** - Currently macOS only
- **Single Database** - One database at a time
- **Read-Only Mode** - Some operations require unlock

---

## **Future Features**

- iOS version
- Multi-database view
- Real-time collaboration
- Advanced visualizations
- Plugin system

---

**BlazeDBVisualizer is your complete database management solution!**

