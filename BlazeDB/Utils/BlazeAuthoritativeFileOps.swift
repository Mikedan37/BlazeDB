//
//  BlazeAuthoritativeFileOps.swift
//  BlazeDB
//
//  Centralized best-effort file removal with explicit logging (Pass 6).
//

import Foundation

/// Best-effort filesystem operations where silent `try?` would hide failures on recovery/cleanup paths.
enum BlazeAuthoritativeFileOps {
    /// Removes a file or directory if present. On failure, logs a warning (does not throw).
    static func removeItemIfExists(at url: URL, context: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        do {
            try fm.removeItem(at: url)
        } catch {
            BlazeLogger.warn("\(context): could not remove \(url.path): \(error.localizedDescription)")
        }
    }
}
