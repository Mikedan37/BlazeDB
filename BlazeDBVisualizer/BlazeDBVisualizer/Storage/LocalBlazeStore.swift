//  LocalBlazeStore.swift
//  BlazeDBVisualizer
//  Created by Michael Danylchuk on 6/29/25.

import BlazeDB
import Foundation

enum LocalBlazeStore {
    /// Opens the bundled local visualizer database. Prefer this over force-unwraps so sandbox
    /// or permission issues surface as errors instead of process traps.
    static func shared() throws -> BlazeDBClient {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let fileURL = base.appendingPathComponent("BlazeDBVisualizer/local.blaze")
        return try BlazeDBClient(
            name: "LocalVisualizerStore",
            fileURL: fileURL,
            password: ""
        )
    }
}
