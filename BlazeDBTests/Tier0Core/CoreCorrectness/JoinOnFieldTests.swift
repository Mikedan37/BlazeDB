//
//  JoinOnFieldTests.swift
//  BlazeDBTests
//
//  `equals` is the right-hand field. Joins on a field other than the record id
//  must match that field, including repeated keys and unmatched right rows.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class JoinOnFieldTests: XCTestCase {
    private var ordersURL: URL!
    private var productsURL: URL!
    private var orders: BlazeDBClient!
    private var products: BlazeDBClient!

    override func setUp() {
        super.setUp()
        let id = UUID().uuidString
        ordersURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("JoinOnField-orders-\(id).blazedb")
        productsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("JoinOnField-products-\(id).blazedb")
        let password = UUID().uuidString + "aA1!"
        orders = try! BlazeDBClient(name: "orders-\(id)", fileURL: ordersURL, password: password)
        products = try! BlazeDBClient(name: "products-\(id)", fileURL: productsURL, password: password)
    }

    override func tearDown() {
        try? orders.close()
        try? products.close()
        for url in [ordersURL, productsURL] {
            guard let url else { continue }
            let base = url.deletingPathExtension()
            for ext in ["blazedb", "meta", "wal", "salt", "indexes"] {
                try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
            }
            try? FileManager.default.removeItem(at: url)
        }
        orders = nil
        products = nil
        ordersURL = nil
        productsURL = nil
        super.tearDown()
    }

    func testQueryJoinMatchesNamedFieldRatherThanRecordID() throws {
        try seedCatalog()

        let joined = try orders.query()
            .join(products.collection, on: "product_sku", equals: "sku", type: .inner)
            .execute()
            .joined

        let pairs = joined.map { row in
            (row.leftField("order")?.stringValue, row.rightField("name")?.stringValue)
        }
        XCTAssertEqual(pairs.count, 2, "Both orders for SKU-1 should match Widget, and SKU-9 should not invent a match")
        XCTAssertTrue(pairs.contains { $0.0 == "o1" && $0.1 == "Widget" })
        XCTAssertTrue(pairs.contains { $0.0 == "o2" && $0.1 == "Widget" })
    }

    func testQueryRightJoinKeepsUnmatchedNamedFieldRows() throws {
        try seedCatalog()

        let joined = try orders.query()
            .join(products.collection, on: "product_sku", equals: "sku", type: .right)
            .execute()
            .joined

        let names = Set(joined.compactMap { $0.rightField("name")?.stringValue })
        XCTAssertEqual(names, ["Widget", "Gadget"])
        let gadget = joined.filter { $0.rightField("name")?.stringValue == "Gadget" }
        XCTAssertEqual(gadget.count, 1)
        XCTAssertTrue(gadget[0].left.storage.isEmpty)
    }

    func testCollectionJoinMatchesNamedField() throws {
        try seedCatalog()

        let joined = try orders.collection.join(
            with: products.collection,
            on: "product_sku",
            equals: "sku",
            type: .inner
        )
        XCTAssertEqual(joined.count, 2)
        XCTAssertEqual(Set(joined.compactMap { $0.rightField("name")?.stringValue }), ["Widget"])
    }

    private func seedCatalog() throws {
        _ = try products.insert(BlazeDataRecord([
            "sku": .string("SKU-1"),
            "name": .string("Widget")
        ]))
        _ = try products.insert(BlazeDataRecord([
            "sku": .string("SKU-2"),
            "name": .string("Gadget")
        ]))
        _ = try orders.insert(BlazeDataRecord([
            "order": .string("o1"),
            "product_sku": .string("SKU-1")
        ]))
        _ = try orders.insert(BlazeDataRecord([
            "order": .string("o2"),
            "product_sku": .string("SKU-1")
        ]))
        _ = try orders.insert(BlazeDataRecord([
            "order": .string("o3"),
            "product_sku": .string("SKU-9")
        ]))
    }
}
