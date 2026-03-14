import Foundation

public struct StagingTelemetryEvent: Codable, Sendable {
    public let operation: String
    public let durationMS: Double
    public let success: Bool
    public let timestamp: Date

    public init(operation: String, durationMS: Double, success: Bool, timestamp: Date = Date()) {
        self.operation = operation
        self.durationMS = durationMS
        self.success = success
        self.timestamp = timestamp
    }
}

public struct StagingTelemetrySummary: Sendable {
    public let total: Int
    public let successes: Int
    public let failures: Int
    public let avgDurationMS: Double
}

public actor StagingTelemetryCollector {
    private var events: [StagingTelemetryEvent] = []

    public init() {}

    public func record(_ event: StagingTelemetryEvent) {
        events.append(event)
    }

    public func summary() -> StagingTelemetrySummary {
        let total = events.count
        let successes = events.filter(\.success).count
        let failures = total - successes
        let avgDuration = total > 0 ? events.map(\.durationMS).reduce(0, +) / Double(total) : 0
        return StagingTelemetrySummary(
            total: total,
            successes: successes,
            failures: failures,
            avgDurationMS: avgDuration
        )
    }
}
