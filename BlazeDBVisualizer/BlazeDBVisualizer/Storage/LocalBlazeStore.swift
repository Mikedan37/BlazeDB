//  LocalBlazeStore.swift
//  BlazeDBVisualizer
//  Created by Michael Danylchuk on 6/29/25.

import BlazeDB
import Foundation

enum LocalBlazeStore {
    static var shared: BlazeDBClient {
        try! BlazeDBClient(
            name: "LocalVisualizerStore",
            fileURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("BlazeDBVisualizer/local.blaze"),
            password: ""
        )
    }
}
