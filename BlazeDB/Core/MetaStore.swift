import Foundation

public protocol MetaStore {
    func fetchMeta() throws -> [String: BlazeDocumentField]
    func updateMeta(_ newMeta: [String: BlazeDocumentField]) throws
}

