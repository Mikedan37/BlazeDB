//
//  MemorySampler.swift
//  BlazeDBBenchmarks
//

import Foundation

#if canImport(Darwin)
import Darwin
#endif

enum MemorySampler {
    struct Sample: Codable {
        let label: String
        let residentBytes: UInt64?
        let note: String
    }

    static func residentBytes() -> UInt64? {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.resident_size
        #else
        return nil
        #endif
    }

    static func sample(_ label: String) -> Sample {
        Sample(
            label: label,
            residentBytes: residentBytes(),
            note: residentBytes() == nil ? "RSS unavailable on this platform" : "mach_task_basic_info.resident_size"
        )
    }

    static func formatBytes(_ bytes: UInt64?) -> String {
        guard let bytes else { return "N/A" }
        if bytes >= 1_048_576 {
            return String(format: "%.2f MB", Double(bytes) / 1_048_576.0)
        }
        if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        }
        return "\(bytes) B"
    }
}
