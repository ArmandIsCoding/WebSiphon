//
//  WebSiphonApp.swift
//  WebSiphon
//
//  Created by Armando Meabe on 22/06/2026.
//

import SwiftUI
import SwiftData

@main
struct WebSiphonApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            DownloadTarget.self,
        ])

        func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
            return try ModelContainer(for: schema, configurations: [config])
        }

        // Try normal load first.
        if let container = try? makeContainer() {
            return container
        }

        // Schema mismatch – wipe the on-disk store and start fresh.
        let storeURL = URL.applicationSupportDirectory
            .appendingPathComponent("default.store")

        for ext in ["", "-shm", "-wal"] {
            let file = storeURL.appendingPathExtension("store\(ext)" == "store" ? "" : ext)
            try? FileManager.default.removeItem(at: file)
        }

        // Also try the SwiftData default location.
        let appSupportDir = URL.applicationSupportDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: appSupportDir,
            includingPropertiesForKeys: nil
        ) {
            for item in contents where item.lastPathComponent.contains(".store") {
                try? FileManager.default.removeItem(at: item)
            }
        }

        do {
            return try makeContainer()
        } catch {
            fatalError("Could not create ModelContainer even after store reset: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
