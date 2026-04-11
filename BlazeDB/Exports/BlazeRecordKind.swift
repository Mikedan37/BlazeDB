import Foundation

public enum BlazeRecordKind {
    public static let storageKey = "_blazeKind"

    public static func normalizedName(for type: Any.Type) -> String {
        String(describing: type).lowercased()
    }

    public static func recordMatchesNamespace(_ record: BlazeDataRecord, normalizedNamespace norm: String) -> Bool {
        guard let have = record.storage[storageKey]?.stringValue?.lowercased() else { return false }
        return have == norm
    }
}
