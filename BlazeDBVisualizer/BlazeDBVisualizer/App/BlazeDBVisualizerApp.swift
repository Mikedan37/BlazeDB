//  BlazeDBVisualizerApp.swift
//  BlazeDBVisualizer
//  Created by Michael Danylchuk on 6/29/25.
import SwiftUI

@main
struct BlazeDBVisualizerApp: App {
    var body: some Scene {
        MenuBarExtra("BlazeDB", systemImage: "flame.fill") {
            MenuExtraView()
        }
    }
}
