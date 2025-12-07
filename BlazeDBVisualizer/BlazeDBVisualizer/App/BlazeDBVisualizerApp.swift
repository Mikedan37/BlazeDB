//  BlazeDBVisualizerApp.swift
//  BlazeDBVisualizer
//  Created by Michael Danylchuk on 6/29/25.
//
//  ✅ UPGRADED: Now has both Menu Bar Extra AND full window!
//
import SwiftUI

@main
struct BlazeDBVisualizerApp: App {
    var body: some Scene {
        // Main Window (for full interaction!)
        WindowGroup(id: "main") {
            MainWindowView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 700)
        
        // Menu Bar Extra (quick access)
        MenuBarExtra("BlazeDB", systemImage: "flame.fill") {
            MenuExtraView()
        }
        .menuBarExtraStyle(.window)
    }
}
