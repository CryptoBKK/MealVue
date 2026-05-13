//
//  MealVueApp.swift
//  MealVue
//
//  Created by Quinn Rieman on 28/4/26.
//

import SwiftUI
import SwiftData

@main
struct MealVueApp: App {
    @State private var isReady = false
    @State private var modelContainer: ModelContainer?
    @State private var startupError: String?
    @State private var healthKitManager = HealthKitManager()

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let modelContainer {
                    ContentView {
                        maybeReady()
                    }
                    .modelContainer(modelContainer)
                    .environment(healthKitManager)
                }

                if !isReady {
                    LaunchView(startupError: startupError)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                guard modelContainer == nil else { return }
                modelContainer = makeModelContainer()
                maybeReady()
            }
        }
    }

    private func maybeReady() {
        guard modelContainer != nil, !isReady else { return }
        withAnimation(.easeOut(duration: 0.35)) {
            isReady = true
        }
    }

    private func makeModelContainer() -> ModelContainer? {
        let schema = Schema([FoodEntry.self])
        let configuration = ModelConfiguration(
            "MealVue",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .private("iCloud.com.mealvue.app")
        )

        do {
            print("🔍 Creating ModelContainer for FoodEntry...")
            let container = try ModelContainer(
                for: schema,
                configurations: configuration
            )
            print("✅ ModelContainer created successfully")
            return container
        } catch {
            print("❌ Failed to create ModelContainer: \(error)")
            print("   Error type: \(type(of: error))")

            do {
                try resetStoreFiles(at: storeURL)
                let container = try ModelContainer(
                    for: schema,
                    configurations: configuration
                )
                print("⚠️ Recreated SwiftData store after removing incompatible files")
                return container
            } catch {
                print("❌ Failed to recreate store on disk: \(error)")

                do {
                    let inMemoryConfiguration = ModelConfiguration(
                        "MealVueFallback",
                        schema: schema,
                        isStoredInMemoryOnly: true,
                        cloudKitDatabase: .none
                    )
                    let container = try ModelContainer(
                        for: schema,
                        configurations: inMemoryConfiguration
                    )
                    print("⚠️ Using in-memory SwiftData store fallback")
                    return container
                } catch {
                    startupError = "Meal data could not be loaded."
                    print("❌ Unable to create even an in-memory ModelContainer: \(error)")
                    return nil
                }
            }
        }
    }

    private var storeURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL.documentsDirectory
        let directory = applicationSupport.appendingPathComponent("MealVue", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        return directory.appendingPathComponent("MealVue.store")
    }

    private func resetStoreFiles(at url: URL) throws {
        let fileManager = FileManager.default
        let sidecarURLs = [
            url,
            url.deletingPathExtension().appendingPathExtension("\(url.pathExtension)-shm"),
            url.deletingPathExtension().appendingPathExtension("\(url.pathExtension)-wal")
        ]

        for sidecarURL in sidecarURLs where fileManager.fileExists(atPath: sidecarURL.path) {
            try fileManager.removeItem(at: sidecarURL)
        }
    }
}

private struct LaunchView: View {
    let startupError: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.green.opacity(0.22), Color.blue.opacity(0.12), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: 112, height: 112)
                        .shadow(color: .black.opacity(0.08), radius: 20, y: 8)

                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                }

                VStack(spacing: 6) {
                    Text("MealVue")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text("Loading your meals, iCloud sync, and health guide...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let startupError {
                    Text(startupError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else {
                    ProgressView()
                        .tint(.green)
                        .scaleEffect(1.15)
                        .padding(.top, 8)
                }
            }
            .padding(24)
        }
    }
}
