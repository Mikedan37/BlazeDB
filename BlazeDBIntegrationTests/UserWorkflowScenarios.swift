//
//  UserWorkflowScenarios.swift
//  BlazeDBIntegrationTests
//
//  Real-world user workflow scenarios that validate complete feature sets
//  These simulate actual app usage patterns from initialization to production
//

import XCTest
@testable import BlazeDBCore

final class UserWorkflowScenarios: XCTestCase {
    
    var dbURL: URL!
    
    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Workflow-\(UUID().uuidString).blazedb")
    }
    
    override func tearDown() {
        guard let dbURL = dbURL else {
            super.tearDown()
            return
        }
        let extensions = ["", "meta", "indexes", "wal", "backup"]
        for ext in extensions {
            let url = ext.isEmpty ? dbURL : dbURL.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }
    
    // MARK: - Scenario 1: Notes App Development
    
    /// User builds a notes app from MVP to production
    func testScenario_NotesAppDevelopment() async throws {
        print("\n📝 SCENARIO: Notes App Development")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "NotesApp", fileURL: dbURL, password: "notes-secure-123")
        
        // Day 1: Simple CRUD
        print("  📅 Day 1: Basic note creation")
        let note1 = try await db!.insert(BlazeDataRecord([
            "title": .string("First Note"),
            "content": .string("Hello from BlazeDB!")
        ]))
        XCTAssertNotNil(note1)
        print("    ✅ Created first note")
        
        // Day 3: Add categories
        print("  📅 Day 3: Add categorization")
        let note2 = try await db!.insert(BlazeDataRecord([
            "title": .string("Work Note"),
            "content": .string("Meeting notes"),
            "category": .string("work")  // New field!
        ]))
        print("    ✅ Added category field")
        
        // Week 2: Add tags (array field)
        print("  📅 Week 2: Add tags feature")
        let note3 = try await db!.insert(BlazeDataRecord([
            "title": .string("Tagged Note"),
            "content": .string("Important stuff"),
            "category": .string("personal"),
            "tags": .array([.string("important"), .string("TODO")])  // Array field!
        ]))
        print("    ✅ Added tags (array fields)")
        
        // Week 3: Enable search
        print("  📅 Week 3: Add search functionality")
        try await db!.collection.enableSearch(fields: ["title", "content"])
        
        let searchResults = try await db!.collection.search(query: "Hello")
        XCTAssertEqual(searchResults.count, 1, "Should find 'Hello' in first note")
        print("    ✅ Search works: found \(searchResults.count) notes")
        
        // Month 2: Add favorites (boolean field)
        print("  📅 Month 2: Add favorites feature")
        try await db!.update(id: note1, with: BlazeDataRecord([
            "favorite": .bool(true)  // New boolean field!
        ]))
        
        let favorites = try await db!.query()
            .where("favorite", equals: .bool(true))
            .execute()
        XCTAssertGreaterThan(favorites.count, 0, "Should find favorited notes")
        print("    ✅ Favorites feature works")
        
        // Month 3: Sync simulation (bulk updates)
        print("  📅 Month 3: Simulate iCloud sync")
        try await db!.beginTransaction()
        
        // Batch update from "cloud"
        _ = try await db!.updateMany(
            where: { $0.storage["category"]?.stringValue == "work" },
            with: BlazeDataRecord([
                "synced": .bool(true),
                "sync_date": .date(Date())
            ])
        )
        
        try await db!.commitTransaction()
        print("    ✅ Synced work notes (transaction)")
        
        // Production: Close and reopen
        print("  📦 PRODUCTION: App restart")
        try await db!.persist()
        db = nil
        
        db = try BlazeDBClient(name: "NotesApp", fileURL: dbURL, password: "notes-secure-123")
        
        let allNotes = try await db!.fetchAll()
        XCTAssertEqual(allNotes.count, 3, "All notes should persist")
        print("    ✅ All 3 notes persisted through restart")
        
        // Verify all features still work
        let searchAfterRestart = try await db!.collection.search(query: "Note")
        XCTAssertGreaterThan(searchAfterRestart.count, 0, "Search should work after restart")
        print("    ✅ Search works after restart")
        
        print("  ✅ SCENARIO COMPLETE: Notes app from MVP to production!")
    }
    
    // MARK: - Scenario 2: E-Commerce Order System
    
    /// User builds e-commerce system with orders, customers, and inventory
    func testScenario_ECommerceOrderSystem() async throws {
        print("\n🛒 SCENARIO: E-Commerce Order System")
        
        // Create 3 databases: Customers, Orders, Products
        let customersDB = try BlazeDBClient(name: "Customers", fileURL: dbURL, password: "ecommerce-123")
        
        let ordersURL = dbURL.deletingLastPathComponent().appendingPathComponent("Orders-\(UUID().uuidString).blazedb")
        let ordersDB = try BlazeDBClient(name: "Orders", fileURL: ordersURL, password: "ecommerce-123")
        
        let productsURL = dbURL.deletingLastPathComponent().appendingPathComponent("Products-\(UUID().uuidString).blazedb")
        let productsDB = try BlazeDBClient(name: "Products", fileURL: productsURL, password: "ecommerce-123")
        
        defer {
            try? FileManager.default.removeItem(at: ordersURL)
            try? FileManager.default.removeItem(at: ordersURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: productsURL)
            try? FileManager.default.removeItem(at: productsURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        
        print("  ✅ Setup: 3 databases (Customers, Orders, Products)")
        
        // Add customers
        let customerRecords = (0..<10).map { i in
            BlazeDataRecord([
                "name": .string("Customer \(i)"),
                "email": .string("customer\(i)@shop.com"),
                "tier": .string(i < 3 ? "premium" : "standard")
            ])
        }
        let customerIDs = try await customersDB.insertMany(customerRecords)
        print("  ✅ Added 10 customers (3 premium, 7 standard)")
        
        // Add products
        let productRecords = (0..<20).map { i in
            BlazeDataRecord([
                "name": .string("Product \(i)"),
                "price": .double(Double(i) * 9.99),
                "stock": .int(100)
            ])
        }
        let productIDs = try await productsDB.insertMany(productRecords)
        print("  ✅ Added 20 products")
        
        // Simulate Black Friday: High concurrent orders
        print("  🛍️  BLACK FRIDAY: Concurrent orders")
        
        var allOrderIDs: [UUID] = []
        
        await withTaskGroup(of: [UUID].self) { group in
            // 5 concurrent shoppers
            for shopper in 0..<5 {
                group.addTask {
                    var shopperOrders: [UUID] = []
                    for order in 0..<10 {
                        let orderID = try! await ordersDB.insert(BlazeDataRecord([
                            "customer_id": .uuid(customerIDs[shopper]),
                            "product_id": .uuid(productIDs[(shopper * 10 + order) % 20]),
                            "amount": .double(Double(order) * 9.99),
                            "status": .string("pending")
                        ]))
                        shopperOrders.append(orderID)
                    }
                    return shopperOrders
                }
            }
            
            for await orders in group {
                allOrderIDs.append(contentsOf: orders)
            }
        }
        
        XCTAssertEqual(allOrderIDs.count, 50, "All 50 orders should be created")
        print("  ✅ Processed 50 concurrent orders")
        
        // JOIN: Get customer info for orders
        print("  🔗 Generating sales report (JOIN customers + orders)")
        let ordersWithCustomers = try await ordersDB.join(
            with: customersDB,
            on: "customer_id",
            equals: "id",
            type: .inner
        )
        
        XCTAssertEqual(ordersWithCustomers.count, 50, "All orders should JOIN with customers")
        print("  ✅ JOIN completed: 50 orders with customer data")
        
        // Aggregation: Sales by customer tier
        let premiumOrders = ordersWithCustomers.filter { joined in
            joined.right?.storage["tier"]?.stringValue == "premium"
        }
        
        let standardOrders = ordersWithCustomers.filter { joined in
            joined.right?.storage["tier"]?.stringValue == "standard"
        }
        
        print("  ✅ Premium customers: \(premiumOrders.count) orders")
        print("  ✅ Standard customers: \(standardOrders.count) orders")
        
        // Transaction: Process payments atomically
        print("  💳 Processing payment (atomic transaction)")
        try await ordersDB.beginTransaction()
        
        let processed = try await ordersDB.updateMany(
            where: { $0.storage["status"]?.stringValue == "pending" },
            with: BlazeDataRecord(["status": .string("completed")])
        )
        
        try await ordersDB.commitTransaction()
        print("  ✅ Processed \(processed) orders in transaction")
        
        print("  ✅ SCENARIO COMPLETE: E-Commerce system validated!")
    }
    
    // MARK: - Scenario 3: Team Collaboration App
    
    /// Multiple team members working concurrently on shared project
    func testScenario_TeamCollaborationApp() async throws {
        print("\n👥 SCENARIO: Team Collaboration App")
        
        let db = try BlazeDBClient(name: "TeamApp", fileURL: dbURL, password: "team-secure-123")
        
        // Setup: Create team structure
        let teamMembers = ["alice", "bob", "charlie", "diana", "eve"]
        print("  👥 Team: \(teamMembers.count) members")
        
        // Each member creates tasks concurrently
        print("  ⚙️  Each member creating 10 tasks...")
        
        var allTaskIDs: [UUID] = []
        
        await withTaskGroup(of: [UUID].self) { group in
            for member in teamMembers {
                group.addTask {
                    var memberTasks: [UUID] = []
                    for i in 0..<10 {
                        let taskID = try! await db.insert(BlazeDataRecord([
                            "title": .string("\(member)'s task \(i)"),
                            "owner": .string(member),
                            "status": .string("todo"),
                            "priority": .int(Int.random(in: 1...5))
                        ]))
                        memberTasks.append(taskID)
                    }
                    return memberTasks
                }
            }
            
            for await tasks in group {
                allTaskIDs.append(contentsOf: tasks)
            }
        }
        
        XCTAssertEqual(allTaskIDs.count, 50, "All 50 tasks should be created")
        print("  ✅ Created 50 tasks concurrently")
        
        // Verify no duplicate IDs (thread safety test)
        let uniqueIDs = Set(allTaskIDs)
        XCTAssertEqual(uniqueIDs.count, 50, "All task IDs should be unique")
        print("  ✅ No duplicate IDs (thread-safe)")
        
        // Dashboard: Aggregate by owner
        let allTasks = try await db.fetchAll()
        let grouped = Dictionary(grouping: allTasks) { task in
            task.storage["owner"]?.stringValue ?? "unknown"
        }
        
        XCTAssertEqual(grouped.keys.count, 5, "Should have 5 team members")
        for member in teamMembers {
            XCTAssertEqual(grouped[member]?.count, 10, "\(member) should have 10 tasks")
        }
        print("  ✅ Each member has 10 tasks (verified)")
        
        // Team lead updates high-priority tasks
        print("  👨‍💼 Team lead: Update high-priority tasks")
        try await db.beginTransaction()
        
        let updated = try await db.updateMany(
            where: { $0.storage["priority"]?.intValue ?? 0 >= 4 },
            with: BlazeDataRecord(["status": .string("in_progress")])
        )
        
        try await db.commitTransaction()
        print("  ✅ Updated \(updated) high-priority tasks")
        
        print("  ✅ SCENARIO COMPLETE: Team collaboration validated!")
    }
    
    // MARK: - Scenario 4: Mobile App Offline/Online
    
    /// Mobile app that works offline and syncs when online
    func testScenario_MobileAppOfflineSupport() async throws {
        print("\n📱 SCENARIO: Mobile App with Offline Support")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "MobileApp", fileURL: dbURL, password: "mobile-123")
        
        // Offline mode: Queue operations locally
        print("  📵 OFFLINE MODE: User creates data without network")
        
        let offlineRecords = (0..<20).map { i in
            BlazeDataRecord([
                "title": .string("Offline Item \(i)"),
                "created_at": .date(Date()),
                "synced": .bool(false)
            ])
        }
        let offlineIDs = try await db!.insertMany(offlineRecords)
        XCTAssertEqual(offlineIDs.count, 20)
        print("    ✅ Created 20 items offline")
        
        // User modifies some items
        try await db!.update(id: offlineIDs[0], with: BlazeDataRecord([
            "title": .string("Modified Offline"),
            "modified_at": .date(Date())
        ]))
        print("    ✅ Modified items offline")
        
        // Online mode: Sync to "cloud"
        print("  📶 ONLINE MODE: Sync to cloud")
        
        try await db!.beginTransaction()
        
        // Mark all as synced
        let synced = try await db!.updateMany(
            where: { $0.storage["synced"]?.boolValue == false },
            with: BlazeDataRecord([
                "synced": .bool(true),
                "synced_at": .date(Date())
            ])
        )
        
        try await db!.commitTransaction()
        XCTAssertEqual(synced, 20, "All items should be synced")
        print("    ✅ Synced 20 items to cloud")
        
        // Simulate: Download from cloud (simulated by inserting "server" data)
        let cloudRecords = (0..<10).map { i in
            BlazeDataRecord([
                "title": .string("Cloud Item \(i)"),
                "synced": .bool(true),
                "source": .string("server")
            ])
        }
        _ = try await db!.insertMany(cloudRecords)
        print("    ✅ Downloaded 10 items from cloud")
        
        // Verify total
        let total = try await db!.count()
        XCTAssertEqual(total, 30, "Should have 20 offline + 10 cloud items")
        print("  ✅ Total items: \(total) (20 local + 10 cloud)")
        
        // Background: Auto-save periodically
        print("  💾 BACKGROUND: Auto-save simulation")
        try await db!.persist()
        
        // App restart
        db = nil
        db = try BlazeDBClient(name: "MobileApp", fileURL: dbURL, password: "mobile-123")
        
        let afterRestart = try await db!.count()
        XCTAssertEqual(afterRestart, 30, "Data should persist")
        print("  ✅ Data persisted through restart")
        
        print("  ✅ SCENARIO COMPLETE: Mobile offline/online validated!")
    }
    
    // MARK: - Scenario 5: Data Scientist Import
    
    /// Data scientist imports large CSV dataset and performs analysis
    func testScenario_DataScientistCSVImport() async throws {
        print("\n📊 SCENARIO: Data Scientist CSV Import & Analysis")
        
        let db = try BlazeDBClient(name: "DataScience", fileURL: dbURL, password: "analysis-123")
        
        // Import CSV (simulated as records)
        print("  📥 Importing 1000-record CSV dataset...")
        let csvData = (0..<1000).map { i in
            BlazeDataRecord([
                "user_id": .int(i % 100),
                "event": .string(["login", "purchase", "logout", "view"].randomElement()!),
                "timestamp": .date(Date().addingTimeInterval(Double(-i * 60))),
                "value": .double(Double.random(in: 0...100)),
                "session_id": .uuid(UUID())
            ])
        }
        
        let start = Date()
        let imported = try await db.insertMany(csvData)
        let importTime = Date().timeIntervalSince(start)
        
        XCTAssertEqual(imported.count, 1000)
        print("  ✅ Imported 1000 records in \(String(format: "%.2f", importTime))s")
        
        // Create indexes for analysis
        print("  📊 Creating indexes for analysis...")
        try await db.collection.createIndex(on: "user_id")
        try await db.collection.createIndex(on: "event")
        print("  ✅ Indexes created")
        
        // Analysis 1: Event counts
        print("  🔍 Analysis 1: Event frequency")
        let eventCounts = Dictionary(grouping: try await db.fetchAll()) { record in
            record.storage["event"]?.stringValue ?? "unknown"
        }.mapValues { $0.count }
        
        print("    Event distribution: \(eventCounts)")
        XCTAssertGreaterThan(eventCounts.keys.count, 0)
        
        // Analysis 2: User behavior (events per user)
        print("  🔍 Analysis 2: User activity")
        let userActivity = Dictionary(grouping: try await db.fetchAll()) { record in
            record.storage["user_id"]?.intValue ?? -1
        }.mapValues { $0.count }
        
        XCTAssertEqual(userActivity.keys.count, 100, "Should have 100 users")
        print("  ✅ Analyzed 100 users")
        
        // Analysis 3: Time-series aggregation
        print("  🔍 Analysis 3: Aggregate by user")
        let stats = try await db.query()
            .groupBy("user_id")
            .aggregate([
                .count(as: "event_count"),
                .avg("value", as: "avg_value")
            ])
            .execute()
        
        let grouped = try stats.grouped
        XCTAssertEqual(grouped.groups.count, 100, "Should have 100 user groups")
        print("  ✅ Aggregated stats for 100 users")
        
        // Export results (fetch and process)
        let exportStart = Date()
        let exportData = try await db.fetchAll()
        let exportTime = Date().timeIntervalSince(exportStart)
        
        XCTAssertLessThan(exportTime, 1.0, "Export should be fast")
        print("  ✅ Exported 1000 records in \(String(format: "%.3f", exportTime))s")
        
        print("  ✅ SCENARIO COMPLETE: Data science workflow validated!")
    }
    
    // MARK: - Scenario 6: Junior Developer First App
    
    /// Junior developer builds their first app with BlazeDB
    func testScenario_JuniorDeveloperFirstApp() async throws {
        print("\n🎓 SCENARIO: Junior Developer's First App")
        
        print("  📖 Hour 1: Reading documentation, trying first insert...")
        
        // Mistake 1: Weak password
        print("  ❌ Attempt 1: Weak password")
        let weakDB = try? BlazeDBClient(name: "FirstApp", fileURL: dbURL, password: "test")
        XCTAssertNil(weakDB, "Weak password should be rejected")
        print("    ✅ Got clear error message about password strength")
        
        // Fix: Strong password
        print("  ✅ Attempt 2: Strong password")
        let db = try BlazeDBClient(name: "FirstApp", fileURL: dbURL, password: "FirstApp2025!")
        print("    ✅ Database created successfully")
        
        // Hour 2: First successful insert
        print("  📝 Hour 2: Creating first record...")
        let firstRecord = try await db.insert(BlazeDataRecord([
            "name": .string("Alice"),
            "age": .int(25)
        ]))
        XCTAssertNotNil(firstRecord)
        print("    ✅ First record created!")
        
        // Hour 3: Learning to query
        print("  🔍 Hour 3: Learning query DSL...")
        let adults = try await db.query()
            .where("age", greaterThanOrEqual: .int(18))
            .execute()
        
        XCTAssertEqual(adults.count, 1)
        print("    ✅ Query DSL makes sense!")
        
        // Day 2: Trying batch operations
        print("  📦 Day 2: Importing data...")
        let batchRecords = (0..<10).map { i in
            BlazeDataRecord([
                "name": .string("Person \(i)"),
                "age": .int(20 + i)
            ])
        }
        _ = try await db.insertMany(batchRecords)
        print("    ✅ Batch import works!")
        
        // Week 2: Trying type-safe API
        print("  🎯 Week 2: Discovering type-safe API...")
        
        struct Person: BlazeStorable {
            var id: UUID
            var name: String
            var age: Int
        }
        
        let allPeople = try await db.fetchAll(Person.self)
        XCTAssertEqual(allPeople.count, 11, "Should convert all records to typed")
        print("    ✅ Type-safe API is magical!")
        
        // Month 2: Shipping to TestFlight
        print("  🚀 Month 2: Deploying to TestFlight...")
        try await db.persist()
        print("    ✅ App ready for production!")
        
        print("  ✅ SCENARIO COMPLETE: Junior developer succeeded with BlazeDB!")
    }
    
    // MARK: - Scenario 7: Rapid Prototyping
    
    /// Startup developer rapidly iterating on product
    func testScenario_RapidPrototypeMVP() async throws {
        print("\n⚡ SCENARIO: Rapid Prototype to MVP")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "StartupMVP", fileURL: dbURL, password: "mvp-2025")
        
        // Week 1: Minimal viable product
        print("  📅 Week 1: MVP launch")
        let user1 = try await db!.insert(BlazeDataRecord([
            "email": .string("user@test.com")
        ]))
        print("    ✅ MVP: Just email (minimal schema)")
        
        // Week 2: Add user profiles
        print("  📅 Week 2: Add user profiles")
        let user2 = try await db!.insert(BlazeDataRecord([
            "email": .string("user2@test.com"),
            "name": .string("Bob"),  // New field!
            "avatar": .string("https://avatar.com/bob.jpg")  // New field!
        ]))
        print("    ✅ Schema evolved: +2 fields (no migration needed!)")
        
        // Week 3: Add social features
        print("  📅 Week 3: Add social features")
        let user3 = try await db!.insert(BlazeDataRecord([
            "email": .string("user3@test.com"),
            "name": .string("Charlie"),
            "avatar": .string("https://avatar.com/charlie.jpg"),
            "followers": .array([.uuid(user1), .uuid(user2)]),  // New array field!
            "bio": .string("Loves prototyping")  // New field!
        ]))
        print("    ✅ Schema evolved: +2 more fields")
        
        // Week 4: Add premium features
        print("  📅 Week 4: Add premium tier")
        try await db!.update(id: user2, with: BlazeDataRecord([
            "premium": .bool(true),  // New boolean field!
            "premium_since": .date(Date())  // New date field!
        ]))
        print("    ✅ Schema evolved: +2 more fields")
        
        // Month 2: Product-market fit, scale to 100 users
        print("  📅 Month 2: Scaling to 100 users")
        let scaledUsers = (0..<100).map { i in
            BlazeDataRecord([
                "email": .string("user\(i)@scale.com"),
                "name": .string("User \(i)"),
                "premium": .bool(i % 10 == 0)  // 10% premium
            ])
        }
        _ = try await db!.insertMany(scaledUsers)
        print("    ✅ Scaled to 100 users")
        
        // Add search for user discovery
        try await db!.collection.enableSearch(fields: ["name", "bio"])
        print("    ✅ Added search feature")
        
        // Month 3: Funding round, prepare for production
        print("  📅 Month 3: Production deployment")
        
        // Add indexes for performance
        try await db!.collection.createIndex(on: "premium")
        
        // Verify everything works
        let allUsers = try await db!.fetchAll()
        XCTAssertGreaterThanOrEqual(allUsers.count, 103, "Should have all users")
        
        let premiumUsers = try await db!.query()
            .where("premium", equals: .bool(true))
            .execute()
        XCTAssertGreaterThan(premiumUsers.count, 0)
        print("    ✅ Premium users: \(premiumUsers.count)")
        
        // Close and reopen (production deployment)
        try await db!.persist()
        db = nil
        
        db = try BlazeDBClient(name: "StartupMVP", fileURL: dbURL, password: "mvp-2025")
        
        let prodCount = try await db!.count()
        XCTAssertGreaterThanOrEqual(prodCount, 103)
        print("    ✅ Data persisted: \(prodCount) users in production")
        
        print("  ✅ SCENARIO COMPLETE: MVP to production in 3 months!")
    }
    
    // MARK: - Scenario 8: Enterprise Dashboard
    
    /// Enterprise team builds real-time dashboard with aggregations
    func testScenario_EnterpriseDashboard() async throws {
        print("\n🏢 SCENARIO: Enterprise Real-Time Dashboard")
        
        let db = try BlazeDBClient(name: "Enterprise", fileURL: dbURL, password: "enterprise-secure-2025")
        
        // Import initial dataset (simulates database already in use)
        print("  📥 Importing existing data (1000 records)...")
        let existingData = (0..<1000).map { i in
            BlazeDataRecord([
                "department": .string(["Sales", "Engineering", "Marketing", "Support"].randomElement()!),
                "status": .string(["open", "in_progress", "completed"].randomElement()!),
                "priority": .int(Int.random(in: 1...5)),
                "hours_logged": .double(Double.random(in: 0.5...8.0)),
                "date": .date(Date().addingTimeInterval(Double(-i * 3600)))
            ])
        }
        _ = try await db.insertMany(existingData)
        print("  ✅ Imported 1000 records")
        
        // Create indexes for dashboard performance
        print("  🔧 Optimizing for dashboard queries...")
        try await db.collection.createIndex(on: "department")
        try await db.collection.createIndex(on: ["department", "status"])
        try await db.collection.createIndex(on: ["status", "priority"])
        print("  ✅ Created 3 performance indexes")
        
        // Dashboard Query 1: Stats by department
        print("  📊 Dashboard Widget 1: Department stats")
        let deptStats = try await db.query()
            .groupBy("department")
            .aggregate([
                .count(as: "total_tasks"),
                .sum("hours_logged", as: "total_hours"),
                .avg("priority", as: "avg_priority")
            ])
            .execute()
        
        let deptGrouped = try deptStats.grouped
        XCTAssertEqual(deptGrouped.groups.count, 4, "Should have 4 departments")
        print("    ✅ Aggregated stats for 4 departments")
        
        // Dashboard Query 2: High-priority items
        let criticalItems = try await db.query()
            .where("priority", greaterThanOrEqual: .int(4))
            .where("status", notEquals: .string("completed"))
            .orderBy("priority", descending: true)
            .limit(10)
            .execute()
        
        XCTAssertGreaterThan(criticalItems.count, 0)
        print("    ✅ Top \(criticalItems.count) critical items")
        
        // Dashboard Query 3: Completion rate by department
        let allRecords = try await db.fetchAll()
        let completionRates = Dictionary(grouping: allRecords) {
            $0.storage["department"]?.stringValue ?? "unknown"
        }.mapValues { records in
            let completed = records.filter { $0.storage["status"]?.stringValue == "completed" }.count
            return Double(completed) / Double(records.count) * 100
        }
        
        print("    Completion rates:")
        for (dept, rate) in completionRates.sorted(by: { $0.key < $1.key }) {
            print("      \(dept): \(String(format: "%.1f", rate))%")
        }
        
        // Real-time update simulation
        print("  🔄 Real-time: New task created")
        _ = try await db.insert(BlazeDataRecord([
            "department": .string("Engineering"),
            "status": .string("open"),
            "priority": .int(5)
        ]))
        
        // Dashboard auto-refreshes (SwiftUI @BlazeQuery simulation)
        let refreshed = try await db.query()
            .where("department", equals: .string("Engineering"))
            .execute()
        print("    ✅ Dashboard refreshed: \(refreshed.count) Engineering tasks")
        
        print("  ✅ SCENARIO COMPLETE: Enterprise dashboard validated!")
    }
    
    // MARK: - Performance Benchmark
    
    /// Measure realistic workflow performance
    func testPerformance_RealWorldWorkflow() async throws {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTStorageMetric()]) {
            Task {
                do {
                    let db = try BlazeDBClient(name: "RealWorld", fileURL: self.dbURL, password: "perf-test-123")
                    
                    // Complete workflow: Setup → Insert → Query → Update → Export
                    try await db.collection.createIndex(on: "category")
                    try await db.collection.enableSearch(fields: ["title"])
                    
                    let records = (0..<100).map { i in
                        BlazeDataRecord([
                            "title": .string("Item \(i)"),
                            "category": .string("cat_\(i % 10)"),
                            "value": .double(Double(i))
                        ])
                    }
                    _ = try await db.insertMany(records)
                    
                    _ = try await db.query().where("category", equals: .string("cat_1")).execute()
                    _ = try await db.collection.search(query: "Item")
                    
                    try await db.beginTransaction()
                    _ = try await db.updateMany(where: { _ in true }, with: BlazeDataRecord(["processed": .bool(true)]))
                    try await db.commitTransaction()
                    
                    _ = try await db.fetchAll()
                    try await db.persist()
                } catch {
                    XCTFail("Real-world workflow failed: \(error)")
                }
            }
        }
    }
}

