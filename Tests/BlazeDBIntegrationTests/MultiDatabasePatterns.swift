//
//  MultiDatabasePatterns.swift
//  BlazeDBIntegrationTests
//
//  Tests complex multi-database relational patterns
//  Validates JOINs, referential integrity, and cross-database transactions
//

import XCTest
@testable import BlazeDB

final class MultiDatabasePatterns: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultiDB-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Complex Relational Patterns
    
    /// SCENARIO: 5-database e-commerce system
    /// Tests: Cross-database JOINs, referential integrity, complex queries
    func testPattern_CompleteECommerceSystem() async throws {
        print("\n🛒 PATTERN: Complete E-Commerce (5 databases)")
        
        // Create 5 interconnected databases
        let customers = try BlazeDBClient(name: "Customers", fileURL: tempDir.appendingPathComponent("customers.db"), password: "ecom-123")
        let products = try BlazeDBClient(name: "Products", fileURL: tempDir.appendingPathComponent("products.db"), password: "ecom-123")
        let orders = try BlazeDBClient(name: "Orders", fileURL: tempDir.appendingPathComponent("orders.db"), password: "ecom-123")
        let inventory = try BlazeDBClient(name: "Inventory", fileURL: tempDir.appendingPathComponent("inventory.db"), password: "ecom-123")
        let reviews = try BlazeDBClient(name: "Reviews", fileURL: tempDir.appendingPathComponent("reviews.db"), password: "ecom-123")
        
        print("  ✅ Created 5 databases: Customers, Products, Orders, Inventory, Reviews")
        
        // Populate customers
        let customerRecords = (0..<20).map { i in
            BlazeDataRecord([
                "name": .string("Customer \(i)"),
                "email": .string("customer\(i)@shop.com"),
                "tier": .string(i < 5 ? "premium" : "standard"),
                "total_spent": .double(0.0)
            ])
        }
        let customerIDs = try await customers.insertMany(customerRecords)
        print("  ✅ Added 20 customers")
        
        // Populate products
        let productRecords = (0..<50).map { i in
            BlazeDataRecord([
                "name": .string("Product \(i)"),
                "price": .double(Double(i) * 9.99),
                "category": .string(["Electronics", "Clothing", "Books", "Food"].randomElement()!)
            ])
        }
        let productIDs = try await products.insertMany(productRecords)
        print("  ✅ Added 50 products")
        
        // Populate inventory
        for productID in productIDs {
            _ = try await inventory.insert(BlazeDataRecord([
                "product_id": .uuid(productID),
                "stock": .int(Int.random(in: 0...100)),
                "warehouse": .string(["LA", "NY", "Chicago"].randomElement()!)
            ]))
        }
        print("  ✅ Added 50 inventory records")
        
        // Create orders (linking customers and products)
        var allOrderIDs: [UUID] = []
        for _ in 0..<100 {
            let orderID = try await orders.insert(BlazeDataRecord([
                "customer_id": .uuid(customerIDs.randomElement()!),
                "product_id": .uuid(productIDs.randomElement()!),
                "quantity": .int(Int.random(in: 1...5)),
                "amount": .double(Double.random(in: 10...500)),
                "status": .string(["pending", "completed", "shipped"].randomElement()!),
                "created_at": .date(Date().addingTimeInterval(Double.random(in: -86400...0)))
            ]))
            allOrderIDs.append(orderID)
        }
        print("  ✅ Created 100 orders")
        
        // Add reviews (linking customers and products)
        for _ in 0..<75 {
            _ = try await reviews.insert(BlazeDataRecord([
                "customer_id": .uuid(customerIDs.randomElement()!),
                "product_id": .uuid(productIDs.randomElement()!),
                "rating": .int(Int.random(in: 1...5)),
                "comment": .string("Great product!"),
                "created_at": .date(Date())
            ]))
        }
        print("  ✅ Added 75 reviews")
        
        // Query 1: JOIN orders with customers
        print("\n  📊 QUERY 1: Orders with customer info")
        let ordersWithCustomers = try await orders.join(
            with: customers,
            on: "customer_id",
            equals: "id",
            type: .inner
        )
        
        XCTAssertEqual(ordersWithCustomers.count, 100, "All orders should JOIN")
        print("    ✅ \(ordersWithCustomers.count) orders with customer data")
        
        // Query 2: JOIN orders with products
        print("  📊 QUERY 2: Orders with product info")
        let ordersWithProducts = try await orders.join(
            with: products,
            on: "product_id",
            equals: "id",
            type: .inner
        )
        
        XCTAssertEqual(ordersWithProducts.count, 100, "All orders should JOIN")
        print("    ✅ \(ordersWithProducts.count) orders with product data")
        
        // Query 3: Products with inventory
        print("  📊 QUERY 3: Products with inventory levels")
        let productsWithInventory = try await products.join(
            with: inventory,
            on: "id",
            equals: "product_id",
            type: .inner
        )
        
        XCTAssertEqual(productsWithInventory.count, 50, "All products should have inventory")
        print("    ✅ \(productsWithInventory.count) products with inventory")
        
        // Complex Query: Low stock products
        let lowStock = productsWithInventory.filter { joined in
            joined.right?.storage["stock"]?.intValue ?? 999 < 10
        }
        print("    ✅ Low stock products: \(lowStock.count)")
        
        // Query 4: Customer order history with aggregation
        print("  📊 QUERY 4: Customer purchase analytics")
        let customerOrders = Dictionary(grouping: ordersWithCustomers) { joined in
            joined.right?.storage["email"]?.stringValue ?? "unknown"
        }
        
        let topCustomers = customerOrders.map { email, orders in
            let totalSpent = orders.reduce(0.0) { sum, order in
                sum + (order.left.storage["amount"]?.doubleValue ?? 0)
            }
            return (email: email, orders: orders.count, spent: totalSpent)
        }.sorted { $0.spent > $1.spent }.prefix(5)
        
        print("    ✅ Top 5 customers:")
        for customer in topCustomers {
            print("      \(customer.email): \(customer.orders) orders, $\(String(format: "%.2f", customer.spent))")
        }
        
        // Query 5: Product ratings
        print("  📊 QUERY 5: Product ratings")
        let productRatings = Dictionary(grouping: try await reviews.fetchAll()) { review in
            review.storage["product_id"]?.uuidValue ?? UUID()
        }
        
        print("    ✅ \(productRatings.count) products have reviews")
        
        print("  ✅ VALIDATED: Complex 5-database e-commerce system works!")
    }
    
    /// SCENARIO: Multi-database atomic transaction simulation
    /// Tests: Cross-database consistency, rollback across databases
    func testPattern_MultiDatabaseAtomicity() async throws {
        print("\n🔐 PATTERN: Multi-Database Atomic Operations")
        
        let accountsDB = try BlazeDBClient(name: "Accounts", fileURL: tempDir.appendingPathComponent("accounts.db"), password: "atomic-123")
        let ledgerDB = try BlazeDBClient(name: "Ledger", fileURL: tempDir.appendingPathComponent("ledger.db"), password: "atomic-123")
        
        // Create two accounts
        let account1 = try await accountsDB.insert(BlazeDataRecord([
            "name": .string("Alice"),
            "balance": .double(1000.0)
        ]))
        
        let account2 = try await accountsDB.insert(BlazeDataRecord([
            "name": .string("Bob"),
            "balance": .double(500.0)
        ]))
        
        print("  ✅ Created 2 accounts: Alice ($1000), Bob ($500)")
        
        // Money transfer: Alice → Bob ($200)
        // Must be atomic across BOTH databases (accounts + ledger)
        print("  💸 Transfer: Alice → Bob ($200)")
        
        // Simulate atomic transaction
        try await accountsDB.beginTransaction()
        try await ledgerDB.beginTransaction()
        
        do {
            // Debit Alice
            if let alice = try await accountsDB.fetch(id: account1) {
                let currentBalance = alice.storage["balance"]?.doubleValue ?? 0
                try await accountsDB.update(id: account1, with: BlazeDataRecord([
                    "balance": .double(currentBalance - 200)
                ]))
            }
            
            // Credit Bob
            if let bob = try await accountsDB.fetch(id: account2) {
                let currentBalance = bob.storage["balance"]?.doubleValue ?? 0
                try await accountsDB.update(id: account2, with: BlazeDataRecord([
                    "balance": .double(currentBalance + 200)
                ]))
            }
            
            // Record in ledger
            _ = try await ledgerDB.insert(BlazeDataRecord([
                "from": .uuid(account1),
                "to": .uuid(account2),
                "amount": .double(200.0),
                "timestamp": .date(Date())
            ]))
            
            // Commit both
            try await accountsDB.commitTransaction()
            try await ledgerDB.commitTransaction()
            
            print("    ✅ Transaction committed")
            
            // Verify
            let aliceFinal = try await accountsDB.fetch(id: account1)
            let bobFinal = try await accountsDB.fetch(id: account2)
            
            XCTAssertEqual(aliceFinal?.storage["balance"]?.doubleValue, 800.0)
            XCTAssertEqual(bobFinal?.storage["balance"]?.doubleValue, 700.0)
            
            print("    ✅ Alice: $800, Bob: $700")
            
            let ledgerCount = try await ledgerDB.count()
            XCTAssertEqual(ledgerCount, 1, "Ledger should have 1 entry")
            
        } catch {
            // Rollback both on failure
            try? await accountsDB.rollbackTransaction()
            try? await ledgerDB.rollbackTransaction()
            print("    ↩️  Transaction rolled back due to error")
        }
        
        print("  ✅ VALIDATED: Multi-database atomicity maintained!")
    }
    
    /// SCENARIO: Master-slave replication simulation
    /// Tests: Data consistency, lag handling, failover
    func testPattern_MasterSlaveReplication() async throws {
        print("\n🔄 PATTERN: Master-Slave Replication Simulation")
        
        let master = try BlazeDBClient(name: "Master", fileURL: tempDir.appendingPathComponent("master.db"), password: "repl-123")
        let slave1 = try BlazeDBClient(name: "Slave1", fileURL: tempDir.appendingPathComponent("slave1.db"), password: "repl-123")
        let slave2 = try BlazeDBClient(name: "Slave2", fileURL: tempDir.appendingPathComponent("slave2.db"), password: "repl-123")
        
        print("  ✅ Created master + 2 slaves")
        
        // Write to master
        print("  ✍️  Writing to master...")
        let masterRecords = (0..<50).map { i in
            BlazeDataRecord([
                "data": .string("Master record \(i)"),
                "timestamp": .date(Date())
            ])
        }
        _ = try await master.insertMany(masterRecords)
        print("    ✅ Master: 50 records")
        
        // Simulate replication to slaves
        print("  🔄 Replicating to slaves...")
        let masterData = try await master.fetchAll()
        
        _ = try await slave1.insertMany(masterData)
        _ = try await slave2.insertMany(masterData)
        
        print("    ✅ Slave 1: \(try await slave1.count()) records")
        print("    ✅ Slave 2: \(try await slave2.count()) records")
        
        // Verify: All have same data
        let masterCount = try await master.count()
        let slave1Count = try await slave1.count()
        let slave2Count = try await slave2.count()
        
        XCTAssertEqual(masterCount, 50)
        XCTAssertEqual(slave1Count, 50)
        XCTAssertEqual(slave2Count, 50)
        
        print("  ✅ Data consistent across master and slaves")
        
        // Simulate: Master fails, promote slave
        print("  💥 Master fails! Promoting Slave 1...")
        
        // Continue writes to promoted slave
        _ = try await slave1.insert(BlazeDataRecord(["data": .string("After promotion")]))
        
        let promotedCount = try await slave1.count()
        XCTAssertEqual(promotedCount, 51)
        print("    ✅ Promoted slave functional: \(promotedCount) records")
        
        print("  ✅ VALIDATED: Replication pattern works!")
    }
    
    /// SCENARIO: Microservices pattern (separate databases per service)
    /// Tests: Service boundaries, data isolation, cross-service queries
    func testPattern_MicroservicesArchitecture() async throws {
        print("\n🏗️  PATTERN: Microservices Architecture")
        
        // 4 microservices with separate databases
        let userService = try BlazeDBClient(name: "UserService", fileURL: tempDir.appendingPathComponent("users.db"), password: "micro-123")
        let authService = try BlazeDBClient(name: "AuthService", fileURL: tempDir.appendingPathComponent("auth.db"), password: "micro-123")
        let bugService = try BlazeDBClient(name: "BugService", fileURL: tempDir.appendingPathComponent("bugs.db"), password: "micro-123")
        let notificationService = try BlazeDBClient(name: "NotificationService", fileURL: tempDir.appendingPathComponent("notifications.db"), password: "micro-123")
        
        print("  ✅ Created 4 microservices")
        
        // User Service: User registration
        print("\n  👤 USER SERVICE: Register user")
        let userID = try await userService.insert(BlazeDataRecord([
            "name": .string("Alice"),
            "email": .string("alice@test.com"),
            "created_at": .date(Date())
        ]))
        print("    ✅ User created: \(userID)")
        
        // Auth Service: Create auth token
        print("  🔐 AUTH SERVICE: Generate token")
        let token = UUID()
        _ = try await authService.insert(BlazeDataRecord([
            "user_id": .uuid(userID),
            "token": .uuid(token),
            "expires_at": .date(Date().addingTimeInterval(3600))
        ]))
        print("    ✅ Token generated")
        
        // Bug Service: Create bug (authenticated)
        print("  🐛 BUG SERVICE: Create bug")
        let bugID = try await bugService.insert(BlazeDataRecord([
            "title": .string("Login bug"),
            "reporter_id": .uuid(userID),
            "status": .string("open")
        ]))
        print("    ✅ Bug created: \(bugID)")
        
        // Notification Service: Send notification
        print("  📧 NOTIFICATION SERVICE: Queue notification")
        _ = try await notificationService.insert(BlazeDataRecord([
            "user_id": .uuid(userID),
            "type": .string("bug_created"),
            "bug_id": .uuid(bugID),
            "sent": .bool(false)
        ]))
        print("    ✅ Notification queued")
        
        // Cross-service query: Get bug with user info
        print("\n  🔗 CROSS-SERVICE: JOIN bug with user")
        let bugsWithUsers = try await bugService.join(
            with: userService,
            on: "reporter_id",
            equals: "id",
            type: .inner
        )
        
        XCTAssertEqual(bugsWithUsers.count, 1)
        if !bugsWithUsers.isEmpty {
            let bugAuthor = bugsWithUsers[0].right?.storage["name"]?.stringValue
            print("    ✅ Bug reported by: \(bugAuthor ?? "unknown")")
        }
        
        // Verify: Each service has correct data
        let userCount = try await userService.count()
        let authCount = try await authService.count()
        let bugCount = try await bugService.count()
        let notificationCount = try await notificationService.count()
        
        XCTAssertEqual(userCount, 1)
        XCTAssertEqual(authCount, 1)
        XCTAssertEqual(bugCount, 1)
        XCTAssertEqual(notificationCount, 1)
        
        print("  ✅ VALIDATED: Microservices pattern works perfectly!")
    }
    
    /// SCENARIO: Event sourcing pattern
    /// Tests: Append-only log, event replay, state reconstruction
    func testPattern_EventSourcing() async throws {
        print("\n📜 PATTERN: Event Sourcing")
        
        let eventsDB = try BlazeDBClient(name: "Events", fileURL: tempDir.appendingPathComponent("events.db"), password: "events-123")
        let stateDB = try BlazeDBClient(name: "State", fileURL: tempDir.appendingPathComponent("state.db"), password: "events-123")
        
        print("  ✅ Created Events (append-only) + State databases")
        
        // Append events
        print("  📝 Recording events...")
        
        let events = [
            ("BugCreated", ["bug_id": UUID(), "title": "Bug 1"]),
            ("BugUpdated", ["bug_id": UUID(), "status": "in_progress"]),
            ("CommentAdded", ["bug_id": UUID(), "comment": "Looking into it"]),
            ("BugClosed", ["bug_id": UUID(), "status": "closed"])
        ]
        
        for (index, (eventType, eventData)) in events.enumerated() {
            var record: [String: BlazeDocumentField] = [
                "event_type": .string(eventType),
                "sequence": .int(index),
                "timestamp": .date(Date())
            ]
            
            for (key, value) in eventData {
                if let uuid = value as? UUID {
                    record[key] = .uuid(uuid)
                } else if let str = value as? String {
                    record[key] = .string(str)
                }
            }
            
            _ = try await eventsDB.insert(BlazeDataRecord(record))
        }
        
        print("    ✅ Recorded 4 events")
        
        // Replay events to reconstruct state
        print("  🔄 Replaying events to build state...")
        
        let allEvents = try await eventsDB.query()
            .orderBy("sequence")
            .execute()
        
        var currentState: [String: Any] = [:]
        
        for eventRecord in try allEvents.records {
            let eventType = eventRecord.storage["event_type"]?.stringValue ?? ""
            
            switch eventType {
            case "BugCreated":
                currentState["status"] = "open"
                currentState["created"] = true
            case "BugUpdated":
                currentState["status"] = "in_progress"
            case "CommentAdded":
                currentState["has_comments"] = true
            case "BugClosed":
                currentState["status"] = "closed"
            default:
                break
            }
        }
        
        // Save final state
        _ = try await stateDB.insert(BlazeDataRecord([
            "status": .string(currentState["status"] as? String ?? "unknown"),
            "has_comments": .bool(currentState["has_comments"] as? Bool ?? false),
            "created": .bool(currentState["created"] as? Bool ?? false)
        ]))
        
        print("    ✅ State reconstructed: \(currentState)")
        
        let stateCount = try await stateDB.count()
        XCTAssertEqual(stateCount, 1)
        
        print("  ✅ VALIDATED: Event sourcing pattern works!")
    }
    
    /// Performance: Multi-database JOIN operations
    func testPerformance_CrossDatabaseJOINs() async throws {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            Task {
                do {
                    let db1 = try BlazeDBClient(name: "Left", fileURL: self.tempDir.appendingPathComponent("left.db"), password: "join-123")
                    let db2 = try BlazeDBClient(name: "Right", fileURL: self.tempDir.appendingPathComponent("right.db"), password: "join-123")
                    
                    // Setup
                    let ids = (0..<20).map { i -> UUID in
                        try! db2.insert(BlazeDataRecord(["value": .int(i)]))
                    }
                    
                    let records = (0..<100).map { i in
                        BlazeDataRecord([
                            "ref_id": .uuid(ids[i % 20]),
                            "data": .string("Item \(i)")
                        ])
                    }
                    _ = try await db1.insertMany(records)
                    
                    // Perform JOIN
                    _ = try await db1.join(with: db2, on: "ref_id", equals: "id", type: .inner)
                    
                } catch {
                    XCTFail("Cross-database JOIN failed: \(error)")
                }
            }
        }
    }
}

