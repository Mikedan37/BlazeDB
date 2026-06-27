//
//  BlazedbRepl.swift
//  BlazeCLICore
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import BlazeDBCore

public enum BlazedbRepl {
    private struct ReplDoctorCheck: Codable {
        let name: String
        let passed: Bool
        let message: String
    }

    private struct ReplDoctorReport: Codable {
        let healthy: Bool
        let database: String
        let path: String
        let checks: [ReplDoctorCheck]
        let warnings: [String]
    }

    public static func prompt(_ message: String = "> ") -> String? {
        print(message, terminator: "")
        return readLine()
    }

    private static func writeStdout(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        FileHandle.standardOutput.write(data)
    }

    static func nextHistoryIndex(current: Int?, direction: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        if direction < 0 {
            if let current {
                return (current - 1 + count) % count
            }
            return count - 1
        } else {
            if let current {
                return (current + 1) % count
            }
            return 0
        }
    }

    private static func readReplInput(
        prompt: String,
        history: [String],
        historyCursor: inout Int?
    ) -> String? {
        #if os(macOS) || os(Linux)
        guard let rawMode = try? TerminalRawMode() else {
            return promptInputFallback(prompt: prompt)
        }
        _ = rawMode
        writeStdout(prompt)
        var buffer = ""

        func redraw() {
            writeStdout("\r\u{1b}[2K")
            writeStdout(prompt + buffer)
        }

        while true {
            var b: UInt8 = 0
            let n = read(STDIN_FILENO, &b, 1)
            if n <= 0 { return nil }

            switch b {
            case 10, 13: // Enter
                writeStdout("\r\n")
                historyCursor = nil
                return buffer
            case 3: // Ctrl+C
                writeStdout("^C\r\n")
                historyCursor = nil
                return ""
            case 127, 8: // Backspace
                if !buffer.isEmpty {
                    buffer.removeLast()
                    redraw()
                }
            case 27: // Escape sequence
                var b2: UInt8 = 0
                var b3: UInt8 = 0
                if read(STDIN_FILENO, &b2, 1) == 1, read(STDIN_FILENO, &b3, 1) == 1, b2 == UInt8(ascii: "[") {
                    if b3 == UInt8(ascii: "D"), let next = nextHistoryIndex(current: historyCursor, direction: -1, count: history.count) {
                        historyCursor = next
                        buffer = history[next]
                        redraw()
                    } else if b3 == UInt8(ascii: "C"), let next = nextHistoryIndex(current: historyCursor, direction: 1, count: history.count) {
                        historyCursor = next
                        buffer = history[next]
                        redraw()
                    }
                }
            default:
                if b >= 32, b < 127, let scalar = UnicodeScalar(UInt32(b)) {
                    buffer.append(Character(scalar))
                    historyCursor = nil
                    redraw()
                }
            }
        }
        #else
        return promptInputFallback(prompt: prompt)
        #endif
    }

    private static func promptInputFallback(prompt: String) -> String? {
        writeStdout(prompt)
        return readLine()
    }

    private static func printWelcome(databasePath: String) {
        let url = URL(fileURLWithPath: databasePath)
        let cols = CLITerminalDraw.layoutColumns()
        CLITerminalDraw.clearScreen()
        for line in CLIBranding.heroBlockLines(width: cols) { print(line) }
        print("")
        print(CLIColors.bold("  shell ready"))
        print(CLIColors.muted("  Connected to \(url.lastPathComponent)"))
        print(CLIColors.muted("  Type \(CLIColors.ice("help")) or \(CLIColors.ice("?")) for shortcuts"))
        print("")
        CLITerminalDraw.flush()
    }

