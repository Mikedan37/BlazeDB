//
//  BlazeEnvironmentKeys.swift
//  BlazeDB
//
//  SwiftUI environment integration for the app-facing query facade (not core engine behavior).
//

import Foundation

#if canImport(SwiftUI) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
import SwiftUI

private enum BlazeDBClientEnvironmentKey: EnvironmentKey {
    static let defaultValue: BlazeDBClient? = nil
}

extension EnvironmentValues {
    /// Optional ``BlazeDBClient`` used by ``BlazeQuery`` when you omit an explicit `db:` parameter.
    ///
    /// Inject from the root of your SwiftUI hierarchy (or any ancestor of views that use ``BlazeQuery``):
    ///
    /// ```swift
    /// MyRootView()
    ///     .environment(\.blazeDBClient, appDatabase.db)
    /// ```
    ///
    /// For custom app shells (for example a type named `AppDatabase`), store your client here or add your own
    /// `EnvironmentKey` and assign the same ``BlazeDBClient`` instance to ``EnvironmentValues/blazeDBClient``.
    public var blazeDBClient: BlazeDBClient? {
        get { self[BlazeDBClientEnvironmentKey.self] }
        set { self[BlazeDBClientEnvironmentKey.self] = newValue }
    }
}

extension View {
    /// Convenience for ``EnvironmentValues/blazeDBClient``.
    public func blazeDBEnvironment(_ client: BlazeDBClient) -> some View {
        environment(\.blazeDBClient, client)
    }
}

#endif
