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
    @State private var minimumElapsed = false
    @State private var modelContainer: ModelContainer?

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let modelContainer {
                    ContentView {
                        maybeReady()
                    }
                    .modelContainer(modelContainer)
                }

                if !isReady {
                    LaunchView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(900))
                minimumElapsed = true
                maybeReady()
            }
            .task {
                guard modelContainer == nil else { return }
                modelContainer = makeModelContainer()
                maybeReady()
            }
        }
    }

    private func maybeReady() {
        guard minimumElapsed, modelContainer != nil, !isReady else { return }
        withAnimation(.easeOut(duration: 0.35)) {
            isReady = true
        }
    }

    private func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            FoodEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

            do {
                return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
            } catch {
                fatalError("Could not create fallback ModelContainer: \(error)")
            }
        }
    }
}

private struct LaunchView: View {
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

                    Text("Loading your meals and health guide...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ProgressView()
                    .tint(.green)
                    .scaleEffect(1.15)
                    .padding(.top, 8)
            }
            .padding(24)
        }
    }
}
