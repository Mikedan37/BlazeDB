//
//  ComputedFieldsTests.swift
//  BlazeDBTests
//
//  Tests for computed field expressions
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class ComputedFieldsTests: XCTestCase {
    var db: BlazeDBClient!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("test.blazedb")
        db = try! BlazeDBClient(name: "TestDB", fileURL: dbURL, password: "ComputedFieldsTest123!")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testMultiplyFields() throws {
        // Insert test data
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "price": .double(10.0),
            "quantity": .int(5)
        ])
        _ = try db.insert(record)
        
        // Compute total = price * quantity
        let results = try db.query()
            .compute("total", multiply: "price", by: "quantity")
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].storage["total"]?.doubleValue, 50.0)
    }
    
    func testAddFields() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "a": .int(10),
            "b": .int(20)
        ])
        _ = try db.insert(record)
        
        let results = try db.query()
            .compute("sum", expression: .add(.field("a"), .field("b")))
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records[0].storage["sum"]?.intValue, 30)
    }
    
    func testSubtractFields() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "revenue": .double(100.0),
            "cost": .double(30.0)
        ])
        _ = try db.insert(record)
        
        let results = try db.query()
            .compute("profit", expression: .subtract(.field("revenue"), .field("cost")))
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records[0].storage["profit"]?.doubleValue, 70.0)
    }
    
    func testDivideFields() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "total": .double(100.0),
            "count": .int(4)
        ])
        _ = try db.insert(record)
        
        let results = try db.query()
            .compute("average", expression: .divide(.field("total"), .field("count")))
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records[0].storage["average"]?.doubleValue, 25.0)
    }
    
    func testComplexExpression() throws {
        // Calculate: (price * quantity) - discount
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "price": .double(100.0),
            "quantity": .int(2),
            "discount": .double(10.0)
        ])
        _ = try db.insert(record)
        
        let results = try db.query()
            .compute("final_total", expression: .subtract(
                .multiply(.field("price"), .field("quantity")),
                .field("discount")
            ))
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records[0].storage["final_total"]?.doubleValue, 190.0)
    }
    
    func testMathFunctions() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "value": .double(-5.5),
            "base": .double(2.0),
            "exponent": .double(3.0)
        ])
        _ = try db.insert(record)
        
        let results = try db.query()
            .compute("abs_value", expression: .abs(.field("value")))
            .compute("rounded", expression: .round(.field("value")))
            .compute("power", expression: .power(.field("base"), .field("exponent")))
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records[0].storage["abs_value"]?.doubleValue, 5.5)
        XCTAssertEqual(records[0].storage["rounded"]?.doubleValue, -6.0)
        XCTAssertEqual(records[0].storage["power"]?.doubleValue, 8.0)
    }
    
    func testComputedFieldsWithProjection() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "price": .double(10.0),
            "quantity": .int(5),
            "other": .string("ignored")
        ])
        _ = try db.insert(record)
        
        // Project only price and quantity, then compute total
        let results = try db.query()
            .project("price", "quantity")
            .compute("total", multiply: "price", by: "quantity")
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records[0].storage["price"]?.doubleValue, 10.0)
        XCTAssertEqual(records[0].storage["quantity"]?.intValue, 5)
        XCTAssertEqual(records[0].storage["total"]?.doubleValue, 50.0)
        XCTAssertNil(records[0].storage["other"]) // Should be filtered out by projection
    }
    
    func testComputedFieldsWithFilters() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "price": .double(10.0),
            "quantity": .int(5)
        ])
        _ = try db.insert(record)
        let record2 = BlazeDataRecord([
            "id": .uuid(UUID()),
            "price": .double(20.0),
            "quantity": .int(3)
        ])
        _ = try db.insert(record2)
        
        // Filter and compute
        let results = try db.query()
            .where("price", greaterThan: .double(15.0))
            .compute("total", multiply: "price", by: "quantity")
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].storage["total"]?.doubleValue, 60.0)
    }
    
    func testMultipleComputedFields() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "price": .double(100.0),
            "quantity": .int(2),
            "tax_rate": .double(0.1)
        ])
        _ = try db.insert(record)
        
        let results = try db.query()
            .compute("subtotal", multiply: "price", by: "quantity")
            .compute("tax", expression: .multiply(
                .field("subtotal"),
                .field("tax_rate")
            ))
            .compute("total", expression: .add(
                .field("subtotal"),
                .field("tax")
            ))
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records[0].storage["subtotal"]?.doubleValue, 200.0)
        XCTAssertEqual(records[0].storage["tax"]?.doubleValue, 20.0)
        XCTAssertEqual(records[0].storage["total"]?.doubleValue, 220.0)
    }
}

