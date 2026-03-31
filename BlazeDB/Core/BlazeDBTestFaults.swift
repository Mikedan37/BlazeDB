import Foundation

#if DEBUG
actor BlazeDBTestFaults {
    static let shared = BlazeDBTestFaults()
    /// When true, metadata save helpers are allowed to inject failures for tests.
    var forceLayoutSaveFailure: Bool = false
}
#endif

