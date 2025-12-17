//
//  BlazeDiscovery.swift
//  BlazeDB Distributed
//
//  Automatic device discovery using mDNS/Bonjour
//  Enables Mac and iOS to find each other automatically
//  Platform-neutral implementation using DiscoveryProvider
//
//  Created by Michael Danylchuk on 1/15/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation
#if canImport(Combine)
import Combine
#endif

/// Automatic discovery using mDNS/Bonjour
/// Platform-neutral wrapper around DiscoveryProvider
public class BlazeDiscovery: ObservableObject {
    @Published public var discoveredDatabases: [DiscoveredDatabase] = []
    
    private let provider: DiscoveryProvider
    
    /// Initialize with a custom discovery provider
    /// - Parameter provider: Discovery provider to use (defaults to platform-appropriate provider)
    public init(provider: DiscoveryProvider? = nil) {
        self.provider = provider ?? DefaultDiscoveryProvider()
    }
    
    // MARK: - Advertising (Server - Mac)
    
    /// Advertise database for discovery (Mac - Server)
    public func advertise(
        database: String,
        deviceName: String,
        port: UInt16 = 8080
    ) {
        provider.advertise(database: database, deviceName: deviceName, port: port)
    }
    
    /// Stop advertising
    public func stopAdvertising() {
        provider.stopAdvertising()
    }
    
    // MARK: - Browsing (Client - iOS)
    
    /// Browse for databases (iOS - Client)
    public func startBrowsing() {
        provider.startBrowsing { [weak self] databases in
            DispatchQueue.main.async {
                self?.discoveredDatabases = databases
            }
        }
    }
    
    /// Stop browsing
    public func stopBrowsing() {
        provider.stopBrowsing()
        discoveredDatabases.removeAll()
    }
    
    /// Check if discovery is available on this platform
    public func isAvailable() -> Bool {
        return provider.isAvailable()
    }
}

#endif // !BLAZEDB_LINUX_CORE
