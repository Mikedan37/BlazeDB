//
//  BlazeStudioApp.swift
//  BlazeStudio
//
//  Created by Michael Danylchuk on 7/5/25.
//

import SwiftUI

@main
struct BlazeStudioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(BlockStore())
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}
