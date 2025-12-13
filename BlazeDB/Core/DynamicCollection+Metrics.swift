import Foundation

extension DynamicCollection {
    public var pageCount: Int {
        queue.sync {
            Set(indexMap.values.flatMap { $0 }).count
        }
    }
    
    public var orphanedPageCount: Int {
        queue.sync {
            let usedPages = Set(indexMap.values.flatMap { $0 })
            let allPages = Set(0..<nextPageIndex)
            return allPages.subtracting(usedPages).count
        }
    }
    
    public var recordCount: Int {
        queue.sync {
            indexMap.count
        }
    }
    
    public var largestRecordSize: Int {
        queue.sync {
            (try? fetchAll().map { record in
                (try? BlazeBinaryEncoder.encode(record).count) ?? 0
            }.max() ?? 0) ?? 0
        }
    }
    
    public var pageWarningCount: Int {
        queue.sync {
            do {
                let all = try fetchAll()
                return all.filter {
                    guard let encodedSize = try? BlazeBinaryEncoder.encode($0).count else {
                        return false
                    }
                    return encodedSize >= 3900
                }.count
            } catch {
                return 0
            }
        }
    }
}

