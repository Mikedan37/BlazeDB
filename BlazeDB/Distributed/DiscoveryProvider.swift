//
//  DiscoveryProvider.swift
//  BlazeDB
//
//  Platform-neutral protocol for peer discovery (mDNS/Bonjour)
//  Allows BlazeDB to work on Linux without Network.framework dependency
//
//  Created by Auto on 12/14/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation

/// Discovered BlazeDB database
public struct DiscoveredDatabase: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let deviceName: String
    public let host: String
    public let port: UInt16
    public let database: String
    
    public init(
        id: UUID = UUID(),
        name: String,
        deviceName: String,
        host: String,
        port: UInt16,
        database: String
    ) {
        self.id = id
        self.name = name
        self.deviceName = deviceName
        self.host = host
        self.port = port
        self.database = database
    }
}

/// Protocol for peer discovery operations (mDNS/Bonjour)
/// Platform-neutral abstraction that allows different implementations per platform
public protocol DiscoveryProvider {
    /// Start advertising a database for discovery
    /// - Parameters:
    ///   - database: Database name
    ///   - deviceName: Device name
    ///   - port: Port number
    func advertise(database: String, deviceName: String, port: UInt16)
    
    /// Stop advertising
    func stopAdvertising()
    
    /// Start browsing for databases
    /// - Parameter onDiscovered: Callback when databases are discovered
    func startBrowsing(onDiscovered: @escaping ([DiscoveredDatabase]) -> Void)
    
    /// Stop browsing
    func stopBrowsing()
    
    /// Check if discovery is available on this platform
    /// - Returns: true if discovery is available, false otherwise
    func isAvailable() -> Bool
}

#if canImport(Network)
import Network

/// Apple platform implementation using Network framework
/// Provides mDNS/Bonjour discovery on iOS/macOS
public final class AppleDiscoveryProvider: DiscoveryProvider, @unchecked Sendable {
    private var browser: NWBrowser?
    private var service: NetService?
    private var isBrowsing = false
    private var isAdvertising = false
    private var discoveredCallback: (([DiscoveredDatabase]) -> Void)?
    
    public init() {}
    
    public func advertise(database: String, deviceName: String, port: UInt16) {
        guard !isAdvertising else { return }
        isAdvertising = true
        
        let service = NetService(
            domain: "local.",
            type: "_blazedb._tcp.",
            name: "\(database)-\(deviceName)",
            port: Int32(port)
        )
        
        service.delegate = NetServiceDelegateImpl()
        service.publish()
        
        self.service = service
        
        BlazeLogger.info("AppleDiscoveryProvider advertising: \(database) on \(deviceName) (port \(port))")
    }
    
    public func stopAdvertising() {
        service?.stop()
        service = nil
        isAdvertising = false
        BlazeLogger.info("AppleDiscoveryProvider stopped advertising")
    }
    
    public func startBrowsing(onDiscovered: @escaping ([DiscoveredDatabase]) -> Void) {
        guard !isBrowsing else { return }
        isBrowsing = true
        discoveredCallback = onDiscovered
        
        let browser = NWBrowser(
            for: .bonjour(type: "_blazedb._tcp.", domain: nil),
            using: .tcp
        )
        
        browser.stateUpdateHandler = { @Sendable [weak self] state in
            guard let self = self else { return }
            
            switch state {
            case .ready:
                BlazeLogger.info("AppleDiscoveryProvider browsing started")
            case .failed(let error):
                BlazeLogger.error("AppleDiscoveryProvider browsing failed", error: error)
            default:
                break
            }
        }
        
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            
            var discovered: [DiscoveredDatabase] = []
            
            for result in results {
                if case .service(let name, let type, let domain, _) = result.endpoint {
                    // Parse service name: "database-deviceName"
                    let parts = name.split(separator: "-", maxSplits: 1)
                    let database = String(parts.first ?? "")
                    let deviceName = parts.count > 1 ? String(parts[1]) : "Unknown"
                    
                    // Note: IP and port are not available until connection/resolution
                    // Use default values - actual connection will resolve these
                    let db = DiscoveredDatabase(
                        name: name,
                        deviceName: deviceName,
                        host: "localhost",  // Will be resolved on connection
                        port: 8080,  // Will be resolved on connection
                        database: database
                    )
                    discovered.append(db)
                }
            }
            
            DispatchQueue.main.async {
                self.discoveredCallback?(discovered)
            }
        }
        
        browser.start(queue: .global())
        self.browser = browser
        
        BlazeLogger.info("AppleDiscoveryProvider started browsing for databases")
    }
    
    public func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
        discoveredCallback?([])
        discoveredCallback = nil
        BlazeLogger.info("AppleDiscoveryProvider stopped browsing")
    }
    
    public func isAvailable() -> Bool {
        // Network framework is available on Apple platforms
        return true
    }
}

// MARK: - NetService Delegate

private class NetServiceDelegateImpl: NSObject, NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        BlazeLogger.debug("AppleDiscoveryProvider service published: \(sender.name)")
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        BlazeLogger.error("AppleDiscoveryProvider failed to publish: \(errorDict)")
    }
}

/// Default provider type for Apple platforms
public typealias DefaultDiscoveryProvider = AppleDiscoveryProvider

#else

/// No-op implementation for Linux and other non-Apple platforms
/// Performs no actual discovery - all operations are no-ops
/// Suitable for server/headless environments where discovery is not needed
public final class NoopDiscoveryProvider: DiscoveryProvider {
    public init() {}
    
    public func advertise(database: String, deviceName: String, port: UInt16) {
        BlazeLogger.info("NoopDiscoveryProvider: advertise called (no-op on Linux)")
    }
    
    public func stopAdvertising() {
        BlazeLogger.info("NoopDiscoveryProvider: stopAdvertising called (no-op on Linux)")
    }
    
    public func startBrowsing(onDiscovered: @escaping ([DiscoveredDatabase]) -> Void) {
        BlazeLogger.info("NoopDiscoveryProvider: startBrowsing called (no-op on Linux)")
        // Immediately call callback with empty array
        DispatchQueue.main.async {
            onDiscovered([])
        }
    }
    
    public func stopBrowsing() {
        BlazeLogger.info("NoopDiscoveryProvider: stopBrowsing called (no-op on Linux)")
    }
    
    public func isAvailable() -> Bool {
        // Discovery is not available on Linux
        return false
    }
}

/// Default provider type for non-Apple platforms
public typealias DefaultDiscoveryProvider = NoopDiscoveryProvider

#endif // canImport(Network)

#endif // !BLAZEDB_LINUX_CORE

