//  DynamicCollection+InitMetadataRecovery.swift
//  Shared init-time recovery: rebuild indexMap from page scan when metadata is missing,
//  corrupt, or signature-untrusted (Pass 3 — no half-applied layout from unverified JSON).

import Foundation

extension DynamicCollection {

    /// Rebuilds `indexMap` / `nextPageIndex` by scanning `store` pages; restores secondary
    /// indexes from `preservedIndexDefinitions` or infers them; persists via `saveLayout()`.
    /// - Important: Call only after removing or invalidating untrusted `.meta` when appropriate.
    func performInitMetadataRebuildFromPages(preservedIndexDefinitions: [String: [String]]) throws {
        var rebuiltIndexMap: [UUID: [Int]] = [:]
        var rebuiltNextPageIndex = 0
        var pageIndex = 0

        var consecutiveEmptyPages = 0
        let maxConsecutiveEmpty = 10

        while consecutiveEmptyPages < maxConsecutiveEmpty {
            do {
                guard let data = try store.readPageWithOverflow(index: pageIndex),
                      !data.isEmpty,
                      !data.allSatisfy({ $0 == 0 }) else {
                    consecutiveEmptyPages += 1
                    rebuiltNextPageIndex = max(rebuiltNextPageIndex, pageIndex + 1)
                    pageIndex += 1
                    continue
                }

                consecutiveEmptyPages = 0

                do {
                    let record = try BlazeBinaryDecoder.decode(data)
                    var recordID: UUID? = record.storage["id"]?.uuidValue

                    if recordID == nil {
                        for (key, field) in record.storage {
                            if key.lowercased() == "id" || key.lowercased().hasSuffix("id") {
                                recordID = field.uuidValue
                                break
                            }
                        }
                    }

                    if let id = recordID {
                        if rebuiltIndexMap[id] == nil {
                            rebuiltIndexMap[id] = [pageIndex]
                        } else {
                            rebuiltIndexMap[id]?.append(pageIndex)
                        }
                    } else {
                        BlazeLogger.debug("Page \(pageIndex) decoded but has no ID field")
                    }
                } catch {
                    BlazeLogger.debug("Page \(pageIndex) is not a valid record: \(error)")
                }

                rebuiltNextPageIndex = max(rebuiltNextPageIndex, pageIndex + 1)
                pageIndex += 1
            } catch {
                consecutiveEmptyPages += 1
                if consecutiveEmptyPages >= maxConsecutiveEmpty {
                    break
                }
                pageIndex += 1
            }
        }

        self.indexMap = rebuiltIndexMap
        self.nextPageIndex = rebuiltNextPageIndex
        self.secondaryIndexes = [:]
        self.cachedSearchIndex = nil
        self.cachedSearchIndexedFields = []

        if !preservedIndexDefinitions.isEmpty {
            BlazeLogger.info("Rebuilding \(preservedIndexDefinitions.count) indexes from preserved definitions...")
            self.secondaryIndexDefinitions = preservedIndexDefinitions
            for (indexKey, fields) in preservedIndexDefinitions {
                BlazeLogger.info("Rebuilding index '\(indexKey)' on fields: \(fields.joined(separator: ", "))")
                var rebuilt: [CompoundIndexKey: Set<UUID>] = [:]
                for id in rebuiltIndexMap.keys {
                    if let record = try? self._fetchNoSync(id: id) {
                        let doc = record.storage
                        let rawKey = CompoundIndexKey.fromFields(doc, fields: fields)
                        let normalizedComponents = rawKey.components.map { component -> AnyBlazeCodable in
                            switch component {
                            case .string(let s): return AnyBlazeCodable(s)
                            case .int(let i): return AnyBlazeCodable(i)
                            case .double(let d): return AnyBlazeCodable(d)
                            case .bool(let b): return AnyBlazeCodable(b)
                            case .date(let d): return AnyBlazeCodable(d)
                            case .uuid(let u): return AnyBlazeCodable(u)
                            case .data(let data): return AnyBlazeCodable(data)
                            case .vector(let v): return AnyBlazeCodable(v)
                            case .null: return AnyBlazeCodable("")
                            case .array, .dictionary: return AnyBlazeCodable("")
                            }
                        }
                        let normalizedKey = CompoundIndexKey(normalizedComponents)
                        rebuilt[normalizedKey, default: []].insert(id)
                    }
                }
                self.secondaryIndexes[indexKey] = rebuilt
                BlazeLogger.info("Rebuilt index '\(indexKey)' with \(rebuilt.count) keys, \(rebuilt.values.reduce(0) { $0 + $1.count }) total UUIDs")
            }
        } else {
            BlazeLogger.warn("No index definitions preserved, attempting to infer from data...")

            var fieldFrequency: [String: Int] = [:]
            let sampleSize = min(10, rebuiltIndexMap.count)
            let sampleIDs = Array(rebuiltIndexMap.keys.prefix(sampleSize))

            for id in sampleIDs {
                if let record = try? self._fetchNoSync(id: id) {
                    for field in record.storage.keys {
                        fieldFrequency[field, default: 0] += 1
                    }
                }
            }

            let systemFields = Set(["id", "createdAt", "updatedAt", "project", "deletedAt"])
            let commonIndexFields = ["name", "email", "category", "type", "status", "userId", "user_id"]

            var inferredDefinitions: [String: [String]] = [:]
            for field in commonIndexFields {
                if !systemFields.contains(field),
                   let frequency = fieldFrequency[field],
                   frequency >= sampleSize / 2 {
                    inferredDefinitions[field] = [field]
                    BlazeLogger.info("Inferred index on field '\(field)' (found in \(frequency)/\(sampleSize) sampled records)")
                }
            }

            if !inferredDefinitions.isEmpty {
                self.secondaryIndexDefinitions = inferredDefinitions
                for (indexKey, fields) in inferredDefinitions {
                    BlazeLogger.info("Rebuilding inferred index '\(indexKey)' on fields: \(fields.joined(separator: ", "))")
                    var rebuilt: [CompoundIndexKey: Set<UUID>] = [:]
                    for id in rebuiltIndexMap.keys {
                        if let record = try? self._fetchNoSync(id: id) {
                            let doc = record.storage
                            guard fields.allSatisfy({ doc[$0] != nil }) else { continue }
                            let rawKey = CompoundIndexKey.fromFields(doc, fields: fields)
                            let normalizedComponents = rawKey.components.map { component -> AnyBlazeCodable in
                                switch component {
                                case .string(let s): return AnyBlazeCodable(s)
                                case .int(let i): return AnyBlazeCodable(i)
                                case .double(let d): return AnyBlazeCodable(d)
                                case .bool(let b): return AnyBlazeCodable(b)
                                case .date(let d): return AnyBlazeCodable(d)
                                case .uuid(let u): return AnyBlazeCodable(u)
                                case .data(let data): return AnyBlazeCodable(data)
                                case .vector(let v): return AnyBlazeCodable(v)
                                case .null: return AnyBlazeCodable("")
                                case .array, .dictionary: return AnyBlazeCodable("")
                                }
                            }
                            let normalizedKey = CompoundIndexKey(normalizedComponents)
                            rebuilt[normalizedKey, default: []].insert(id)
                        }
                    }
                    self.secondaryIndexes[indexKey] = rebuilt
                    BlazeLogger.info("Rebuilt inferred index '\(indexKey)' with \(rebuilt.count) keys, \(rebuilt.values.reduce(0) { $0 + $1.count }) total UUIDs")
                }
            } else {
                BlazeLogger.warn("Could not infer index definitions from data, indexes will be empty")
            }
        }

        BlazeLogger.info("✅ [INIT] Successfully rebuilt layout from data file: \(rebuiltIndexMap.count) records found")
        try saveLayout()
        layoutSignatureVerified = true
        BlazeLogger.info("✅ [INIT] Rebuilt layout saved successfully")
    }
}