    private static func humanBytes(_ value: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: value)
    }

    private static func fieldSummary(_ field: BlazeDocumentField) -> String {
        switch field {
        case .string(let v):
            return v
        case .int(let v):
            return String(v)
        case .double(let v):
            return String(format: "%.3f", v)
        case .bool(let v):
            return v ? "true" : "false"
        case .date(let v):
            let fmt = ISO8601DateFormatter()
            return fmt.string(from: v)
        case .uuid(let v):
            return v.uuidString
        case .data(let d):
            return "<data \(d.count)b>"
        case .array(let arr):
            return "[\(arr.count) items]"
        case .dictionary(let dict):
            return "{\(dict.count) fields}"
        case .vector(let vec):
            return "<vector \(vec.count)>"
        case .null:
            return "null"
        }
    }

    private static func prettyDate(_ iso8601: String) -> String {
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: iso8601) else { return iso8601 }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    private static func printStatus(client: BlazeDBClient, dbPath: String) {
        do {
            let stats = try client.stats()
            let monitoring = try client.getMonitoringSnapshot()
            let dbName = URL(fileURLWithPath: dbPath).lastPathComponent
            print(CLIColors.bold("  status"))
            print(CLIColors.muted("  \(dbName) · \(monitoring.health.status)"))
            print("  records: \(stats.recordCount)")
            print("  pages: \(stats.pageCount)")
            print("  size: \(humanBytes(stats.databaseSize))")
            if let wal = stats.walSize {
                print("  wal: \(humanBytes(wal))")
            }
            print("  indexes: \(monitoring.performance.indexCount)")
            print("  active tx: \(monitoring.performance.activeTransactions)")
            print("  cache hit: \(String(format: "%.1f%%", stats.cacheHitRate * 100))")
            print("  rls: \(client.isRLSEnabled ? "enabled" : "disabled") · policies \(client.listRLSPolicyNames().count)")
            print("  rls context: \(client.hasRLSContext ? "set" : "not set")")
        } catch {
            print("❌ Status error: \(error.localizedDescription)")
        }
    }

    private static func printSchema(client: BlazeDBClient) {
        do {
            let monitoring = try client.getMonitoringSnapshot()
            let schema = monitoring.schema
            print(CLIColors.bold("  schema"))
            print("  total fields: \(schema.totalFields)")
            if !monitoring.performance.indexNames.isEmpty {
                print("  indexes: \(monitoring.performance.indexNames.sorted().joined(separator: ", "))")
            } else {
                print("  indexes: (none)")
            }
            if !schema.commonFields.isEmpty {
                print("  common fields: \(schema.commonFields.joined(separator: ", "))")
            }
            if !schema.customFields.isEmpty {
                print("  custom fields:")
                for key in schema.customFields {
                    let type = schema.inferredTypes[key] ?? "unknown"
                    print("    - \(key): \(type)")
                }
            }
        } catch {
            print("❌ Schema error: \(error.localizedDescription)")
        }
    }

    private static func buildDoctorReport(client: BlazeDBClient, dbPath: String) -> ReplDoctorReport {
        var checks: [ReplDoctorCheck] = []
        var warnings: [String] = []

        let dbExists = FileManager.default.fileExists(atPath: dbPath)
        checks.append(
            ReplDoctorCheck(
                name: "file",
                passed: dbExists,
                message: dbExists ? "database file exists" : "database file missing"
            )
        )

        do {
            _ = try client.stats()
            checks.append(ReplDoctorCheck(name: "stats", passed: true, message: "stats readable"))
        } catch {
            checks.append(ReplDoctorCheck(name: "stats", passed: false, message: error.localizedDescription))
        }

        do {
            _ = try client.health()
            checks.append(ReplDoctorCheck(name: "health", passed: true, message: "health probe succeeded"))
        } catch {
            checks.append(ReplDoctorCheck(name: "health", passed: false, message: error.localizedDescription))
        }

        do {
            _ = try client.getMonitoringSnapshot()
            checks.append(ReplDoctorCheck(name: "monitoring", passed: true, message: "monitoring snapshot generated"))
        } catch {
            checks.append(ReplDoctorCheck(name: "monitoring", passed: false, message: error.localizedDescription))
        }

        do {
            _ = try client.fetchPage(offset: 0, limit: 1)
            checks.append(ReplDoctorCheck(name: "read-path", passed: true, message: "read path healthy"))
        } catch {
            checks.append(ReplDoctorCheck(name: "read-path", passed: false, message: error.localizedDescription))
        }

        if client.isRLSEnabled && !client.hasRLSContext {
            warnings.append("RLS enabled without runtime context (access may fail closed)")
        }

        let healthy = checks.allSatisfy(\.passed)
        return ReplDoctorReport(
            healthy: healthy,
            database: URL(fileURLWithPath: dbPath).lastPathComponent,
            path: dbPath,
            checks: checks,
            warnings: warnings
        )
    }

    private static func printDoctor(client: BlazeDBClient, dbPath: String, asJSON: Bool) {
        let report = buildDoctorReport(client: client, dbPath: dbPath)
        if asJSON {
            if let data = try? JSONEncoder().encode(report),
               let text = String(data: data, encoding: .utf8) {
                print(text)
            } else {
                print("{}")
            }
            return
        }

        print(CLIColors.bold("  doctor"))
        print(CLIColors.muted("  \(report.database)"))
        for check in report.checks {
            let icon = check.passed ? "✅" : "❌"
            print("  \(icon) \(check.name): \(check.message)")
        }
        for warning in report.warnings {
            print("  ⚠️ \(warning)")
        }
        print(report.healthy ? "  ✅ healthy" : "  ❌ unhealthy")
    }

    private static func inspectorValue(_ field: BlazeDocumentField) -> String {
        switch field {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(format: "%.4f", value)
        case .bool(let value):
            return value ? "true" : "false"
        case .date(let value):
            let iso = ISO8601DateFormatter().string(from: value)
            return "\(prettyDate(iso)) (\(iso))"
        case .uuid(let value):
            return value.uuidString
        case .data(let value):
            return "<binary \(value.count) bytes>"
        case .array(let items):
            return "<array \(items.count) items>"
        case .dictionary(let fields):
            return "<object \(fields.count) fields>"
        case .vector(let dims):
            return "<vector \(dims.count)>"
        case .null:
            return "null"
        }
    }

    private static func orderedInspectorKeys(_ storage: [String: BlazeDocumentField]) -> [String] {
        let preferred = ["_blazeKind", "id", "kind", "role", "project", "createdAt", "updatedAt", "sessionId", "title", "name"]
        let preferredKeys = preferred.filter { storage[$0] != nil }
        let remaining = storage.keys.filter { !preferredKeys.contains($0) }.sorted()
        return preferredKeys + remaining
    }

    static func recordIDDisplayText(record: BlazeDataRecord, requestedID: String?) -> String {
        guard let field = record.storage["id"] else {
            return requestedID ?? "<id unavailable>"
        }
        switch field {
        case .uuid(let value):
            return value.uuidString
        case .string(let value):
            if UUID(uuidString: value) != nil {
                return value
            }
            return "<id invalid: \(value)>"
        default:
            return "<id invalid>"
        }
    }

    private static func printInspector(record: BlazeDataRecord, requestedID: String?) {
        let storage = record.storage
        let idText = recordIDDisplayText(record: record, requestedID: requestedID)
        print(CLIColors.bold("  record \(idText)"))

        let multilineKeys = Set(["text", "content", "message", "body"])
        let keyWidth = 10
        for key in orderedInspectorKeys(storage) where !multilineKeys.contains(key) {
            guard let field = storage[key] else { continue }
            let label = key.padding(toLength: keyWidth, withPad: " ", startingAt: 0)
            print("  \(CLIColors.headerCol(label)) \(inspectorValue(field))")
        }

        for key in ["text", "content", "message", "body"] where storage[key] != nil {
            guard let field = storage[key] else { continue }
            print("  \(CLIColors.headerCol(key))")
            let value = inspectorValue(field)
            for line in value.split(separator: "\n", omittingEmptySubsequences: false) {
                print("    \(line)")
            }
        }
    }

    private static func fieldPlainValue(_ field: BlazeDocumentField) -> Any {
        switch field {
        case .string(let v):
            return v
        case .int(let v):
            return v
        case .double(let v):
            return v
        case .bool(let v):
            return v
        case .date(let v):
            let fmt = ISO8601DateFormatter()
            return fmt.string(from: v)
        case .uuid(let v):
            return v.uuidString
        case .data(let d):
            return d.base64EncodedString()
        case .array(let arr):
            return arr.map(fieldPlainValue)
        case .dictionary(let dict):
            var out: [String: Any] = [:]
            for (k, v) in dict { out[k] = fieldPlainValue(v) }
            return out
        case .vector(let vec):
            return vec
        case .null:
            return NSNull()
        }
    }

    private static func recordPlainDictionary(_ record: BlazeDataRecord) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in record.storage { out[k] = fieldPlainValue(v) }
        return out
    }

    private static func printRecordJSON(_ record: BlazeDataRecord) {
        let object = recordPlainDictionary(record)
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            print(object)
            return
        }
        print(text)
    }

    static func runSoftDelete(client: BlazeDBClient, id: UUID) -> String {
        do {
            try client.softDelete(id: id)
            return "🗑️ Soft deleted"
        } catch {
            return "❌ Soft delete failed: \(error.localizedDescription)"
        }
    }

    static func runDelete(client: BlazeDBClient, id: UUID) -> String {
        do {
            try client.delete(id: id)
            return "🗑️ Deleted record \(id)"
        } catch {
            return "❌ Delete failed: \(error.localizedDescription)"
        }
    }

    static func runUpdate(client: BlazeDBClient, id: UUID, json: String) -> String {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: BlazeDocumentField].self, from: data) else {
            return "❌ Invalid update format. Use: update <uuid> {\"key\": \"value\"}"
        }
        do {
            try client.update(id: id, with: BlazeDataRecord(dict))
            return "✏️ Updated record \(id)"
        } catch {
            return "❌ Update failed: \(error.localizedDescription)"
        }
    }

    private static func recordUUID(_ record: BlazeDataRecord) -> UUID? {
        if case .uuid(let value)? = record.storage["id"] {
            return value
        }
        if case .string(let text)? = record.storage["id"] {
            return UUID(uuidString: text)
        }
        return nil
    }

    private enum ReplQueryOperator {
        case eq, ne, gt, lt, gte, lte, contains

        static func parse(_ token: String) -> ReplQueryOperator? {
            switch token.lowercased() {
            case "=", "==", "eq":
                return .eq
            case "!=", "<>", "ne":
                return .ne
            case ">":
                return .gt
            case "<":
                return .lt
            case ">=":
                return .gte
            case "<=":
                return .lte
            case "contains":
                return .contains
            default:
                return nil
            }
        }
    }

    private struct ReplQueryFilter {
        let field: String
        let op: ReplQueryOperator
        let value: BlazeDocumentField
    }

    private enum ReplQueryOutput {
        case table, json, ndjson
    }

    private struct ReplQuerySort {
        let field: String
        let descending: Bool
    }

    private struct ReplQueryPlan {
        let filters: [ReplQueryFilter]
        let sort: ReplQuerySort?
        let limit: Int?
        let offset: Int?
        let output: ReplQueryOutput
    }

    private static func tokenizeCommand(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?

        for ch in input {
            if ch == "\"" || ch == "'" {
                if quote == nil {
                    quote = ch
                    continue
                } else if quote == ch {
                    quote = nil
                    continue
                }
            }

            if ch.isWhitespace && quote == nil {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func parseQueryValue(_ raw: String) -> BlazeDocumentField {
        let lowered = raw.lowercased()
        if lowered == "null" { return .null }
        if lowered == "true" { return .bool(true) }
        if lowered == "false" { return .bool(false) }
        if let intValue = Int(raw) { return .int(intValue) }
        if let doubleValue = Double(raw) { return .double(doubleValue) }
        if let uuid = UUID(uuidString: raw) { return .uuid(uuid) }

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return .date(date) }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return .date(date) }

        return .string(raw)
    }

    private static func queryError(_ message: String) -> Error {
        NSError(domain: "blazedb.query", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func parseQueryPlan(_ input: String) throws -> ReplQueryPlan {
        let tokens = tokenizeCommand(input)
        guard !tokens.isEmpty else {
            throw queryError(
                "Usage: query <field> <op> <value> [and <field> <op> <value> ...] [sort <field> [asc|desc]] [limit N] [offset N] [--json|--ndjson]"
            )
        }

        var filters: [ReplQueryFilter] = []
        var sort: ReplQuerySort?
        var limit: Int?
        var offset: Int?
        var output: ReplQueryOutput = .table

        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let lowered = token.lowercased()

            if lowered == "and" {
                index += 1
                continue
            }
            if lowered == "--json" {
                output = .json
                index += 1
                continue
            }
            if lowered == "--ndjson" {
                output = .ndjson
                index += 1
                continue
            }
            if lowered == "sort" || lowered == "orderby" {
                guard index + 1 < tokens.count else {
                    throw queryError("query sort requires a field name")
                }
                let field = tokens[index + 1]
                var descending = false
                if index + 2 < tokens.count {
                    let dir = tokens[index + 2].lowercased()
                    if dir == "desc" || dir == "asc" {
                        descending = dir == "desc"
                        index += 1
                    }
                }
                sort = ReplQuerySort(field: field, descending: descending)
                index += 2
                continue
            }
            if lowered == "limit" || lowered == "--limit" {
                guard index + 1 < tokens.count, let value = Int(tokens[index + 1]), value >= 0 else {
                    throw queryError("query limit requires a non-negative integer")
                }
                limit = value
                index += 2
                continue
            }
            if lowered == "offset" || lowered == "--offset" {
                guard index + 1 < tokens.count, let value = Int(tokens[index + 1]), value >= 0 else {
                    throw queryError("query offset requires a non-negative integer")
                }
                offset = value
                index += 2
                continue
            }

            guard index + 2 < tokens.count else {
                throw queryError("Invalid query filter near '\(token)'. Expected <field> <op> <value>.")
            }

            let field = tokens[index]
            guard let op = ReplQueryOperator.parse(tokens[index + 1]) else {
                throw queryError("Unsupported query operator '\(tokens[index + 1])'. Use = != > < >= <= contains.")
            }
            let value = parseQueryValue(tokens[index + 2])
            filters.append(ReplQueryFilter(field: field, op: op, value: value))
            index += 3
        }

        guard !filters.isEmpty else {
            throw queryError("query requires at least one filter")
        }

        return ReplQueryPlan(filters: filters, sort: sort, limit: limit, offset: offset, output: output)
    }

    private static func executeQueryPlan(client: BlazeDBClient, plan: ReplQueryPlan) throws -> [BlazeDataRecord] {
        let builder = try buildQueryBuilder(client: client, plan: plan)
        let result = try builder.execute()
        guard let records = result.recordsOrNil else {
            throw queryError("query currently supports record results only")
        }
        return records
    }

    private static func buildQueryBuilder(client: BlazeDBClient, plan: ReplQueryPlan) throws -> QueryBuilder {
        let builder = client.query()
        for filter in plan.filters {
            switch filter.op {
            case .eq:
                _ = builder.where(filter.field, equals: filter.value)
            case .ne:
                _ = builder.where(filter.field, notEquals: filter.value)
            case .gt:
                _ = builder.where(filter.field, greaterThan: filter.value)
            case .lt:
                _ = builder.where(filter.field, lessThan: filter.value)
            case .gte:
                _ = builder.where(filter.field, greaterThanOrEqual: filter.value)
            case .lte:
                _ = builder.where(filter.field, lessThanOrEqual: filter.value)
            case .contains:
                guard case .string(let text) = filter.value else {
                    throw queryError("contains requires a string value")
                }
                _ = builder.where(filter.field, contains: text)
            }
        }
        if let sort = plan.sort {
            _ = builder.orderBy(sort.field, descending: sort.descending)
        }
        if let offset = plan.offset {
            _ = builder.offset(offset)
        }
        if let limit = plan.limit {
            _ = builder.limit(limit)
        }
        return builder
    }

    private static func explainQuery(client: BlazeDBClient, queryInput: String, asJSON: Bool) {
        do {
            let plan = try parseQueryPlan(queryInput)
            let builder = try buildQueryBuilder(client: client, plan: plan)
            let detail = try builder.explain()
            let actual = try executeQueryPlan(client: client, plan: plan).count

            if asJSON {
                let payload: [String: Any] = [
                    "estimatedRecords": detail.estimatedRecords,
                    "actualRecords": actual,
                    "candidateIndexes": detail.candidateIndexes,
                    "filterPredicateCount": detail.filterPredicateCount,
                    "referencedFilterFields": detail.referencedFilterFields,
                    "estimatedTimeMs": Int(detail.estimatedTime * 1000),
                    "warnings": detail.warnings,
                    "steps": detail.steps.map { $0.description },
                ]
                if JSONSerialization.isValidJSONObject(payload),
                   let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
                   let text = String(data: data, encoding: .utf8) {
                    print(text)
                } else {
                    print("{}")
                }
                return
            }

            print(CLIColors.bold("  explain"))
            print("  estimated: \(detail.estimatedRecords) · actual: \(actual)")
            if detail.candidateIndexes.isEmpty {
                print("  candidate indexes: (none)")
            } else {
                print("  candidate indexes: \(detail.candidateIndexes.joined(separator: ", "))")
            }
            for step in detail.steps {
                print("  - \(step.description)")
            }
            for warning in detail.warnings {
                print("  ⚠️ \(warning)")
            }
        } catch {
            print("❌ Explain error: \(error.localizedDescription)")
        }
    }

    private static func truncated(_ text: String, width: Int) -> String {
        guard width > 1 else { return String(text.prefix(max(0, width))) }
        if text.count <= width { return text }
        return String(text.prefix(width - 1)) + "…"
    }

    private static func inferColumns(from records: [BlazeDataRecord], limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for record in records {
            for key in record.storage.keys {
                counts[key, default: 0] += 1
            }
        }
        let sorted = counts.keys.sorted { a, b in
            let ca = counts[a, default: 0]
            let cb = counts[b, default: 0]
            if ca == cb { return a < b }
            return ca > cb
        }
        return Array(sorted.prefix(limit))
    }

    private static func printTablePreview(records: [BlazeDataRecord], columns: Int = 5, rows: Int = 8) {
        printRecordsTable(records: records, columns: columns, maxRows: rows, emptyMessage: "  preview: no rows")
    }

    private static func printRecordsTable(
        records: [BlazeDataRecord],
        columns: Int = 6,
        maxRows: Int? = nil,
        emptyMessage: String = "  no rows"
    ) {
        let shownRecords: [BlazeDataRecord]
        if let maxRows {
            shownRecords = Array(records.prefix(maxRows))
        } else {
            shownRecords = records
        }

        guard !shownRecords.isEmpty else {
            print(CLIColors.muted(emptyMessage))
            return
        }

        let keys = inferColumns(from: shownRecords, limit: columns)
        guard !keys.isEmpty else {
            print(CLIColors.muted("  preview: rows have no inspectable fields"))
            return
        }

        let totalWidth = max(80, CLITerminalDraw.layoutColumns())
        let indexWidth = 4
        let separatorWidth = 3 * keys.count
        let remaining = max(20, totalWidth - indexWidth - separatorWidth - 6)
        let colWidth = max(10, remaining / keys.count)

        var header = "#".padding(toLength: indexWidth, withPad: " ", startingAt: 0)
        for key in keys {
            header += " | " + truncated(key, width: colWidth).padding(toLength: colWidth, withPad: " ", startingAt: 0)
        }
        print(CLIColors.headerCol("  \(header)"))
        print(CLIColors.frame("  " + String(repeating: "-", count: min(totalWidth - 2, header.count + 2))))

        for (idx, row) in shownRecords.enumerated() {
            var line = "\(idx + 1)".padding(toLength: indexWidth, withPad: " ", startingAt: 0)
            for key in keys {
                let value = row.storage[key].map(fieldSummary) ?? "—"
                let cell = truncated(value, width: colWidth).padding(toLength: colWidth, withPad: " ", startingAt: 0)
                line += " | " + cell
            }
            print("  \(line)")
        }
        if records.count > shownRecords.count {
            print(CLIColors.muted("  … \(records.count - shownRecords.count) more rows"))
        }
    }

    @discardableResult
    private static func printDatabaseSnapshot(
        client: BlazeDBClient,
        databasePath: String,
        records: [BlazeDataRecord]? = nil
    ) -> [BlazeDataRecord] {
        let dbName = URL(fileURLWithPath: databasePath).lastPathComponent
        let all = records ?? ((try? client.fetchAll()) ?? [])
        let stats = try? client.stats()

        print(CLIColors.bold("  snapshot"))
        if let stats {
            print(CLIColors.muted("  \(dbName) · records \(stats.recordCount) · size \(humanBytes(stats.databaseSize)) · pages \(stats.pageCount) · indexes \(stats.indexCount)"))
        } else {
            print(CLIColors.muted("  \(dbName) · records \(all.count)"))
        }
        printTablePreview(records: all)
        print(CLIColors.muted("  commands: fetchAll · fetch <uuid> · query · explain query · status · schema · doctor"))
        print("")
        return all
    }

    private static func isHelpCommand(_ trimmed: String) -> Bool {
        switch trimmed.lowercased() {
        case "help", "?", "shortcuts", "keys":
            return true
        default:
            return false
        }
    }

    private static func readMasterPassphrase(prompt: String, confirm: Bool) throws -> String {
        if let envPassword = ProcessInfo.processInfo.environment["BLAZEDB_MASTER_PASSWORD"], !envPassword.isEmpty {
            return envPassword
        }
        let passphrase = try CLIPasswordReader.readLineHidden(prompt: prompt)
        if confirm {
            let again = try CLIPasswordReader.readLineHidden(prompt: "Confirm master passphrase: ")
            guard passphrase == again else {
                throw NSError(domain: "blazedb.master", code: 1, userInfo: [NSLocalizedDescriptionKey: "Passphrases do not match."])
            }
        }
        return passphrase
    }

    private static func parseMasterLockOptions(_ trimmed: String) -> (scope: CLIMasterStorageScope, label: String?) {
        let tokens = trimmed.split(separator: " ").map(String.init)
        var scope: CLIMasterStorageScope = .persistent
        var label: String?
        var index = 2
        while index < tokens.count {
            let token = tokens[index]
            if token == "--scope", index + 1 < tokens.count {
                scope = CLIMasterStorageScope(rawValue: tokens[index + 1]) ?? .persistent
                index += 2
                continue
            }
            if token == "--label", index + 1 < tokens.count {
                label = tokens[index + 1]
                index += 2
                continue
            }
            index += 1
        }
        return (scope, label)
    }

    private static func handleMasterLockCommand(trimmed: String, dbPath: String, password: String) {
        let options = parseMasterLockOptions(trimmed)
        do {
            if options.scope == .session {
                let entry = try CLIMasterKeyringStore.addEntry(
                    passphrase: "",
                    dbPath: dbPath,
                    dbSecret: password,
                    scope: .session,
                    label: options.label
                )
                print("✅ Master lock updated for current DB (\(entry.scope.rawValue)).")
                return
            }

            let status = try CLIMasterKeyringStore.status()
            let passphrase: String
            if status.exists {
                passphrase = try readMasterPassphrase(prompt: "Master passphrase: ", confirm: false)
            } else {
                print("🔐 Master keyring not initialized. Creating it now.")
                passphrase = try readMasterPassphrase(prompt: "Create master passphrase: ", confirm: true)
                _ = try CLIMasterKeyringStore.initialize(passphrase: passphrase)
            }

            let entry = try CLIMasterKeyringStore.addEntry(
                passphrase: passphrase,
                dbPath: dbPath,
                dbSecret: password,
                scope: options.scope,
                label: options.label
            )
            print("✅ Master lock updated for current DB (\(entry.scope.rawValue)).")
            print("   Path: \(entry.canonicalPath)")
        } catch {
            print("💥 Failed to save into master lock: \(error.localizedDescription)")
        }
    }

    /// Opens the database, records successful open in registry when `registryURL` is set, then runs the REPL.
    public static func runShell(
        dbPath: String,
        password: String,
        registryURL: URL?
    ) throws {
        let url = URL(fileURLWithPath: dbPath)
        let client = try BlazeDBClient(name: "default", fileURL: url, password: password)
        _ = try CLIRLSConfigStore.loadAndApply(forDBPath: dbPath, to: client)

        if let registryURL {
            var reg = try CLIRegistry.load(from: registryURL)
            reg.recordSuccessfulOpen(path: url.path)
            try reg.save(to: registryURL)
        }

        printWelcome(databasePath: dbPath)
        let initialRecords = (try? client.fetchAll()) ?? []
        printDatabaseSnapshot(client: client, databasePath: dbPath, records: initialRecords)
        var lastTableRecords: [BlazeDataRecord] = initialRecords

        var commandHistory: [String] = []
        var historyCursor: Int? = nil
        while let input = readReplInput(prompt: "> ", history: commandHistory, historyCursor: &historyCursor) {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if commandHistory.last != trimmed {
                    commandHistory.append(trimmed)
                }
                historyCursor = nil
            }
            if trimmed == "exit" { break }
            if isHelpCommand(trimmed) {
                CLIHelp.printRepl(databaseName: url.lastPathComponent, databasePath: dbPath)
                continue
            }
            if trimmed == "inspect" || trimmed == "snapshot" {
                let records = (try? client.fetchAll()) ?? []
                lastTableRecords = printDatabaseSnapshot(client: client, databasePath: dbPath, records: records)
                continue
            }
            if trimmed == "status" {
                printStatus(client: client, dbPath: dbPath)
                continue
            }
            if trimmed == "schema" {
                printSchema(client: client)
                continue
            }
            if trimmed == "doctor" || trimmed == "doctor --json" {
                printDoctor(client: client, dbPath: dbPath, asJSON: trimmed == "doctor --json")
                continue
            }
            if trimmed == "begin" {
                do {
                    try client.beginTransaction()
                    print("✅ Transaction started")
                } catch {
                    print("❌ Begin failed: \(error.localizedDescription)")
                }
                continue
            }
            if trimmed == "commit" {
                do {
                    try client.commitTransaction()
                    print("✅ Transaction committed")
                } catch {
                    print("❌ Commit failed: \(error.localizedDescription)")
                }
                continue
            }
            if trimmed == "rollback" {
                do {
                    try client.rollbackTransaction()
                    print("✅ Transaction rolled back")
                } catch {
                    print("❌ Rollback failed: \(error.localizedDescription)")
                }
                continue
            }
            if trimmed == "master lock" || trimmed == "master add" || trimmed.starts(with: "master lock ") || trimmed.starts(with: "master add ") {
                handleMasterLockCommand(trimmed: trimmed, dbPath: dbPath, password: password)
                continue
            }
            if trimmed == "fetchAll" || trimmed == "fetchAll --raw" {
                let records = try client.fetchAll()
                lastTableRecords = records
                if trimmed == "fetchAll --raw" {
                    for r in records { printRecordJSON(r) }
                } else {
                    print(CLIColors.bold("  fetchAll (\(records.count) rows)"))
                    printRecordsTable(records: records, columns: 6, maxRows: nil)
                }
            } else if trimmed == "fetchAll --json" {
                let records = try client.fetchAll()
                lastTableRecords = records
                let payload = records.map(recordPlainDictionary)
                if JSONSerialization.isValidJSONObject(payload),
                   let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
                   let text = String(data: data, encoding: .utf8) {
                    print(text)
                } else {
                    print("[]")
                }
            } else if trimmed == "fetchAll --ndjson" {
                let records = try client.fetchAll()
                lastTableRecords = records
                for record in records {
                    let object = recordPlainDictionary(record)
                    if JSONSerialization.isValidJSONObject(object),
                       let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                       let text = String(data: data, encoding: .utf8) {
                        print(text)
                    }
                }
            } else if trimmed.starts(with: "insert ") {
                let json = String(trimmed.dropFirst("insert ".count))
                if let data = json.data(using: .utf8),
                   let dict = try? JSONDecoder().decode([String: BlazeDocumentField].self, from: data) {
                    let id = try client.insert(BlazeDataRecord(dict))
                    print("✅ Inserted with ID: \(id)")
                } else {
                    print("❌ Invalid JSON")
                }
            } else if trimmed.starts(with: "fetch ") {
                let parts = trimmed.split(separator: " ").map(String.init)
                if parts.count >= 2 {
                    let wantsJSON = parts.count >= 3 && parts[2] == "--json"

                    if let id = UUID(uuidString: parts[1]),
                       let record = try? client.fetch(id: id) {
                        if wantsJSON {
                            printRecordJSON(record)
                        } else {
                            printInspector(record: record, requestedID: id.uuidString)
                        }
                        continue
                    }

                    if let index = Int(parts[1]) {
                        guard index > 0 else {
                            print("❌ Row index must be >= 1")
                            continue
                        }
                        guard !lastTableRecords.isEmpty else {
                            print("❌ No table context yet. Run fetchAll first, then fetch <row-index>.")
                            continue
                        }
                        guard index <= lastTableRecords.count else {
                            print("❌ Row index out of range (1...\(lastTableRecords.count))")
                            continue
                        }

                        let record = lastTableRecords[index - 1]
                        if wantsJSON {
                            printRecordJSON(record)
                        } else {
                            printInspector(record: record, requestedID: recordUUID(record)?.uuidString)
                        }
                        continue
                    }

                    print("❌ Invalid fetch target. Use fetch <uuid> or fetch <row-index>.")
                } else {
                    print("❌ Invalid fetch target. Use fetch <uuid> or fetch <row-index>.")
                }
            } else if trimmed == "query" {
                print("❌ Usage: query <field> <op> <value> [and ...] [sort <field> [asc|desc]] [limit N] [offset N] [--json|--ndjson]")
            } else if trimmed == "explain query" {
                print("❌ Usage: explain query <field> <op> <value> [and ...] [sort <field> [asc|desc]] [limit N] [offset N] [--json]")
            } else if trimmed.starts(with: "explain query ") {
                let explainInput = String(trimmed.dropFirst("explain query ".count))
                let jsonMode = explainInput.contains("--json")
                explainQuery(client: client, queryInput: explainInput, asJSON: jsonMode)
            } else if trimmed.starts(with: "query ") {
                let queryInput = String(trimmed.dropFirst("query ".count))
                do {
                    let plan = try parseQueryPlan(queryInput)
                    let records = try executeQueryPlan(client: client, plan: plan)
                    lastTableRecords = records
                    switch plan.output {
                    case .table:
                        print(CLIColors.bold("  query (\(records.count) rows)"))
                        printRecordsTable(records: records, columns: 6, maxRows: nil)
                    case .json:
                        let payload = records.map(recordPlainDictionary)
                        if JSONSerialization.isValidJSONObject(payload),
                           let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
                           let text = String(data: data, encoding: .utf8) {
                            print(text)
                        } else {
                            print("[]")
                        }
                    case .ndjson:
                        for record in records {
                            let object = recordPlainDictionary(record)
                            if JSONSerialization.isValidJSONObject(object),
                               let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                               let text = String(data: data, encoding: .utf8) {
                                print(text)
                            }
                        }
                    }
                } catch {
                    print("❌ Query error: \(error.localizedDescription)")
                }
            } else if trimmed.starts(with: "softDelete ") {
                let idStr = String(trimmed.dropFirst("softDelete ".count))
                if let id = UUID(uuidString: idStr) {
                    print(runSoftDelete(client: client, id: id))
                } else {
                    print("❌ Invalid UUID")
                }
            } else if trimmed.starts(with: "update ") {
                let parts = trimmed.dropFirst("update ".count).split(separator: " ", maxSplits: 1).map(String.init)
                if parts.count == 2, let id = UUID(uuidString: parts[0]) {
                    print(runUpdate(client: client, id: id, json: parts[1]))
                } else {
                    print("❌ Invalid update format. Use: update <uuid> {\"key\": \"value\"}")
                }
            } else if trimmed.starts(with: "delete ") {
                let idStr = String(trimmed.dropFirst("delete ".count))
                if let id = UUID(uuidString: idStr) {
                    print(runDelete(client: client, id: id))
                } else {
                    print("❌ Invalid UUID")
                }
            } else if !trimmed.isEmpty {
                print("❓ Unknown command. Type \(CLIColors.ice("help")).")
            }
        }
    }

    public static func runManager() {
        let manager = BlazeDBManager.shared
        let cols = CLITerminalDraw.layoutColumns()
        CLITerminalDraw.clearScreen()
        for line in CLIBranding.heroBlockLines(width: cols) { print(line) }
        print("")
        print(CLIColors.bold("  manager"))
        print(CLIColors.muted("  Type \(CLIColors.ice("help")) for shortcuts"))
        print("")

        while let input = prompt() {
            let parts = input.split(separator: " ", maxSplits: 2).map(String.init)
            let head = parts.first?.lowercased() ?? ""
            switch head {
            case "exit":
                break
            case "help", "?", "shortcuts":
                CLIHelp.printManager()
            case "list":
                for name in manager.mountedDatabases.keys {
                    print("📁 \(name)")
                }
            case "mount":
                if parts.count == 4 {
                    do {
                        try manager.mountDatabase(
                            named: parts[1],
                            fileURL: URL(fileURLWithPath: parts[2]),
                            password: parts[3]
                        )
                        print("✅ Mounted \(parts[1])")
                    } catch {
                        print("❌ Failed to mount: \(error.localizedDescription)")
                    }
                } else {
                    print("❌ Usage: mount <name> <path> <password>")
                }
            case "use":
                if parts.count == 2 {
                    try? manager.switchDatabase(to: parts[1])
                    print("🎯 Using \(parts[1])")
                } else {
                    print("❌ Usage: use <name>")
                }
            case "current":
                if let current = manager.currentDatabaseName {
                    print("🎯 Currently using:", current)
                } else {
                    print("❌ No active DB")
                }
            default:
                if !head.isEmpty {
                    print("❓ Unknown command. Type \(CLIColors.ice("help")).")
                }
            }
            if head == "exit" { break }
        }
    }
}
