//
//  BlazeDiscovery.swift
//  BlazeDB Distributed
//
//  Automatic device discovery using mDNS/Bonjour
//  Enables Mac and iOS to find each other automatically
//
//  Created by Michael Danylchuk on 1/15/25.
//

import Foundation
import Network

#if canImport(Foundation)
// NetService is part of Foundation on Apple platforms
#endif

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

/// Automatic discovery using mDNS/Bonjour
public class BlazeDiscovery: ObservableObject {
    @Published public var discoveredDatabases: [DiscoveredDatabase] = []
    
    private var browser: NWBrowser?
    private var service: NetService?
    private var isBrowsing = false
    private var isAdvertising = false
    
    public init() {}
    
    // MARK: - Advertising (Server - Mac)
    
    /// Advertise database for discovery (Mac - Server)
    public func advertise(
        database: String,
        deviceName: String,
        port: UInt16 = 8080
    ) {
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
        
        BlazeLogger.info("BlazeDiscovery advertising: \(database) on \(deviceName) (port \(port))")
    }
    
    /// Stop advertising
    public func stopAdvertising() {
        service?.stop()
        service = nil
        isAdvertising = false
        BlazeLogger.info("BlazeDiscovery stopped advertising")
    }
    
    // MARK: - Browsing (Client - iOS)
    
    /// Browse for databases (iOS - Client)
    public func startBrowsing() {
        guard !isBrowsing else { return }
        isBrowsing = true
        
        let browser = NWBrowser(
            for: .bonjour(type: "_blazedb._tcp.", domain: nil),
            using: .tcp
        )
        
        browser.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            
            switch state {
            case .ready:
                BlazeLogger.info("BlazeDiscovery browsing started")
            case .failed(let error):
                BlazeLogger.error("BlazeDiscovery browsing failed", error: error)
            default:
                break
            }
        }
        
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            
            var discovered: [DiscoveredDatabase] = []
            
            for result in results {
                if case .bonjour(let record) = result.endpoint {
                    // Parse service name: "database-deviceName"
                    let parts = record.name.split(separator: "-", maxSplits: 1)
                    let database = String(parts.first ?? "")
                    let deviceName = parts.count > 1 ? String(parts[1]) : "Unknown"
                    
                    let db = DiscoveredDatabase(
                        name: record.name,
                        deviceName: deviceName,
                        host: record.hostname ?? "localhost",
                        port: UInt16(record.port ?? 8080),
                        database: database
                    )
                    discovered.append(db)
                }
            }
            
            DispatchQueue.main.async {
                self.discoveredDatabases = discovered
            }
        }
        
        browser.start(queue: .global())
        self.browser = browser
        
        BlazeLogger.info("BlazeDiscovery started browsing for databases")
    }
    
    /// Stop browsing
    public func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
        discoveredDatabases.removeAll()
        BlazeLogger.info("BlazeDiscovery stopped browsing")
    }
}

// MARK: - NetService Delegate

private class NetServiceDelegateImpl: NSObject, NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        BlazeLogger.debug("BlazeDiscovery service published: \(sender.name)")
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        BlazeLogger.error("BlazeDiscovery failed to publish: \(errorDict)")
    }
}

