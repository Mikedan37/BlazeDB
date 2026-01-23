//
//  BlazeDBClient+TelemetryStub.swift
//  BlazeDB
//
//  Stub telemetry implementation for core builds (when distributed modules are excluded)
//  Provides no-op telemetry to allow core code to compile without distributed dependencies
//

#if !BLAZEDB_DISTRIBUTED
import Foundation

/// Stub telemetry manager for core builds
/// All methods are no-ops - telemetry is only available when BlazeDBDistributed is included
public final class Telemetry {
    private weak var client: BlazeDBClient?
    
    init(client: BlazeDBClient) {
        self.client = client
    }
    
    public func enable(samplingRate: Double = 0.01) {
        // No-op
    }
    
    public func disable() {
        // No-op
    }
    
    public func configure(_ config: Any) {
        // No-op
    }
    
    internal func record(operation: String, duration: Double, success: Bool, recordCount: Int? = nil, error: Error? = nil) {
        // No-op - telemetry disabled in core builds
    }
}

extension BlazeDBClient {
    nonisolated(unsafe) private static var telemetryStubs: [String: Telemetry] = [:]
    private static let telemetryStubLock = NSLock()
    
    /// Stub telemetry property for core builds
    /// Returns a no-op telemetry stub when distributed modules are excluded
    public var telemetry: Telemetry {
        let key = "\(name)-\(fileURL.path)"
        
        Self.telemetryStubLock.lock()
        defer { Self.telemetryStubLock.unlock() }
        
        if let existing = Self.telemetryStubs[key] {
            return existing
        }
        
        let stub = Telemetry(client: self)
        Self.telemetryStubs[key] = stub
        return stub
    }
}
#endif
