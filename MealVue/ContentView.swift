//  ContentView.swift
//  MealVue
//
//  Created by Quinn Rieman on 28/4/26.
//

import Charts
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import VisionKit

struct ContentView: View {
    var onReady: () -> Void = {}
    @State private var selectedTab = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        TabView(selection: $selectedTab) {
            DailyLogView()
                .tabItem {
                    Label("Today", systemImage: "list.bullet.rectangle.portrait.fill")
                }
                .tag(0)

            LogFoodView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Log Food", systemImage: "camera.fill")
                }
                .tag(1)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(2)

            GuideRootView()
                .tabItem {
                    Label("Guide", systemImage: "heart.text.square.fill")
                }
                .tag(3)

            HealthTrendsView()
                .tabItem {
                    Label("Health", systemImage: "waveform.path.ecg")
                }
                .tag(4)
        }
        .tint(.green)
        .onAppear {
            onReady()
            migrateDefaultAIProviderIfNeeded()
        }
        .sheet(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { isPresented in
                if !isPresented {
                    hasCompletedOnboarding = true
                }
            }
        )) {
            OnboardingWelcomeView {
                hasCompletedOnboarding = true
                selectedTab = 0
            }
        }
    }

    private func migrateDefaultAIProviderIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didDefaultToCloudflareMealVueAI") else { return }
        defaults.set(AIProvider.cloudflare.rawValue, forKey: "aiProvider")
        defaults.set(true, forKey: "didDefaultToCloudflareMealVueAI")
    }
}

private struct OnboardingWelcomeView: View {
    var onComplete: () -> Void
    @Environment(HealthKitManager.self) private var healthKitManager
    @State private var isRequestingHealth = false
    @State private var healthMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Welcome to MealVue")
                        .font(.largeTitle.bold())

                    Text("Set your health profile first, then use photo, barcode, or text entry to estimate nutrition and compare foods with your kidney and heart targets.")
                        .foregroundStyle(.secondary)

                    onboardingRow(
                        icon: "person.crop.circle.badge.checkmark",
                        title: "Enter Personal Settings",
                        text: "Go to Settings and add CKD stage, weight, and any custom nutrient targets from your clinician or dietitian."
                    )

                    onboardingRow(
                        icon: "sparkles",
                        title: "Use MealVue AI",
                        text: "MealVue AI is built in for testing. Bring-your-own API providers can be used later for lower-cost subscription tiers."
                    )

                    onboardingRow(
                        icon: "heart.text.square.fill",
                        title: "Connect Apple Health",
                        text: "Tap the button below to approve MealVue for saving meal nutrition and reading health trend data."
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Apple Health Permission", systemImage: "heart.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)

                        Text("MealVue needs Health permission before it can sync nutrition totals to Apple Health. You can skip or change this later in the Health tab.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("When iOS asks, allow the nutrition types you want MealVue to write.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    onboardingRow(
                        icon: "exclamationmark.triangle.fill",
                        title: "Review Every Estimate",
                        text: "AI and barcode data can be wrong. Check the label and edit nutrient totals before saving."
                    )

                    if isRequestingHealth {
                        ProgressView("Requesting Apple Health access...")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    if !healthMessage.isEmpty {
                        InfoBanner(title: "Apple Health", message: healthMessage)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Getting Started")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isRequestingHealth ? "Requesting..." : "Connect Health & Start") {
                        Task { await requestHealthAndComplete() }
                    }
                        .fontWeight(.bold)
                        .disabled(isRequestingHealth)
                }
            }
        }
    }

    private func requestHealthAndComplete() async {
        guard !isRequestingHealth else { return }
        isRequestingHealth = true
        healthMessage = ""

        if healthKitManager.isAvailable {
            await healthKitManager.requestAuthorization()

            switch healthKitManager.authorizationState {
            case .authorized, .partial:
                onComplete()
            case .unavailable:
                healthMessage = "Apple Health is not available on this device. You can continue using MealVue without Health sync."
                onComplete()
            default:
                healthMessage = "Apple Health access was not fully enabled. You can turn it on later from the Health tab."
                onComplete()
            }
        } else {
            healthMessage = "Apple Health is not available on this device. You can continue using MealVue without Health sync."
            onComplete()
        }

        isRequestingHealth = false
    }

    private func onboardingRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DailyLogView: View {
    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var entries: [FoodEntry]
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKitManager

    @AppStorage("kidneyChecksEnabled") private var kidneyChecksEnabled = true
    @AppStorage("heartChecksEnabled") private var heartChecksEnabled = true
    @AppStorage("ckdStage") private var ckdStageRaw = CKDStage.notSpecified.rawValue
    @AppStorage("userWeightKg") private var userWeightKg = ""
    @AppStorage("proteinTargetG") private var proteinTargetG = ""
    @AppStorage("sodiumTargetMg") private var sodiumTargetMg = ""
    @AppStorage("potassiumTargetMg") private var potassiumTargetMg = ""
    @AppStorage("phosphorusTargetMg") private var phosphorusTargetMg = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("showTodayProgressRings") private var showTodayProgressRings = true
    @AppStorage("showTodayNutritionBarGraph") private var showTodayNutritionBarGraph = true
    @State private var showSettings = false

    private var todayEntries: [FoodEntry] {
        entries.filter { Calendar.current.isDateInToday($0.timestamp) }
    }

    private var totals: NutritionTotals {
        NutritionTotals(entries: todayEntries)
    }

    private var selectedCKDStage: CKDStage {
        CKDStage(rawValue: ckdStageRaw) ?? .notSpecified
    }

    private var proteinTarget: Double {
        parsedTarget(proteinTargetG) ?? RecommendedTargets.defaultProteinG(
            for: selectedCKDStage,
            weightKg: Double(userWeightKg.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }

    private var sodiumTarget: Double {
        parsedTarget(sodiumTargetMg) ?? RecommendedTargets.defaultSodiumMg(heartChecksEnabled: heartChecksEnabled)
    }

    private var potassiumTarget: Double? {
        parsedTarget(potassiumTargetMg) ?? (kidneyChecksEnabled ? RecommendedTargets.defaultPotassiumMg(for: selectedCKDStage) : nil)
    }

    private var phosphorusTarget: Double? {
        parsedTarget(phosphorusTargetMg) ?? (kidneyChecksEnabled ? RecommendedTargets.defaultPhosphorusMg(for: selectedCKDStage) : nil)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TotalsCard(totals: totals)
                }

                if showTodayProgressRings {
                    Section("Progress Rings") {
                        NutrientRingsView(
                            proteinG: totals.proteinG,
                            proteinTarget: proteinTarget,
                            sodiumMg: totals.sodiumMg,
                            sodiumTarget: sodiumTarget,
                            potassiumMg: totals.potassiumMg,
                            potassiumTarget: potassiumTarget,
                            phosphorusMg: totals.phosphorusMg,
                            phosphorusTarget: phosphorusTarget
                        )
                    }
                }

                if showTodayNutritionBarGraph {
                    Section("Nutrition Bar Graph") {
                        BarGraphView(totals: totals, title: "Today's Nutrition")
                    }
                }

                if todayEntries.isEmpty {
                    ContentUnavailableView(
                        "No meals logged today",
                        systemImage: "fork.knife",
                        description: Text("Use Log Food to capture a meal photo or add an entry manually.")
                    )
                } else {
                    Section("Today") {
                        ForEach(todayEntries) { entry in
                            NavigationLink {
                                FoodEntryDetailView(entry: entry)
                            } label: {
                                FoodEntryRow(entry: entry)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle(todayTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView {
                    showSettings = false
                }
            }
        }
    }

    private var todayTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }

    private func parsedTarget(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private func delete(at offsets: IndexSet) {
        let entryIDs = offsets.map { todayEntries[$0].entryId }

        for index in offsets {
            modelContext.delete(todayEntries[index])
        }

        Task {
            for entryID in entryIDs {
                try? await healthKitManager.deleteExportedMeal(entryID: entryID)
            }
        }
    }
}

private struct LogFoodView: View {
    @Binding var selectedTab: Int

    @State private var showCamera = false
    @State private var showBarcodeScanner = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingImage: IdentifiableImage?
    @State private var pendingBarcodeProduct: BarcodeProduct?
    @State private var showTextEntry = false
    @State private var barcodeLookupMessage = ""
    @State private var isLookingUpBarcode = false

    private var providerNotConfiguredMessage: String {
        switch Config.selectedProvider {
        case .anthropic:
            return "Add an Anthropic API key in Settings if you want automatic nutrition estimates from food photos."
        case .gemini:
            return "Add a Google Gemini API key in Settings if you want automatic nutrition estimates from food photos."
        case .openAI:
            return "Add an OpenAI API key in Settings if you want automatic nutrition estimates from food photos."
        case .openRouter:
            return "Add an OpenRouter API key in Settings if you want automatic nutrition estimates from food photos."
        case .cloudflare:
            return "MealVue AI is temporarily unavailable. Try again later or use manual entry."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 20) {
                        Image(systemName: "fork.knife.circle.fill")
                            .font(.system(size: 88))
                            .foregroundStyle(.green)

                        VStack(spacing: 8) {
                            Text("Log a Meal")
                                .font(.title.bold())
                            Text("Take a photo, choose from your library, or describe what you ate. If no API key is configured, you can still save the photo and fill in the nutrition manually.")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 30)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        Button {
                            showCamera = true
                        } label: {
                            ActionButtonLabel(
                                title: "Take Photo",
                                systemImage: "camera.fill"
                            )
                        }

                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            ActionButtonLabel(
                                title: "Library",
                                systemImage: "photo.on.rectangle.angled"
                            )
                        }

                        Button {
                            showTextEntry = true
                        } label: {
                            ActionButtonLabel(
                                title: "Describe",
                                systemImage: "text.bubble.fill"
                            )
                        }

                        Button {
                            showBarcodeScanner = true
                        } label: {
                            ActionButtonLabel(
                                title: "Barcode",
                                systemImage: "barcode.viewfinder"
                            )
                        }
                    }

                    if isLookingUpBarcode {
                        ProgressView("Looking up barcode...")
                    }

                    if !barcodeLookupMessage.isEmpty {
                        InfoBanner(
                            title: "Barcode lookup",
                            message: barcodeLookupMessage
                        )
                    }

                    if !Config.isConfigured {
                        InfoBanner(
                            title: "AI not configured",
                            message: providerNotConfiguredMessage
                        )
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Log Food")
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera) { image in
                pendingImage = IdentifiableImage(image: image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showBarcodeScanner) {
            BarcodeScannerView { barcode in
                showBarcodeScanner = false
                Task {
                    await lookupBarcode(barcode)
                }
            }
        }
        .sheet(item: $pendingImage) { item in
            PhotoAnalysisView(image: item.image) {
                pendingImage = nil
                selectedTab = 0
            }
        }
        .sheet(item: $pendingBarcodeProduct) { product in
            BarcodeProductEntryView(product: product) {
                pendingBarcodeProduct = nil
                selectedTab = 0
            }
        }
        .sheet(isPresented: $showTextEntry) {
            TextAnalysisEntryView {
                showTextEntry = false
                selectedTab = 0
            }
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    pickerItem = nil
                    try? await Task.sleep(for: .milliseconds(300))
                    pendingImage = IdentifiableImage(image: image)
                } else {
                    pickerItem = nil
                }
            }
        }
    }

    private func lookupBarcode(_ barcode: String) async {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLookingUpBarcode = true
        barcodeLookupMessage = ""
        defer { isLookingUpBarcode = false }

        do {
            let product = try await BarcodeLookupService.lookup(barcode: trimmed)
            try? await Task.sleep(for: .milliseconds(250))
            pendingBarcodeProduct = product
        } catch {
            barcodeLookupMessage = error.localizedDescription
        }
    }

}

private struct HistoryView: View {
    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var entries: [FoodEntry]

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No food history yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Captured and manually logged meals will appear here.")
                    )
                } else {
                    Section("Days") {
                        ForEach(groupedEntries, id: \.date) { section in
                            NavigationLink {
                                DayHistoryView(section: section)
                            } label: {
                                DayHistoryRow(section: section)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            DailyNutritionReportView(entries: entries)
                        } label: {
                            Label("Report", systemImage: "doc.richtext")
                        }
                    }
                }
            }
        }
    }

    private var groupedEntries: [HistorySection] {
        let grouped = Dictionary(grouping: entries) { entry in
            Calendar.current.startOfDay(for: entry.timestamp)
        }

        return grouped.keys.sorted(by: >).map { date in
            HistorySection(date: date, entries: grouped[date] ?? [])
        }
    }
}

private struct DayHistoryView: View {
    let section: HistorySection
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKitManager

    var body: some View {
        List {
            Section {
                TotalsCard(totals: section.totals)
            }

            Section("Meals") {
                ForEach(section.entries) { entry in
                    NavigationLink {
                        FoodEntryDetailView(entry: entry)
                    } label: {
                        FoodEntryRow(entry: entry)
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle(section.shortTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func delete(at offsets: IndexSet) {
        let entriesToDelete = offsets.map { section.entries[$0] }
        let entryIDs = entriesToDelete.map(\.entryId)

        for entry in entriesToDelete {
            modelContext.delete(entry)
        }

        Task {
            for entryID in entryIDs {
                try? await healthKitManager.deleteExportedMeal(entryID: entryID)
            }
        }
    }
}

private struct DayHistoryRow: View {
    let section: HistorySection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.headline)
                    Text("\(section.entries.count) meals")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(section.totals.calories) kcal")
                    .font(.headline)
                    .foregroundStyle(.green)
            }

            HStack(spacing: 10) {
                ReportMetricChip(title: "Protein", value: "\(Int(section.totals.proteinG)) g", tint: .blue)
                ReportMetricChip(title: "Sodium", value: "\(Int(section.totals.sodiumMg)) mg", tint: .orange)
                ReportMetricChip(title: "Potassium", value: "\(Int(section.totals.potassiumMg)) mg", tint: .yellow)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DailyNutritionReportView: View {
    @AppStorage("kidneyChecksEnabled") private var kidneyChecksEnabled = true
    @AppStorage("heartChecksEnabled") private var heartChecksEnabled = true
    @AppStorage("ckdStage") private var ckdStageRaw = CKDStage.notSpecified.rawValue
    @AppStorage("userWeightKg") private var userWeightKg = ""
    @AppStorage("proteinTargetG") private var proteinTargetG = ""
    @AppStorage("sodiumTargetMg") private var sodiumTargetMg = ""
    @AppStorage("potassiumTargetMg") private var potassiumTargetMg = ""
    @AppStorage("phosphorusTargetMg") private var phosphorusTargetMg = ""

    let entries: [FoodEntry]

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var reportURL: URL?
    @State private var reportError = ""

    init(entries: [FoodEntry]) {
        self.entries = entries

        let sortedDates = entries.map(\.timestamp).sorted()
        let minDate = sortedDates.first ?? Date()
        let maxDate = sortedDates.last ?? Date()
        let calendar = Calendar.current
        let defaultStart = max(
            calendar.startOfDay(for: minDate),
            calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: maxDate)) ?? calendar.startOfDay(for: minDate)
        )

        _startDate = State(initialValue: defaultStart)
        _endDate = State(initialValue: maxDate)
    }

    private var selectedCKDStage: CKDStage {
        CKDStage(rawValue: ckdStageRaw) ?? .notSpecified
    }

    private var reportTargets: NutritionTargets {
        NutritionTargets(
            proteinG: parsedTarget(proteinTargetG) ?? RecommendedTargets.defaultProteinG(
                for: selectedCKDStage,
                weightKg: Double(userWeightKg.trimmingCharacters(in: .whitespacesAndNewlines))
            ),
            sodiumMg: parsedTarget(sodiumTargetMg) ?? RecommendedTargets.defaultSodiumMg(heartChecksEnabled: heartChecksEnabled),
            potassiumMg: parsedTarget(potassiumTargetMg) ?? (kidneyChecksEnabled ? RecommendedTargets.defaultPotassiumMg(for: selectedCKDStage) : nil),
            phosphorusMg: parsedTarget(phosphorusTargetMg) ?? (kidneyChecksEnabled ? RecommendedTargets.defaultPhosphorusMg(for: selectedCKDStage) : nil)
        )
    }

    private var filteredSections: [HistorySection] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(startDate, endDate))
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(startDate, endDate))) ?? Date()

        let filteredEntries = entries.filter { entry in
            entry.timestamp >= start && entry.timestamp < end
        }

        let grouped = Dictionary(grouping: filteredEntries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }

        return grouped.keys.sorted(by: >).map { date in
            HistorySection(date: date, entries: grouped[date] ?? [])
        }
    }

    var body: some View {
        List {
            Section("Date Range") {
                DatePicker("Start", selection: $startDate, displayedComponents: .date)
                DatePicker("End", selection: $endDate, displayedComponents: .date)

                Button("Create PDF Report") {
                    generateReport()
                }
                .disabled(filteredSections.isEmpty)

                if let reportURL {
                    ShareLink(item: reportURL) {
                        Label("Share Latest PDF", systemImage: "square.and.arrow.up")
                    }
                }

                if !reportError.isEmpty {
                    Text(reportError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Included Days") {
                if filteredSections.isEmpty {
                    Text("No entries in this date range.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredSections, id: \.date) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(section.title)
                                    .font(.headline)
                                Spacer()
                                Text("\(section.totals.calories) kcal")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                            }

                            HStack(spacing: 10) {
                                ReportMetricChip(title: "Protein", value: "\(Int(section.totals.proteinG)) g", tint: .blue)
                                ReportMetricChip(title: "Sodium", value: "\(Int(section.totals.sodiumMg)) mg", tint: .orange)
                                ReportMetricChip(title: "Potassium", value: "\(Int(section.totals.potassiumMg)) mg", tint: .yellow)
                                ReportMetricChip(title: "Phosphorus", value: "\(Int(section.totals.phosphorusMg)) mg", tint: .purple)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Daily Report")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func generateReport() {
        do {
            reportURL = try NutritionReportPDF.writeReport(
                for: filteredSections.sorted(by: { $0.date < $1.date }),
                startDate: min(startDate, endDate),
                endDate: max(startDate, endDate),
                targets: reportTargets
            )
            reportError = ""
        } catch {
            reportError = "Could not create the PDF report."
        }
    }

    private func parsedTarget(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }
}

private struct ReportMetricChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct ShoppingHelperCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "cart.badge.questionmark")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Shopping Helper")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Scan a barcode or photo-check food before buying.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct GuideRootView: View {
    @AppStorage("kidneyChecksEnabled") private var kidneyChecksEnabled = true
    @AppStorage("heartChecksEnabled") private var heartChecksEnabled = true

    private let recommendedGroups: [FoodGroup] = [
        FoodGroup(
            title: "Lower-Sodium Staples",
            systemImage: "leaf.circle.fill",
            tint: .green,
            items: [
                "Fresh or frozen vegetables without added sauce",
                "Rice, pasta, oats, tortillas, and unsalted crackers",
                "Homemade meals seasoned with herbs instead of heavy salt"
            ]
        ),
        FoodGroup(
            title: "Kidney-Friendlier Produce",
            systemImage: "apple.logo",
            tint: .teal,
            items: [
                "Apples, berries, grapes, peaches, pineapple",
                "Cabbage, cauliflower, cucumber, onions, lettuce",
                "Portions should still match potassium guidance from the care team"
            ]
        ),
        FoodGroup(
            title: "Lean Protein Choices",
            systemImage: "fork.knife.circle.fill",
            tint: .blue,
            items: [
                "Egg whites, fish, chicken, turkey",
                "Tuna packed in water with low sodium",
                "Protein goals depend on CKD stage and dialysis status"
            ]
        )
    ]

    private let foodsToLimit: [FoodGroup] = [
        FoodGroup(
            title: "Foods Often High In Sodium",
            systemImage: "exclamationmark.triangle.fill",
            tint: .orange,
            items: [
                "Processed meats like bacon, sausage, deli meat, and hot dogs",
                "Fast food, instant noodles, canned soups, and chips",
                "Soy sauce, seasoning packets, and many salt substitutes"
            ]
        ),
        FoodGroup(
            title: "Foods Often High In Potassium",
            systemImage: "bolt.heart.fill",
            tint: .yellow,
            items: [
                "Bananas, oranges, melon, and dried fruit",
                "Potatoes, tomatoes, spinach, and avocado",
                "Large amounts of beans, dairy, and some salt substitutes"
            ]
        ),
        FoodGroup(
            title: "Foods Often High In Phosphorus",
            systemImage: "drop.triangle.fill",
            tint: .red,
            items: [
                "Dark colas and processed foods with ingredients containing 'phos'",
                "Large amounts of cheese, milk, nuts, seeds, and bran cereals",
                "Packaged foods with phosphate additives"
            ]
        )
    ]

    private let menuPlans: [MenuPlan] = [
        MenuPlan(
            title: "Menu Plan A",
            meals: [
                Meal(name: "Breakfast", items: "Oatmeal with blueberries, toast with unsalted butter, herbal tea"),
                Meal(name: "Lunch", items: "Grilled chicken wrap with lettuce and cucumber, apple slices"),
                Meal(name: "Dinner", items: "Baked fish, white rice, roasted cauliflower, side salad"),
                Meal(name: "Snack", items: "Unsalted popcorn or crackers with a small serving of cream cheese")
            ]
        ),
        MenuPlan(
            title: "Menu Plan B",
            meals: [
                Meal(name: "Breakfast", items: "Egg-white scramble with peppers and onions, English muffin, grapes"),
                Meal(name: "Lunch", items: "Turkey sandwich on white bread with lettuce, cabbage slaw, pear"),
                Meal(name: "Dinner", items: "Roasted chicken, pasta with olive oil and garlic, green beans"),
                Meal(name: "Snack", items: "Rice cakes with a little jam or unsalted cereal")
            ]
        )
    ]

    private let medicationPages: [MedicationPage] = [
        MedicationPage(
            title: "Pain Medicines",
            systemImage: "pills.fill",
            tint: .red,
            subtitle: "What is usually preferred and what to avoid",
            summary: "Pain medicine safety matters in CKD because some common drugs can reduce kidney blood flow or build up as kidney function drops.",
            safeItems: [
                "Acetaminophen is often preferred over NSAIDs when used as directed.",
                "Topical pain products such as lidocaine, capsaicin, menthol, or camphor may be safer options for some people.",
                "Prescription pain medicines can sometimes be used, but dose changes may be needed based on eGFR."
            ],
            cautionItems: [
                "Ibuprofen, naproxen, ketorolac, meloxicam, celecoxib, diclofenac tablets, and high-dose aspirin are NSAIDs that often are not kidney friendly in CKD.",
                "NSAIDs are especially risky with dehydration, heart failure, liver disease, or when used with ACE inhibitors, ARBs, or diuretics.",
                "Many cold and flu products include hidden NSAIDs, so labels need to be checked carefully."
            ]
        ),
        MedicationPage(
            title: "Blood Pressure Medicines",
            systemImage: "heart.text.square.fill",
            tint: .blue,
            subtitle: "Common kidney-protective medicines and monitoring points",
            summary: "Blood pressure control is a major part of kidney protection, but the best medicine depends on albuminuria, blood pressure, potassium, and eGFR.",
            safeItems: [
                "ACE inhibitors and ARBs may help protect kidney function in people with CKD, high blood pressure, diabetes, or albumin in the urine.",
                "Diuretics are commonly used to manage blood pressure and extra fluid.",
                "These medicines are often kidney-friendly when monitored with follow-up blood tests."
            ],
            cautionItems: [
                "ACE inhibitors, ARBs, and diuretics can change potassium or creatinine, so lab monitoring is important.",
                "Dose adjustments may be needed if kidney function worsens, blood pressure runs low, or dehydration occurs.",
                "Do not stop blood pressure medicines suddenly unless a clinician tells you to."
            ]
        ),
        MedicationPage(
            title: "Diabetes Medicines",
            systemImage: "cross.case.circle.fill",
            tint: .green,
            subtitle: "Common CKD considerations for glucose-lowering drugs",
            summary: "Many diabetes medicines can still be used in CKD, but some need lower doses or closer review as eGFR changes.",
            safeItems: [
                "Some diabetes medicines can be kidney-protective or still safe with dose adjustment.",
                "Insulin is often used in CKD, but the dose may need change because insulin can stay in the body longer.",
                "Medication plans usually work best when tailored to both blood sugar goals and kidney function."
            ],
            cautionItems: [
                "Some diabetes medicines are reduced or stopped at lower eGFR levels.",
                "Risk of low blood sugar can increase as kidney function declines.",
                "All diabetes medicine changes should be tied to current labs and clinician guidance."
            ]
        ),
        MedicationPage(
            title: "Stomach And OTC Medicines",
            systemImage: "stethoscope.circle.fill",
            tint: .orange,
            subtitle: "Antacids, reflux medicines, and supplements",
            summary: "Over-the-counter products are easy to underestimate, but several are problematic in CKD because ingredients can accumulate or hide unsafe drugs.",
            safeItems: [
                "Some reflux and stomach medicines can still be used safely if the dose matches kidney function.",
                "Pharmacist review is useful for any OTC medication used regularly.",
                "Bringing all prescription, OTC, and supplement products to appointments improves safety."
            ],
            cautionItems: [
                "Antacids containing aluminum, magnesium, or large amounts of calcium may not be kidney friendly.",
                "H2 blockers and proton pump inhibitors may need review, especially with long-term use.",
                "Herbal supplements should not be assumed safe for kidneys.",
                "Combination OTC products may include NSAIDs or other ingredients that are risky in CKD."
            ]
        )
    ]

    private let heartBetterChoices: [FoodGroup] = [
        FoodGroup(
            title: "Heart-Healthier Staples",
            systemImage: "heart.circle.fill",
            tint: .pink,
            items: [
                "High-fiber grains such as oats and whole grains when tolerated",
                "Beans, lentils, and vegetables when potassium goals allow",
                "Foods prepared with olive oil instead of heavy saturated fat"
            ]
        ),
        FoodGroup(
            title: "Lean And Unsaturated Fats",
            systemImage: "drop.circle.fill",
            tint: .red,
            items: [
                "Fish, skinless poultry, nuts, seeds, and avocado in appropriate portions",
                "Low-sodium meals built around vegetables and minimally processed foods",
                "Meals that limit added sugar and refined fried foods"
            ]
        )
    ]

    private let heartFoodsToLimit: [FoodGroup] = [
        FoodGroup(
            title: "High Saturated Fat Foods",
            systemImage: "heart.slash.circle.fill",
            tint: .orange,
            items: [
                "Fried foods, fast food, and pastries",
                "Fatty red meat, processed meat, and heavy cream sauces",
                "Large portions of butter, shortening, and full-fat desserts"
            ]
        ),
        FoodGroup(
            title: "High Sodium Foods",
            systemImage: "waveform.path.ecg.rectangle.fill",
            tint: .yellow,
            items: [
                "Processed snacks, canned soups, deli meats, and restaurant meals",
                "Foods with added salt that may worsen blood pressure and fluid retention",
                "Sugar-sweetened drinks and highly processed convenience foods"
            ]
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroCard

                    NavigationLink {
                        ShoppingHelperView()
                    } label: {
                        ShoppingHelperCard()
                    }
                    .buttonStyle(.plain)

                    sectionHeader(
                        title: "Usually Better Choices",
                        subtitle: "Common kidney-friendlier foods for many adults with chronic kidney disease."
                    )

                    ForEach(recommendedGroups) { group in
                        GuideCard(group: group)
                    }

                    sectionHeader(
                        title: "Often Limited Or Avoided",
                        subtitle: "These foods are commonly restricted because of sodium, potassium, or phosphorus."
                    )

                    ForEach(foodsToLimit) { group in
                        GuideCard(group: group)
                    }

                    sectionHeader(
                        title: "Sample Menu Plans",
                        subtitle: "Reference one-day meal ideas. Exact portions and protein targets should come from a clinician or renal dietitian."
                    )

                    ForEach(menuPlans) { plan in
                        MenuPlanCard(plan: plan)
                    }

                    if heartChecksEnabled {
                        sectionHeader(
                            title: "Heart Health Guide",
                            subtitle: "General food patterns that support healthier cholesterol, blood pressure, and overall cardiovascular health."
                        )

                        ForEach(heartBetterChoices) { group in
                            GuideCard(group: group)
                        }

                        sectionHeader(
                            title: "Heart Foods To Limit",
                            subtitle: "Common foods that may be harder on heart health because of sodium, saturated fat, or heavy processing."
                        )

                        ForEach(heartFoodsToLimit) { group in
                            GuideCard(group: group)
                        }
                    }

                    if kidneyChecksEnabled {
                        sectionHeader(
                            title: "Medicine Pages",
                            subtitle: "Open a medication page for focused kidney-safety guidance by category."
                        )

                        ForEach(medicationPages) { page in
                            NavigationLink(value: page) {
                                MedicationPageCard(page: page)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Health Guide")
            .navigationDestination(for: MedicationPage.self) { page in
                MedicationDetailView(page: page)
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MealVue Health Guide")
                .font(.largeTitle.bold())

            Text("Track meals, review food choices, and keep kidney and heart health checks in one place.")
                .foregroundStyle(.secondary)

            Label("Always confirm diet restrictions and medical advice with a clinician.", systemImage: "cross.case.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.16), Color.blue.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.bold())

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ShoppingHelperView: View {
    @AppStorage("kidneyChecksEnabled") private var kidneyChecksEnabled = true
    @AppStorage("heartChecksEnabled") private var heartChecksEnabled = true
    @AppStorage("ckdStage") private var ckdStageRaw = CKDStage.notSpecified.rawValue
    @AppStorage("userWeightKg") private var userWeightKg = ""
    @AppStorage("proteinTargetG") private var proteinTargetG = ""
    @AppStorage("sodiumTargetMg") private var sodiumTargetMg = ""
    @AppStorage("potassiumTargetMg") private var potassiumTargetMg = ""
    @AppStorage("phosphorusTargetMg") private var phosphorusTargetMg = ""

    @State private var showCamera = false
    @State private var showBarcodeScanner = false
    @State private var isChecking = false
    @State private var statusMessage = ""
    @State private var result: ShoppingCheckResult?
    @State private var textDescription = ""
    @State private var foodName = ""
    @State private var quantity = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""
    @State private var sodium = ""
    @State private var potassium = ""
    @State private var phosphorus = ""
    @State private var notes = ""

    private var selectedCKDStage: CKDStage {
        CKDStage(rawValue: ckdStageRaw) ?? .notSpecified
    }

    private var targets: NutritionTargets {
        NutritionTargets(
            proteinG: parsedTarget(proteinTargetG) ?? RecommendedTargets.defaultProteinG(
                for: selectedCKDStage,
                weightKg: Double(userWeightKg.trimmingCharacters(in: .whitespacesAndNewlines))
            ),
            sodiumMg: parsedTarget(sodiumTargetMg) ?? RecommendedTargets.defaultSodiumMg(heartChecksEnabled: heartChecksEnabled),
            potassiumMg: parsedTarget(potassiumTargetMg) ?? (kidneyChecksEnabled ? RecommendedTargets.defaultPotassiumMg(for: selectedCKDStage) : nil),
            phosphorusMg: parsedTarget(phosphorusTargetMg) ?? (kidneyChecksEnabled ? RecommendedTargets.defaultPhosphorusMg(for: selectedCKDStage) : nil)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Shopping Helper")
                        .font(.largeTitle.bold())

                    Text("Check a product against your current kidney and heart settings before it goes in the cart.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button {
                        showCamera = true
                    } label: {
                        ActionButtonLabel(
                            title: "Photo Check",
                            systemImage: "camera.fill",
                            fill: Color.green,
                            foreground: .white
                        )
                    }

                    Button {
                        showBarcodeScanner = true
                    } label: {
                        ActionButtonLabel(
                            title: "Scan Barcode",
                            systemImage: "barcode.viewfinder",
                            fill: Color.green.opacity(0.12),
                            foreground: .green
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Describe a food")
                        .font(.headline)

                    TextField("Example: low sodium canned soup, one cup", text: $textDescription, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        Task { await checkDescription() }
                    } label: {
                        Label("Check Description", systemImage: "text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(textDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !Config.isConfigured)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if isChecking {
                    ProgressView("Checking food...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }

                if !statusMessage.isEmpty {
                    InfoBanner(title: "Shopping check", message: statusMessage)
                }

                if let result {
                    ShoppingCheckResultCard(result: result)

                    MealEditor(
                        foodName: $foodName,
                        quantity: $quantity,
                        calories: $calories,
                        protein: $protein,
                        carbs: $carbs,
                        fat: $fat,
                        fiber: $fiber,
                        sodium: $sodium,
                        potassium: $potassium,
                        phosphorus: $phosphorus,
                        notes: $notes
                    )
                    .padding(.horizontal, -20)

                    Button {
                        updateRecommendationFromEditedFields(source: result.source)
                    } label: {
                        Label("Update Recommendation", systemImage: "checklist.checked")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    ShoppingEmptyState()
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Shopping Helper")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera) { image in
                Task {
                    await checkPhoto(image)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showBarcodeScanner) {
            BarcodeScannerView { barcode in
                showBarcodeScanner = false
                Task {
                    await checkBarcode(barcode)
                }
            }
        }
    }

    private func checkPhoto(_ image: UIImage) async {
        guard Config.isConfigured else {
            statusMessage = "Photo checks need MealVue AI or a configured AI provider."
            return
        }

        isChecking = true
        statusMessage = ""
        defer { isChecking = false }

        do {
            let nutrition = try await ClaudeService.analyzeFood(image: image)
            let snapshot = ShoppingNutritionSnapshot(nutritionResult: nutrition)
            let evaluated = ShoppingDietEvaluator.evaluate(
                snapshot: snapshot,
                source: "Photo estimate",
                targets: targets,
                kidneyChecksEnabled: kidneyChecksEnabled,
                heartChecksEnabled: heartChecksEnabled
            )
            result = evaluated
            applyShoppingResult(evaluated)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func checkDescription() async {
        let description = textDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return }

        guard Config.isConfigured else {
            statusMessage = "Text checks need MealVue AI or a configured AI provider."
            return
        }

        isChecking = true
        statusMessage = ""
        defer { isChecking = false }

        do {
            let nutrition = try await ClaudeService.analyzeText(description: description)
            let snapshot = ShoppingNutritionSnapshot(nutritionResult: nutrition)
            let evaluated = ShoppingDietEvaluator.evaluate(
                snapshot: snapshot,
                source: "Text estimate",
                targets: targets,
                kidneyChecksEnabled: kidneyChecksEnabled,
                heartChecksEnabled: heartChecksEnabled
            )
            result = evaluated
            applyShoppingResult(evaluated)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func checkBarcode(_ barcode: String) async {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isChecking = true
        statusMessage = ""
        defer { isChecking = false }

        do {
            let product = try await BarcodeLookupService.lookup(barcode: trimmed)
            let snapshot = ShoppingNutritionSnapshot(product: product, amount: product.defaultAmountG)
            let evaluated = ShoppingDietEvaluator.evaluate(
                snapshot: snapshot,
                source: "Barcode lookup",
                targets: targets,
                kidneyChecksEnabled: kidneyChecksEnabled,
                heartChecksEnabled: heartChecksEnabled
            )
            result = evaluated
            applyShoppingResult(evaluated)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func applyShoppingResult(_ result: ShoppingCheckResult) {
        foodName = result.snapshot.name
        quantity = result.snapshot.quantity
        calories = "\(result.snapshot.calories)"
        protein = format(result.snapshot.proteinG)
        carbs = format(result.snapshot.carbsG)
        fat = format(result.snapshot.fatG)
        fiber = format(result.snapshot.fiberG)
        sodium = format(result.snapshot.sodiumMg)
        potassium = format(result.snapshot.potassiumMg)
        phosphorus = format(result.snapshot.phosphorusMg)
        notes = result.snapshot.notes
    }

    private func updateRecommendationFromEditedFields(source: String) {
        let snapshot = ShoppingNutritionSnapshot(
            name: foodName.trimmingCharacters(in: .whitespacesAndNewlines),
            quantity: quantity.trimmingCharacters(in: .whitespacesAndNewlines),
            calories: Int(calories) ?? 0,
            proteinG: Double(protein) ?? 0,
            carbsG: Double(carbs) ?? 0,
            fatG: Double(fat) ?? 0,
            fiberG: Double(fiber) ?? 0,
            sodiumMg: Double(sodium) ?? 0,
            potassiumMg: Double(potassium) ?? 0,
            phosphorusMg: Double(phosphorus) ?? 0,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        result = ShoppingDietEvaluator.evaluate(
            snapshot: snapshot,
            source: source,
            targets: targets,
            kidneyChecksEnabled: kidneyChecksEnabled,
            heartChecksEnabled: heartChecksEnabled
        )
    }

    private func parsedTarget(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }
}

private struct ShoppingNutritionSnapshot {
    let name: String
    let quantity: String
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double
    let sodiumMg: Double
    let potassiumMg: Double
    let phosphorusMg: Double
    let notes: String

    init(
        name: String,
        quantity: String,
        calories: Int,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double,
        sodiumMg: Double,
        potassiumMg: Double,
        phosphorusMg: Double,
        notes: String
    ) {
        self.name = name
        self.quantity = quantity
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sodiumMg = sodiumMg
        self.potassiumMg = potassiumMg
        self.phosphorusMg = phosphorusMg
        self.notes = notes
    }

    init(nutritionResult: NutritionResult) {
        name = nutritionResult.foodName
        quantity = nutritionResult.estimatedQuantity
        calories = nutritionResult.calories
        proteinG = nutritionResult.proteinG
        carbsG = nutritionResult.carbsG
        fatG = nutritionResult.fatG
        fiberG = nutritionResult.fiberG
        sodiumMg = nutritionResult.sodiumMg
        potassiumMg = nutritionResult.potassiumMg
        phosphorusMg = nutritionResult.phosphorusMg
        notes = nutritionResult.notes
    }

    init(product: BarcodeProduct, amount: Double) {
        let multiplier = amount / 100
        name = product.displayName
        quantity = "\(format(amount)) g/ml"
        calories = Int((product.caloriesPer100G * multiplier).rounded())
        proteinG = product.proteinPer100G * multiplier
        carbsG = product.carbsPer100G * multiplier
        fatG = product.fatPer100G * multiplier
        fiberG = product.fiberPer100G * multiplier
        sodiumMg = product.sodiumPer100GMg * multiplier
        potassiumMg = product.potassiumPer100GMg * multiplier
        phosphorusMg = product.phosphorusPer100GMg * multiplier
        notes = product.servingSize.isEmpty ? "Barcode: \(product.barcode)" : "Serving: \(product.servingSize) | Barcode: \(product.barcode)"
    }
}

private struct ShoppingCheckResult {
    enum Recommendation {
        case buy
        case caution
        case avoid

        var title: String {
            switch self {
            case .buy: return "OK to buy"
            case .caution: return "Buy with caution"
            case .avoid: return "Not a good fit"
            }
        }

        var systemImage: String {
            switch self {
            case .buy: return "checkmark.circle.fill"
            case .caution: return "exclamationmark.triangle.fill"
            case .avoid: return "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .buy: return .green
            case .caution: return .orange
            case .avoid: return .red
            }
        }
    }

    let snapshot: ShoppingNutritionSnapshot
    let source: String
    let recommendation: Recommendation
    let warnings: [String]
    let positives: [String]
}

private enum ShoppingDietEvaluator {
    static func evaluate(
        snapshot: ShoppingNutritionSnapshot,
        source: String,
        targets: NutritionTargets,
        kidneyChecksEnabled: Bool,
        heartChecksEnabled: Bool
    ) -> ShoppingCheckResult {
        var warnings: [String] = []
        var positives: [String] = []
        var severity = 0

        evaluate(
            value: snapshot.sodiumMg,
            target: targets.sodiumMg,
            name: "sodium",
            cautionFraction: heartChecksEnabled ? 0.20 : 0.25,
            avoidFraction: heartChecksEnabled ? 0.35 : 0.45,
            unit: "mg",
            warnings: &warnings,
            severity: &severity
        )

        if kidneyChecksEnabled {
            evaluate(
                value: snapshot.potassiumMg,
                target: targets.potassiumMg,
                name: "potassium",
                cautionFraction: 0.25,
                avoidFraction: 0.40,
                unit: "mg",
                warnings: &warnings,
                severity: &severity
            )

            evaluate(
                value: snapshot.phosphorusMg,
                target: targets.phosphorusMg,
                name: "phosphorus",
                cautionFraction: 0.25,
                avoidFraction: 0.40,
                unit: "mg",
                warnings: &warnings,
                severity: &severity
            )

            if snapshot.proteinG > targets.proteinG * 0.40 {
                warnings.append("This serving uses a large share of the daily protein target.")
                severity = max(severity, 1)
            }
        }

        if heartChecksEnabled {
            if snapshot.fatG >= 20 {
                warnings.append("Fat is high for one serving. Check the label for saturated fat.")
                severity = max(severity, 1)
            }

            if snapshot.fiberG >= 5 {
                positives.append("Good fiber for heart health if potassium and phosphorus fit your plan.")
            }
        }

        if snapshot.sodiumMg <= targets.sodiumMg * 0.15 {
            positives.append("Sodium is relatively low for one serving.")
        }

        if kidneyChecksEnabled,
           (targets.potassiumMg == nil || snapshot.potassiumMg <= (targets.potassiumMg ?? .greatestFiniteMagnitude) * 0.20),
           (targets.phosphorusMg == nil || snapshot.phosphorusMg <= (targets.phosphorusMg ?? .greatestFiniteMagnitude) * 0.20) {
            positives.append("Potassium and phosphorus look reasonable for this serving.")
        }

        let recommendation: ShoppingCheckResult.Recommendation
        if severity >= 2 {
            recommendation = .avoid
        } else if severity == 1 || !warnings.isEmpty {
            recommendation = .caution
        } else {
            recommendation = .buy
        }

        return ShoppingCheckResult(
            snapshot: snapshot,
            source: source,
            recommendation: recommendation,
            warnings: warnings,
            positives: positives
        )
    }

    private static func evaluate(
        value: Double,
        target: Double?,
        name: String,
        cautionFraction: Double,
        avoidFraction: Double,
        unit: String,
        warnings: inout [String],
        severity: inout Int
    ) {
        guard let target, target > 0 else { return }

        let fraction = value / target
        if fraction >= avoidFraction {
            warnings.append("\(name.capitalized) is high: \(Int(value.rounded())) \(unit), about \(Int((fraction * 100).rounded()))% of the daily target.")
            severity = max(severity, 2)
        } else if fraction >= cautionFraction {
            warnings.append("\(name.capitalized) needs caution: \(Int(value.rounded())) \(unit), about \(Int((fraction * 100).rounded()))% of the daily target.")
            severity = max(severity, 1)
        }
    }
}

private struct ShoppingCheckResultCard: View {
    let result: ShoppingCheckResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: result.recommendation.systemImage)
                    .font(.title2)
                    .foregroundStyle(result.recommendation.tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.recommendation.title)
                        .font(.title2.bold())

                    Text(result.snapshot.name)
                        .font(.headline)

                    Text("\(result.source) | \(result.snapshot.quantity.isEmpty ? "serving estimate" : result.snapshot.quantity)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ShoppingMetricTile(title: "Calories", value: "\(result.snapshot.calories)", tint: .green)
                ShoppingMetricTile(title: "Protein", value: "\(Int(result.snapshot.proteinG.rounded())) g", tint: .blue)
                ShoppingMetricTile(title: "Sodium", value: "\(Int(result.snapshot.sodiumMg.rounded())) mg", tint: .orange)
                ShoppingMetricTile(title: "Potassium", value: "\(Int(result.snapshot.potassiumMg.rounded())) mg", tint: .yellow)
                ShoppingMetricTile(title: "Phosphorus", value: "\(Int(result.snapshot.phosphorusMg.rounded())) mg", tint: .purple)
                ShoppingMetricTile(title: "Fiber", value: "\(Int(result.snapshot.fiberG.rounded())) g", tint: .teal)
            }

            if !result.warnings.isEmpty {
                ShoppingMessageGroup(title: "Warnings", systemImage: "exclamationmark.triangle.fill", tint: .orange, messages: result.warnings)
            }

            if !result.positives.isEmpty {
                ShoppingMessageGroup(title: "Why it may fit", systemImage: "checkmark.circle.fill", tint: .green, messages: result.positives)
            }

            if !result.snapshot.notes.isEmpty {
                Text(result.snapshot.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(result.recommendation.tint, lineWidth: 3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ShoppingMetricTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundStyle(tint)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ShoppingMessageGroup: View {
    let title: String
    let systemImage: String
    let tint: Color
    let messages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)

            ForEach(messages, id: \.self) { message in
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
        }
    }
}

private struct ShoppingEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ready to check a food", systemImage: "cart.fill")
                .font(.headline)

            Text("Use a barcode for packaged food, or take a photo when there is no barcode. Results use your current kidney and heart settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SettingsView: View {
    var onDone: () -> Void = {}
    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var entries: [FoodEntry]
    @AppStorage("anthropicAPIKey") private var anthropicAPIKey = ""
    @AppStorage("anthropicModelID") private var anthropicModelID = AnthropicModel.defaultModel.id
    @AppStorage("geminiAPIKey") private var geminiAPIKey = ""
    @AppStorage("geminiModelID") private var geminiModelID = GeminiModel.defaultModel.id
    @AppStorage("openAIAPIKey") private var openAIAPIKey = ""
    @AppStorage("openAIModelID") private var openAIModelID = OpenAIModel.defaultModel.id
    @AppStorage("openRouterAPIKey") private var openRouterAPIKey = ""
    @AppStorage("openRouterModelID") private var openRouterModelID = OpenRouterModel.freeRouter.id
    @AppStorage("aiProvider") private var aiProviderRaw = AIProvider.cloudflare.rawValue
    @AppStorage("kidneyChecksEnabled") private var kidneyChecksEnabled = true
    @AppStorage("heartChecksEnabled") private var heartChecksEnabled = true
    @AppStorage("userSex") private var userSex = UserSex.preferNotToSay.rawValue
    @AppStorage("userAge") private var userAge = ""
    @AppStorage("userHeightCm") private var userHeightCm = ""
    @AppStorage("userWeightKg") private var userWeightKg = ""
    @AppStorage("ckdStage") private var ckdStageRaw = CKDStage.notSpecified.rawValue
    @AppStorage("proteinTargetG") private var proteinTargetG = ""
    @AppStorage("sodiumTargetMg") private var sodiumTargetMg = ""
    @AppStorage("potassiumTargetMg") private var potassiumTargetMg = ""
    @AppStorage("phosphorusTargetMg") private var phosphorusTargetMg = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("showTodayProgressRings") private var showTodayProgressRings = true
    @AppStorage("showTodayNutritionBarGraph") private var showTodayNutritionBarGraph = true

    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKitManager
    @State private var showAnthropicKey = false
    @State private var showGeminiKey = false
    @State private var showOpenAIKey = false
    @State private var showOpenRouterKey = false

    @FocusState private var focusedField: SettingsField?
    @State private var geminiModels: [GeminiModel] = GeminiModel.defaults
    @State private var openAIModels: [OpenAIModel] = OpenAIModel.defaults
    @State private var openRouterModels: [OpenRouterModel] = OpenRouterModel.recommended
    @State private var isLoadingGeminiModels = false
    @State private var isLoadingOpenAIModels = false
    @State private var isLoadingModels = false
    @State private var geminiError = ""
    @State private var openAIError = ""
    @State private var openRouterError = ""
    @State private var showResetConfirmation = false
    @State private var resetStatus = ""
    private var selectedProvider: AIProvider {
        AIProvider(rawValue: aiProviderRaw) ?? .cloudflare
    }

    private var selectedOpenRouterModel: OpenRouterModel? {
        openRouterModels.first(where: { $0.id == openRouterModelID })
    }

    private var selectedCKDStage: CKDStage {
        CKDStage(rawValue: ckdStageRaw) ?? .notSpecified
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("AI Analysis") {
                    Picker("Provider", selection: $aiProviderRaw) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }

                    if selectedProvider == .anthropic {
                        APIKeyField(
                            title: "Anthropic API Key",
                            text: $anthropicAPIKey,
                            isVisible: $showAnthropicKey,
                            focusedField: $focusedField,
                            field: .anthropicKey,
                            onSubmit: dismissKeyboard
                        )

                        Text("Uses Anthropic's Messages API for food photo and text analysis.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text(anthropicAPIKey.isEmpty ? "No Anthropic API key saved." : "Anthropic API key saved.")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(anthropicAPIKey.isEmpty ? .secondary : .green)

                        Picker("Claude Model", selection: $anthropicModelID) {
                            ForEach(AnthropicModel.defaults) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                    } else if selectedProvider == .gemini {
                        APIKeyField(
                            title: "Google Gemini API Key",
                            text: $geminiAPIKey,
                            isVisible: $showGeminiKey,
                            focusedField: $focusedField,
                            field: .geminiKey,
                            onSubmit: dismissKeyboard
                        )

                        Button(isLoadingGeminiModels ? "Loading Models..." : "Refresh Gemini Models") {
                            Task { await loadGeminiModels() }
                        }
                        .disabled(geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingGeminiModels)

                        if isLoadingGeminiModels {
                            ProgressView()
                        }

                        Picker("Gemini Model", selection: $geminiModelID) {
                            ForEach(geminiModels) { model in
                                Text("\(model.displayName) • Vision").tag(model.id)
                            }
                        }

                        if !geminiError.isEmpty {
                            Text(geminiError)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }

                        Text("Uses Google's Gemini generateContent API. Refresh only shows models expected to support food photo analysis.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text(geminiAPIKey.isEmpty ? "No Gemini API key saved." : "Gemini API key saved.")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(geminiAPIKey.isEmpty ? .secondary : .green)
                    } else if selectedProvider == .openAI {
                        APIKeyField(
                            title: "OpenAI API Key",
                            text: $openAIAPIKey,
                            isVisible: $showOpenAIKey,
                            focusedField: $focusedField,
                            field: .openAIKey,
                            onSubmit: dismissKeyboard
                        )

                        Button(isLoadingOpenAIModels ? "Loading Models..." : "Refresh OpenAI Models") {
                            Task { await loadOpenAIModels() }
                        }
                        .disabled(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingOpenAIModels)

                        if isLoadingOpenAIModels {
                            ProgressView()
                        }

                        Picker("OpenAI Model", selection: $openAIModelID) {
                            ForEach(openAIModels) { model in
                                Text("\(model.displayName) • Vision").tag(model.id)
                            }
                        }

                        if !openAIError.isEmpty {
                            Text(openAIError)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }

                        Text("Uses OpenAI's Chat Completions API. Refresh only shows models expected to support image inputs.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text(openAIAPIKey.isEmpty ? "No OpenAI API key saved." : "OpenAI API key saved.")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(openAIAPIKey.isEmpty ? .secondary : .green)
                    } else if selectedProvider == .openRouter {
                        APIKeyField(
                            title: "OpenRouter API Key",
                            text: $openRouterAPIKey,
                            isVisible: $showOpenRouterKey,
                            focusedField: $focusedField,
                            field: .openRouterKey,
                            onSubmit: dismissKeyboard
                        )

                        Button(isLoadingModels ? "Loading Models..." : "Refresh OpenRouter Models") {
                            Task { await loadOpenRouterModels() }
                        }
                        .disabled(openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingModels)

                        if isLoadingModels {
                            ProgressView()
                        }

                        Picker("OpenRouter Model", selection: $openRouterModelID) {
                            ForEach(openRouterModels) { model in
                                Text(openRouterPickerLabel(for: model)).tag(model.id)
                            }
                        }

                        if let selectedOpenRouterModel, !selectedOpenRouterModel.supportsVision {
                            Text("This model appears to be text-only. It may fail on food photo analysis, but can still work for text meal descriptions.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }

                        if !openRouterError.isEmpty {
                            Text(openRouterError)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }

                        Text("Uses OpenRouter's chat completions API. Vision-capable models are marked for food photo analysis, and text-only models are still available for manual meal descriptions.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text(openRouterAPIKey.isEmpty ? "No OpenRouter API key saved." : "OpenRouter API key saved.")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(openRouterAPIKey.isEmpty ? .secondary : .green)
                    } else {
                        Label("Built-in MealVue AI is enabled.", systemImage: "sparkles")
                            .foregroundStyle(.green)

                        Text("Uses Cloudflare Workers AI through the MealVue backend. Testers do not need to enter AI API keys.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                }

                Section("Health Checks") {
                    Toggle("Kidney Health Checker", isOn: $kidneyChecksEnabled)
                    Toggle("Heart Health Checker", isOn: $heartChecksEnabled)

                    Text("Turn these checks on or off for AI warnings and guide content.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Today Screen") {
                    Toggle("Show Progress Rings", isOn: $showTodayProgressRings)
                    Toggle("Show Nutrition Bar Graph", isOn: $showTodayNutritionBarGraph)

                    Text("Use these controls to simplify the Today tab during testing or for users who prefer fewer visual summaries.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Profile") {
                    Picker("Sex", selection: $userSex) {
                        ForEach(UserSex.allCases) { sex in
                            Text(sex.rawValue).tag(sex.rawValue)
                        }
                    }

                    TextField("Age", text: $userAge)
                        .keyboardType(.numberPad)
                    TextField("Height (cm)", text: $userHeightCm)
                        .keyboardType(.decimalPad)
                    TextField("Weight (kg)", text: $userWeightKg)
                        .keyboardType(.decimalPad)

                    Picker("CKD Stage", selection: $ckdStageRaw) {
                        ForEach(CKDStage.allCases) { stage in
                            Text(stage.displayName).tag(stage.rawValue)
                        }
                    }

                    Text("These profile details are stored for context. Kidney sodium, potassium, and phosphorus targets are usually based more on CKD stage, lab results, dialysis status, and clinician guidance than on age, sex, height, or weight alone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Daily Targets") {
                    TextField("Protein target (g/day)", text: $proteinTargetG)
                        .keyboardType(.decimalPad)
                    TextField("Sodium target (mg/day)", text: $sodiumTargetMg)
                        .keyboardType(.numberPad)
                    TextField("Potassium target (mg/day)", text: $potassiumTargetMg)
                        .keyboardType(.numberPad)
                    TextField("Phosphorus target (mg/day)", text: $phosphorusTargetMg)
                        .keyboardType(.numberPad)

                    Button("Reset Targets To Recommended Defaults") {
                        proteinTargetG = recommendedProteinTargetText
                        sodiumTargetMg = String(Int(RecommendedTargets.defaultSodiumMg(heartChecksEnabled: heartChecksEnabled)))
                        potassiumTargetMg = kidneyChecksEnabled ? String(Int(RecommendedTargets.defaultPotassiumMg(for: selectedCKDStage))) : ""
                        phosphorusTargetMg = kidneyChecksEnabled ? String(Int(RecommendedTargets.defaultPhosphorusMg(for: selectedCKDStage))) : ""
                    }

                    Text(recommendedTargetSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About This App") {
                    Label("MealVue food logging with photo capture", systemImage: "camera.fill")
                    Label("Manual and AI-assisted nutrition entry", systemImage: "square.and.pencil")
                    Label("Kidney and heart health guidance", systemImage: "heart.text.square.fill")
                }

                Section("Data") {
                    Button {
                        hasCompletedOnboarding = false
                    } label: {
                        Label("Show Onboarding Again", systemImage: "questionmark.circle")
                    }

                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("Erase All MealVue Data From iCloud", systemImage: "trash")
                    }
                    .disabled(entries.isEmpty)

                    Text("Deletes MealVue meal records from this device and from iCloud-synced MealVue data on your other devices.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !resetStatus.isEmpty {
                        Text(resetStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Safety") {
                    Text("This app is for reference and self-tracking only.")
                    Text("Kidney diets and medication decisions should be personalized with a clinician, renal dietitian, or pharmacist.")
                }
            }
            .navigationTitle("MealVue Settings")
            .scrollDismissesKeyboard(.interactively)
            .task(id: aiProviderRaw) {
                if selectedProvider == .gemini, geminiModels.count <= GeminiModel.defaults.count, !geminiAPIKey.isEmpty {
                    await loadGeminiModels()
                }

                if selectedProvider == .openAI, openAIModels.count <= OpenAIModel.defaults.count, !openAIAPIKey.isEmpty {
                    await loadOpenAIModels()
                }

                guard selectedProvider == .openRouter, openRouterModels.count <= OpenRouterModel.recommended.count, !openRouterAPIKey.isEmpty else { return }
                await loadOpenRouterModels()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        finishSettings()
                    }
                    .fontWeight(.semibold)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done Typing") {
                        finishSettings()
                    }
                }
            }
            .confirmationDialog(
                "Erase all MealVue meal data?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Erase MealVue iCloud Data", role: .destructive) {
                    resetMealData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes MealVue meal records from this device and from iCloud-synced MealVue data on your other devices. It also attempts to remove matching MealVue nutrition entries from Apple Health.")
            }
        }
    }

    private func resetMealData() {
        let entriesToDelete = entries
        let entryIDs = entriesToDelete.map(\.entryId)
        let count = entriesToDelete.count

        for entry in entriesToDelete {
            modelContext.delete(entry)
        }

        do {
            try modelContext.save()
        } catch {
            resetStatus = "Could not erase MealVue data: \(error.localizedDescription)"
            return
        }

        resetStatus = "Erased \(count) MealVue meal records. Cleaning Apple Health exports..."

        Task {
            for entryID in entryIDs {
                try? await healthKitManager.deleteExportedMeal(entryID: entryID)
            }

            resetStatus = "Erased \(count) MealVue meal records and requested Apple Health cleanup."
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
    }

    private func finishSettings() {
        focusedField = nil
        onDone()
    }

    private func loadOpenRouterModels() async {
        let key = openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            openRouterModels = OpenRouterModel.recommended
            openRouterError = ""
            return
        }

        isLoadingModels = true
        defer { isLoadingModels = false }

        do {
            let fetched = try await ClaudeService.fetchOpenRouterModels(apiKey: key)
            openRouterModels = fetched.isEmpty ? OpenRouterModel.recommended : fetched

            if !openRouterModels.contains(where: { $0.id == openRouterModelID }) {
                openRouterModelID = openRouterModels.first?.id ?? OpenRouterModel.freeRouter.id
            }

            openRouterError = fetched.isEmpty ? "No OpenRouter models were returned for this key. Auto Router and Free Router are still available." : ""
        } catch {
            openRouterModels = OpenRouterModel.recommended
            openRouterModelID = OpenRouterModel.freeRouter.id
            openRouterError = error.localizedDescription
        }
    }

    private func openRouterPickerLabel(for model: OpenRouterModel) -> String {
        if model.isRouter {
            return model.displayName
        }

        if model.supportsVision {
            return "\(model.displayName) • Vision"
        }

        return "\(model.displayName) • Text Only"
    }

    private func loadGeminiModels() async {
        let key = geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            geminiModels = GeminiModel.defaults
            geminiError = ""
            return
        }

        isLoadingGeminiModels = true
        defer { isLoadingGeminiModels = false }

        do {
            let fetched = try await ClaudeService.fetchGeminiModels(apiKey: key)
            geminiModels = fetched.isEmpty ? GeminiModel.defaults : fetched

            if GeminiModel.shouldResetSelection(geminiModelID) || !geminiModels.contains(where: { $0.id == geminiModelID }) {
                geminiModelID = geminiModels.first?.id ?? GeminiModel.defaultModel.id
            }

            geminiError = fetched.isEmpty ? "No Gemini vision-compatible generateContent models were returned. Falling back to defaults." : ""
        } catch {
            geminiModels = GeminiModel.defaults
            geminiModelID = GeminiModel.defaultModel.id
            geminiError = error.localizedDescription
        }
    }

    private func loadOpenAIModels() async {
        let key = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            openAIModels = OpenAIModel.defaults
            openAIError = ""
            return
        }

        isLoadingOpenAIModels = true
        defer { isLoadingOpenAIModels = false }

        do {
            let fetched = try await ClaudeService.fetchOpenAIModels(apiKey: key)
            openAIModels = fetched.isEmpty ? OpenAIModel.defaults : fetched

            if !openAIModels.contains(where: { $0.id == openAIModelID }) {
                openAIModelID = openAIModels.first?.id ?? OpenAIModel.defaultModel.id
            }

            openAIError = fetched.isEmpty ? "No compatible OpenAI chat models were returned. Falling back to defaults." : ""
        } catch {
            openAIModels = OpenAIModel.defaults
            openAIModelID = OpenAIModel.defaultModel.id
            openAIError = error.localizedDescription
        }
    }

    private var recommendedTargetSummary: String {
        var parts: [String] = [
            "Suggested protein target: \(recommendedProteinTargetText) g/day.",
            "Suggested sodium target: \(Int(RecommendedTargets.defaultSodiumMg(heartChecksEnabled: heartChecksEnabled))) mg/day."
        ]

        if kidneyChecksEnabled {
            parts.append("Suggested potassium target: \(Int(RecommendedTargets.defaultPotassiumMg(for: selectedCKDStage))) mg/day.")
            parts.append("Suggested phosphorus target: \(Int(RecommendedTargets.defaultPhosphorusMg(for: selectedCKDStage))) mg/day.")
        } else {
            parts.append("Potassium and phosphorus are tracked, but no kidney-specific limit is applied unless you enter one or turn on the kidney checker.")
        }

        return parts.joined(separator: " ")
    }

    private var recommendedProteinTargetText: String {
        let weight = Double(userWeightKg.trimmingCharacters(in: .whitespacesAndNewlines))
        let grams = RecommendedTargets.defaultProteinG(for: selectedCKDStage, weightKg: weight)
        return String(Int(grams.rounded()))
    }
}

private enum SettingsField: Hashable {
    case anthropicKey
    case geminiKey
    case openAIKey
    case openRouterKey
}

private enum UserSex: String, CaseIterable, Identifiable {
    case female = "Female"
    case male = "Male"
    case intersex = "Intersex"
    case preferNotToSay = "Prefer Not To Say"

    var id: String { rawValue }
}

private enum CKDStage: String, CaseIterable, Identifiable {
    case notSpecified = "Not Specified"
    case stage1 = "Stage 1"
    case stage2 = "Stage 2"
    case stage3a = "Stage 3a"
    case stage3b = "Stage 3b"
    case stage4 = "Stage 4"
    case stage3to4 = "Stages 3-4"
    case stage5NotDialysis = "Stage 5 Not On Dialysis"
    case dialysis = "Dialysis"

    static let allCases: [CKDStage] = [
        .notSpecified,
        .stage1,
        .stage2,
        .stage3a,
        .stage3b,
        .stage4,
        .stage5NotDialysis,
        .dialysis
    ]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stage3to4:
            return "Stages 3-4 (Legacy)"
        default:
            return rawValue
        }
    }
}

private struct APIKeyField: View {
    let title: String
    @Binding var text: String
    @Binding var isVisible: Bool
    @FocusState.Binding var focusedField: SettingsField?
    let field: SettingsField
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isVisible {
                    TextField(title, text: $text)
                        .onSubmit { onSubmit?() }
                } else {
                    SecureField(title, text: $text)
                        .onSubmit { onSubmit?() }
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: field)
            .submitLabel(.done)

            Button(isVisible ? "Hide" : "View") {
                isVisible.toggle()
            }
            .font(.footnote.weight(.semibold))
        }
    }
}

private struct FoodEntryRow: View {
    let entry: FoodEntry
    @AppStorage("kidneyChecksEnabled") private var kidneyChecksEnabled = true

    var body: some View {
        HStack(spacing: 12) {
            if let image = entry.uiImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.foodName)
                        .font(.headline)
                    Spacer()
                    Text("\(entry.calories) kcal")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }

                if !entry.estimatedQuantity.isEmpty {
                    Text(entry.estimatedQuantity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    MacroChip(label: "P", value: entry.proteinG, tint: .blue)
                    MacroChip(label: "C", value: entry.carbsG, tint: .green)
                    MacroChip(label: "F", value: entry.fatG, tint: .orange)
                    MacroChip(label: "Fi", value: entry.fiberG, tint: .purple)
                }

                if kidneyChecksEnabled && !entry.kidneyWarning.isEmpty {
                    Label(entry.kidneyWarning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FoodEntryDetailView: View {
    let entry: FoodEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKitManager
    @AppStorage("kidneyChecksEnabled") private var kidneyChecksEnabled = true
    @State private var showEditor = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            if let image = entry.uiImage {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }

            Section("Meal") {
                detailRow("Food", value: entry.foodName)
                detailRow("Quantity", value: entry.estimatedQuantity.isEmpty ? "Not provided" : entry.estimatedQuantity)
                detailRow("Logged", value: entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                detailRow("AI confidence", value: entry.confidence.capitalized)
            }

            Section("Nutrition") {
                detailRow("Calories", value: "\(entry.calories)")
                detailRow("Protein", value: "\(Int(entry.proteinG)) g")
                detailRow("Carbs", value: "\(Int(entry.carbsG)) g")
                detailRow("Fat", value: "\(Int(entry.fatG)) g")
                detailRow("Fiber", value: "\(Int(entry.fiberG)) g")
                detailRow("Sodium", value: "\(Int(entry.sodiumMg)) mg")
                detailRow("Potassium", value: "\(Int(entry.potassiumMg)) mg")
                detailRow("Phosphorus", value: "\(Int(entry.phosphorusMg)) mg")
            }

            Section("Health Notes") {
                if kidneyChecksEnabled {
                    Text(entry.kidneyWarning.isEmpty ? "No kidney warning entered." : entry.kidneyWarning)
                } else {
                    Text("Kidney health checker is turned off.")
                }

                if !entry.aiNotes.isEmpty {
                    Text(entry.aiNotes)
                        .foregroundStyle(.secondary)
                }

                if !entry.notes.isEmpty {
                    Text(entry.notes)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(entry.foodName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEditor = true
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            HistoricalMealEditView(entry: entry)
        }
        .confirmationDialog(
            "Delete this meal?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Meal", role: .destructive) {
                deleteEntry()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the MealVue history item and attempts to remove the matching Apple Health nutrition export.")
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func deleteEntry() {
        let entryID = entry.entryId
        modelContext.delete(entry)

        Task {
            try? await healthKitManager.deleteExportedMeal(entryID: entryID)
        }

        dismiss()
    }
}

private struct HistoricalMealEditView: View {
    let entry: FoodEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKitManager
    @AppStorage("kidneyChecksEnabled") private var kidneyChecksEnabled = true
    @AppStorage("heartChecksEnabled") private var heartChecksEnabled = true

    @State private var foodName = ""
    @State private var quantity = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""
    @State private var sodium = ""
    @State private var potassium = ""
    @State private var phosphorus = ""
    @State private var notes = ""
    @State private var kidneyWarning = ""
    @State private var heartWarning = ""
    @State private var sodiumWarning = ""
    @State private var potassiumWarning = ""
    @State private var phosphorusWarning = ""
    @State private var confidence = "manual"
    @State private var providerUsed = ""
    @State private var modelUsed = ""
    @State private var isRedoingAI = false
    @State private var errorMessage = ""
    @State private var didLoadEntry = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let image = entry.uiImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .padding(.horizontal)
                    }

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.red.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal)
                    }

                    Button {
                        Task { await redoAI() }
                    } label: {
                        if isRedoingAI {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Redo AI Analysis", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRedoingAI || !Config.isConfigured)
                    .padding(.horizontal)

                    Text(entry.uiImage == nil ? "AI Redo will analyze the current food name and quantity." : "AI Redo will re-analyze the saved photo using the current food name and quantity as correction text.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    MealEditor(
                        foodName: $foodName,
                        quantity: $quantity,
                        calories: $calories,
                        protein: $protein,
                        carbs: $carbs,
                        fat: $fat,
                        fiber: $fiber,
                        sodium: $sodium,
                        potassium: $potassium,
                        phosphorus: $phosphorus,
                        notes: $notes
                    )
                }
                .padding(.vertical)
            }
            .navigationTitle("Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                }
            }
            .onAppear(perform: loadEntryIfNeeded)
        }
    }

    private func loadEntryIfNeeded() {
        guard !didLoadEntry else { return }
        didLoadEntry = true

        foodName = entry.foodName
        quantity = entry.estimatedQuantity
        calories = "\(entry.calories)"
        protein = format(entry.proteinG)
        carbs = format(entry.carbsG)
        fat = format(entry.fatG)
        fiber = format(entry.fiberG)
        sodium = format(entry.sodiumMg)
        potassium = format(entry.potassiumMg)
        phosphorus = format(entry.phosphorusMg)
        notes = entry.notes
        kidneyWarning = entry.kidneyWarning
        confidence = entry.confidence
    }

    private func redoAI() async {
        guard Config.isConfigured else {
            errorMessage = "MealVue AI is not available. Check AI settings and try again."
            return
        }

        isRedoingAI = true
        errorMessage = ""
        defer { isRedoingAI = false }

        do {
            let result: NutritionResult
            if let image = entry.uiImage {
                result = try await ClaudeService.analyzeFood(image: image, correctedDescription: correctedDescription)
            } else {
                result = try await ClaudeService.analyzeText(description: correctedDescription)
            }
            apply(result: result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var correctedDescription: String {
        let trimmedFoodName = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuantity = quantity.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedFoodName.isEmpty {
            return trimmedQuantity.isEmpty ? entry.foodName : trimmedQuantity
        }

        if trimmedQuantity.isEmpty {
            return trimmedFoodName
        }

        return "\(trimmedQuantity) of \(trimmedFoodName)"
    }

    private func apply(result: NutritionResult) {
        foodName = result.foodName
        quantity = result.estimatedQuantity
        calories = "\(result.calories)"
        protein = format(result.proteinG)
        carbs = format(result.carbsG)
        fat = format(result.fatG)
        fiber = format(result.fiberG)
        sodium = format(result.sodiumMg)
        potassium = format(result.potassiumMg)
        phosphorus = format(result.phosphorusMg)
        notes = result.notes
        kidneyWarning = Config.kidneyChecksEnabled ? result.kidneyWarning : ""
        heartWarning = Config.heartChecksEnabled ? result.heartWarning : ""
        sodiumWarning = (Config.kidneyChecksEnabled || Config.heartChecksEnabled) ? result.sodiumWarning : ""
        potassiumWarning = (Config.kidneyChecksEnabled || Config.heartChecksEnabled) ? result.potassiumWarning : ""
        phosphorusWarning = (Config.kidneyChecksEnabled || Config.heartChecksEnabled) ? result.phosphorusWarning : ""
        confidence = result.confidence
        providerUsed = result.providerName
        modelUsed = result.modelUsed
    }

    private func save() {
        entry.foodName = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.estimatedQuantity = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.calories = Int(calories) ?? 0
        entry.proteinG = Double(protein) ?? 0
        entry.carbsG = Double(carbs) ?? 0
        entry.fatG = Double(fat) ?? 0
        entry.fiberG = Double(fiber) ?? 0
        entry.sodiumMg = Double(sodium) ?? 0
        entry.potassiumMg = Double(potassium) ?? 0
        entry.phosphorusMg = Double(phosphorus) ?? 0
        entry.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.kidneyWarning = kidneyChecksEnabled ? kidneyWarning.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        entry.confidence = confidence

        if !providerUsed.isEmpty || !modelUsed.isEmpty {
            entry.aiNotes = combinedAINotes(
                baseNotes: notes,
                heartWarning: heartChecksEnabled ? heartWarning : "",
                sodiumWarning: (kidneyChecksEnabled || heartChecksEnabled) ? sodiumWarning : "",
                potassiumWarning: (kidneyChecksEnabled || heartChecksEnabled) ? potassiumWarning : "",
                phosphorusWarning: (kidneyChecksEnabled || heartChecksEnabled) ? phosphorusWarning : "",
                provider: providerUsed,
                model: modelUsed
            )
        }

        do {
            try modelContext.save()
        } catch {
            errorMessage = "MealVue could not save this meal. Try again."
            return
        }

        Task {
            try? await healthKitManager.deleteExportedMeal(entryID: entry.entryId)
            try? await healthKitManager.save(entry: entry)
        }

        dismiss()
    }
}

private struct BarcodeProduct: Identifiable {
    let barcode: String
    let name: String
    let brand: String
    let packageQuantity: String
    let servingSize: String
    let servingQuantityG: Double?
    let caloriesPer100G: Double
    let proteinPer100G: Double
    let carbsPer100G: Double
    let fatPer100G: Double
    let fiberPer100G: Double
    let sodiumPer100GMg: Double
    let potassiumPer100GMg: Double
    let phosphorusPer100GMg: Double

    var id: String { barcode }

    var displayName: String {
        if brand.isEmpty { return name }
        return "\(name) - \(brand)"
    }

    var defaultAmountG: Double {
        servingQuantityG ?? 100
    }
}

private struct BarcodeScannerView: View {
    var onBarcode: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var manualBarcode = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                #if targetEnvironment(simulator)
                manualEntry
                #else
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    LiveBarcodeScanner(onBarcode: onBarcode)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding()
                } else {
                    manualEntry
                }
                #endif
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var manualEntry: some View {
        VStack(spacing: 16) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            TextField("Barcode number", text: $manualBarcode)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)

            Button("Look Up Product") {
                onBarcode(manualBarcode)
            }
            .buttonStyle(.borderedProminent)
            .disabled(manualBarcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(24)
    }
}

private struct LiveBarcodeScanner: UIViewControllerRepresentable {
    var onBarcode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        try? uiViewController.startScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onBarcode: onBarcode)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private var didScan = false
        private let onBarcode: (String) -> Void

        init(onBarcode: @escaping (String) -> Void) {
            self.onBarcode = onBarcode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle(item)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard let item = addedItems.first else { return }
            handle(item)
        }

        private func handle(_ item: RecognizedItem) {
            guard !didScan else { return }
            guard case .barcode(let barcode) = item,
                  let payload = barcode.payloadStringValue,
                  !payload.isEmpty else { return }

            didScan = true
            onBarcode(payload)
        }
    }
}

private struct BarcodeProductEntryView: View {
    let product: BarcodeProduct
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKitManager
    @AppStorage("kidneyChecksEnabled") private var kidneyChecksEnabled = true
    @AppStorage("heartChecksEnabled") private var heartChecksEnabled = true

    @State private var amountG: String
    @State private var foodName = ""
    @State private var quantity = ""
    @State private var caloriesText = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""
    @State private var sodium = ""
    @State private var potassium = ""
    @State private var phosphorus = ""
    @State private var notes = ""
    @State private var kidneyWarning = ""
    @State private var heartWarning = ""
    @State private var sodiumWarning = ""
    @State private var potassiumWarning = ""
    @State private var phosphorusWarning = ""
    @State private var confidence = "barcode"
    @State private var providerUsed = ""
    @State private var modelUsed = ""
    @State private var isRedoingAI = false
    @State private var errorMessage = ""
    @State private var didInitialize = false

    init(product: BarcodeProduct, onSave: @escaping () -> Void) {
        self.product = product
        self.onSave = onSave
        _amountG = State(initialValue: format(product.defaultAmountG))
    }

    private var amount: Double {
        max(Double(amountG) ?? product.defaultAmountG, 0)
    }

    private var multiplier: Double {
        amount / 100
    }

    private var calories: Int {
        Int((product.caloriesPer100G * multiplier).rounded())
    }

    private var amountPresets: [(String, Double)] {
        var presets: [(String, Double)] = [("100 g/ml", 100)]

        if let serving = product.servingQuantityG, serving > 0 {
            presets.insert(("1 serving", serving), at: 0)
            presets.append(("2 servings", serving * 2))
        }

        presets.append(("Half pack", 50))
        return presets
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(product.displayName)
                        .font(.headline)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        if !product.packageQuantity.isEmpty {
                            LabeledContent("Package", value: product.packageQuantity)
                        }

                        if !product.servingSize.isEmpty {
                            LabeledContent("Listed serving", value: product.servingSize)
                        }

                        LabeledContent("Barcode", value: product.barcode)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal)

                    GroupBox("Amount") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                TextField("Amount", text: $amountG)
                                    .keyboardType(.decimalPad)
                                Text("g or ml")
                                    .foregroundStyle(.secondary)
                            }

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 8) {
                                ForEach(amountPresets, id: \.0) { label, amount in
                                    Button(label) {
                                        amountG = format(amount)
                                        updateFieldsFromBarcode()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal)
                    }

                    Button {
                        Task { await redoAI() }
                    } label: {
                        if isRedoingAI {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Redo AI Analysis", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRedoingAI || !Config.isConfigured)
                    .padding(.horizontal)

                    MealEditor(
                        foodName: $foodName,
                        quantity: $quantity,
                        calories: $caloriesText,
                        protein: $protein,
                        carbs: $carbs,
                        fat: $fat,
                        fiber: $fiber,
                        sodium: $sodium,
                        potassium: $potassium,
                        phosphorus: $phosphorus,
                        notes: $notes
                    )
                }
                .padding(.vertical)
            }
            .navigationTitle("Barcode Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                        .disabled(amount <= 0)
                }
            }
            .onAppear(perform: initializeIfNeeded)
            .onChange(of: amountG) { _, _ in
                updateFieldsFromBarcode()
            }
        }
    }

    private func initializeIfNeeded() {
        guard !didInitialize else { return }
        didInitialize = true
        foodName = product.displayName
        notes = "Barcode: \(product.barcode). Nutrition data from Open Food Facts. Review label values before relying on totals."
        updateFieldsFromBarcode()
    }

    private func updateFieldsFromBarcode() {
        quantity = "\(format(amount)) g/ml"
        caloriesText = "\(calories)"
        protein = format(product.proteinPer100G * multiplier)
        carbs = format(product.carbsPer100G * multiplier)
        fat = format(product.fatPer100G * multiplier)
        fiber = format(product.fiberPer100G * multiplier)
        sodium = format(product.sodiumPer100GMg * multiplier)
        potassium = format(product.potassiumPer100GMg * multiplier)
        phosphorus = format(product.phosphorusPer100GMg * multiplier)
        kidneyWarning = kidneyChecksEnabled ? barcodeKidneyWarning : ""
    }

    private func redoAI() async {
        guard Config.isConfigured else {
            errorMessage = "MealVue AI is not available. Check AI settings and try again."
            return
        }

        isRedoingAI = true
        errorMessage = ""
        defer { isRedoingAI = false }

        do {
            let result = try await ClaudeService.analyzeText(description: "\(quantity) of \(foodName)")
            foodName = result.foodName
            quantity = result.estimatedQuantity
            caloriesText = "\(result.calories)"
            protein = format(result.proteinG)
            carbs = format(result.carbsG)
            fat = format(result.fatG)
            fiber = format(result.fiberG)
            sodium = format(result.sodiumMg)
            potassium = format(result.potassiumMg)
            phosphorus = format(result.phosphorusMg)
            notes = result.notes
            kidneyWarning = Config.kidneyChecksEnabled ? result.kidneyWarning : ""
            heartWarning = Config.heartChecksEnabled ? result.heartWarning : ""
            sodiumWarning = (Config.kidneyChecksEnabled || Config.heartChecksEnabled) ? result.sodiumWarning : ""
            potassiumWarning = (Config.kidneyChecksEnabled || Config.heartChecksEnabled) ? result.potassiumWarning : ""
            phosphorusWarning = (Config.kidneyChecksEnabled || Config.heartChecksEnabled) ? result.phosphorusWarning : ""
            confidence = result.confidence
            providerUsed = result.providerName
            modelUsed = result.modelUsed
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        let entry = FoodEntry(
            foodName: foodName.trimmingCharacters(in: .whitespacesAndNewlines),
            estimatedQuantity: quantity.trimmingCharacters(in: .whitespacesAndNewlines),
            calories: Int(caloriesText) ?? 0,
            proteinG: Double(protein) ?? 0,
            carbsG: Double(carbs) ?? 0,
            fatG: Double(fat) ?? 0,
            fiberG: Double(fiber) ?? 0,
            sodiumMg: Double(sodium) ?? 0,
            potassiumMg: Double(potassium) ?? 0,
            phosphorusMg: Double(phosphorus) ?? 0,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            kidneyWarning: kidneyChecksEnabled ? kidneyWarning.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            confidence: confidence,
            aiNotes: combinedAINotes(
                baseNotes: notes,
                heartWarning: heartChecksEnabled ? heartWarning : "",
                sodiumWarning: (kidneyChecksEnabled || heartChecksEnabled) ? sodiumWarning : "",
                potassiumWarning: (kidneyChecksEnabled || heartChecksEnabled) ? potassiumWarning : "",
                phosphorusWarning: (kidneyChecksEnabled || heartChecksEnabled) ? phosphorusWarning : "",
                provider: providerUsed,
                model: modelUsed
            ),
            imageData: nil
        )

        modelContext.insert(entry)
        Task {
            try? await healthKitManager.save(entry: entry)
        }
        onSave()
    }

    private var barcodeKidneyWarning: String {
        var warnings: [String] = []

        if product.sodiumPer100GMg * multiplier >= 700 {
            warnings.append("High sodium for this amount.")
        }

        if product.potassiumPer100GMg * multiplier >= 700 {
            warnings.append("High potassium for this amount.")
        }

        if product.phosphorusPer100GMg * multiplier >= 300 {
            warnings.append("High phosphorus for this amount.")
        }

        return warnings.joined(separator: " ")
    }
}

private enum BarcodeLookupService {
    static func lookup(barcode: String) async throws -> BarcodeProduct {
        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json")
        components?.queryItems = [
            URLQueryItem(
                name: "fields",
                value: "code,product_name,brands,quantity,serving_size,serving_quantity,nutriments"
            )
        ]

        guard let url = components?.url else {
            throw BarcodeLookupError.invalidBarcode
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("MealVue/1.0 (nutrition logging app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BarcodeLookupError.lookupFailed
        }

        let decoded = try JSONDecoder().decode(OpenFoodFactsResponse.self, from: data)
        guard decoded.status == 1, let product = decoded.product else {
            throw BarcodeLookupError.notFound
        }

        return BarcodeProduct(
            barcode: decoded.code ?? barcode,
            name: product.productName?.isEmpty == false ? product.productName! : "Scanned product",
            brand: product.brands ?? "",
            packageQuantity: product.quantity ?? "",
            servingSize: product.servingSize ?? "",
            servingQuantityG: product.servingQuantity,
            caloriesPer100G: product.nutriments.energyKcal100G ?? product.nutriments.energyKcal ?? 0,
            proteinPer100G: product.nutriments.protein100G ?? 0,
            carbsPer100G: product.nutriments.carbohydrates100G ?? 0,
            fatPer100G: product.nutriments.fat100G ?? 0,
            fiberPer100G: product.nutriments.fiber100G ?? 0,
            sodiumPer100GMg: (product.nutriments.sodium100G ?? 0) * 1000,
            potassiumPer100GMg: (product.nutriments.potassium100G ?? 0) * 1000,
            phosphorusPer100GMg: (product.nutriments.phosphorus100G ?? 0) * 1000
        )
    }
}

private struct OpenFoodFactsResponse: Decodable {
    let code: String?
    let status: Int
    let product: Product?

    struct Product: Decodable {
        let productName: String?
        let brands: String?
        let quantity: String?
        let servingSize: String?
        let servingQuantity: Double?
        let nutriments: Nutriments

        enum CodingKeys: String, CodingKey {
            case productName = "product_name"
            case brands
            case quantity
            case servingSize = "serving_size"
            case servingQuantity = "serving_quantity"
            case nutriments
        }
    }

    struct Nutriments: Decodable {
        let energyKcal100G: Double?
        let energyKcal: Double?
        let protein100G: Double?
        let carbohydrates100G: Double?
        let fat100G: Double?
        let fiber100G: Double?
        let sodium100G: Double?
        let potassium100G: Double?
        let phosphorus100G: Double?

        enum CodingKeys: String, CodingKey {
            case energyKcal100G = "energy-kcal_100g"
            case energyKcal = "energy-kcal"
            case protein100G = "proteins_100g"
            case carbohydrates100G = "carbohydrates_100g"
            case fat100G = "fat_100g"
            case fiber100G = "fiber_100g"
            case sodium100G = "sodium_100g"
            case potassium100G = "potassium_100g"
            case phosphorus100G = "phosphorus_100g"
        }
    }
}

private enum BarcodeLookupError: LocalizedError {
    case invalidBarcode
    case lookupFailed
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidBarcode:
            return "The scanned barcode was not valid."
        case .lookupFailed:
            return "Could not look up this barcode. Check the connection and try again."
        case .notFound:
            return "No product was found for this barcode."
        }
    }
}

private struct PhotoAnalysisView: View {
    let image: UIImage
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKitManager
    @AppStorage("kidneyChecksEnabled") private var kidneyChecksEnabled = true
    @AppStorage("heartChecksEnabled") private var heartChecksEnabled = true

    @State private var phase: AnalysisPhase
    @State private var foodName = ""
    @State private var quantity = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""
    @State private var sodium = ""
    @State private var potassium = ""
    @State private var phosphorus = ""
    @State private var notes = ""
    @State private var kidneyWarning = ""
    @State private var heartWarning = ""
    @State private var sodiumWarning = ""
    @State private var potassiumWarning = ""
    @State private var phosphorusWarning = ""
    @State private var confidence = "manual"
    @State private var modelUsed = ""
    @State private var providerUsed = ""
    @State private var didStartAnalysis = false

    init(image: UIImage, onSave: @escaping () -> Void) {
        self.image = image
        self.onSave = onSave
        _phase = State(initialValue: Config.isConfigured ? .analyzing : .editing)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal)

                    switch phase {
                    case .analyzing:
                        ProgressView("Analyzing photo...")
                            .padding(.top, 40)

                    case .editing:
                        if !Config.isConfigured {
                            InfoBanner(
                                title: "Manual mode",
                                message: "No API key is configured, so fill in the meal details yourself and save the photo entry."
                            )
                            .padding(.horizontal)
                        }

                        if kidneyChecksEnabled && !kidneyWarning.isEmpty {
                            WarningCard(message: kidneyWarning)
                                .padding(.horizontal)
                        }

                        if heartChecksEnabled && !heartWarning.isEmpty {
                            WarningCard(message: heartWarning, tint: .pink)
                                .padding(.horizontal)
                        }

                        if (kidneyChecksEnabled || heartChecksEnabled) && !sodiumWarning.isEmpty {
                            WarningCard(message: sodiumWarning, tint: .orange)
                                .padding(.horizontal)
                        }

                        if (kidneyChecksEnabled || heartChecksEnabled) && !potassiumWarning.isEmpty {
                            WarningCard(message: potassiumWarning, tint: .yellow)
                                .padding(.horizontal)
                        }

                        if (kidneyChecksEnabled || heartChecksEnabled) && !phosphorusWarning.isEmpty {
                            WarningCard(message: phosphorusWarning, tint: .purple)
                                .padding(.horizontal)
                        }

                        if !modelUsed.isEmpty {
                            ModelInfoCard(provider: providerUsed, model: modelUsed, confidence: confidence)
                                .padding(.horizontal)
                        }

                        if Config.isConfigured {
                            Button {
                                Task { await redoAnalysisWithRetries() }
                            } label: {
                                Label("AI Redo", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.horizontal)
                        }

                        MealEditor(
                            foodName: $foodName,
                            quantity: $quantity,
                            calories: $calories,
                            protein: $protein,
                            carbs: $carbs,
                            fat: $fat,
                            fiber: $fiber,
                            sodium: $sodium,
                            potassium: $potassium,
                            phosphorus: $phosphorus,
                            notes: $notes
                        )
                    case .error(let message):
                        ErrorStateView(message: message) {
                            Task { await analyzeWithRetries() }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Photo Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if case .editing = phase {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .fontWeight(.bold)
                    }
                }
            }
        }
        .onAppear {
            guard Config.isConfigured, !didStartAnalysis else { return }
            didStartAnalysis = true

            Task {
                await analyzeWithRetries()
            }
        }
    }

    private func analyzeWithRetries() async {
        await runAnalysisWithRetries {
            try await analyze()
        }
    }

    private func redoAnalysisWithRetries() async {
        await runAnalysisWithRetries {
            try await redoAnalysis()
        }
    }

    private func runAnalysisWithRetries(_ operation: @escaping () async throws -> Void) async {
        do {
            try await Task.sleep(for: .milliseconds(initialAnalysisDelayMS))
        } catch {
            return
        }

        let retryDelays = analysisRetryDelaysNS

        for (index, delay) in retryDelays.enumerated() {
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
            }

            do {
                try Task.checkCancellation()
                try await operation()
                return
            } catch is CancellationError {
                return
            } catch {
                if index == retryDelays.count - 1 {
                    phase = .error(error.localizedDescription)
                    return
                }
            }
        }
    }

    private var initialAnalysisDelayMS: Int {
        Config.selectedProvider == .openRouter ? 150 : 600
    }

    private var analysisRetryDelaysNS: [UInt64] {
        if Config.selectedProvider == .openRouter {
            return [
                0,
                500_000_000,
                1_000_000_000
            ]
        }

        return [
            0,
            1_000_000_000,
            2_000_000_000,
            3_000_000_000
        ]
    }

    private func analyze() async throws {
        phase = .analyzing

        let result = try await ClaudeService.analyzeFood(image: image)
        apply(result: result)
        phase = .editing
    }

    private func redoAnalysis() async throws {
        phase = .analyzing

        let result = try await ClaudeService.analyzeFood(
            image: image,
            correctedDescription: correctedDescription
        )
        apply(result: result)
        phase = .editing
    }

    private var correctedDescription: String {
        let trimmedFoodName = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuantity = quantity.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedFoodName.isEmpty {
            return trimmedQuantity
        }

        if trimmedQuantity.isEmpty {
            return trimmedFoodName
        }

        return "\(trimmedQuantity) of \(trimmedFoodName)"
    }

    private func apply(result: NutritionResult) {
        foodName = result.foodName
        quantity = result.estimatedQuantity
        calories = "\(result.calories)"
        protein = format(result.proteinG)
        carbs = format(result.carbsG)
        fat = format(result.fatG)
        fiber = format(result.fiberG)
        sodium = format(result.sodiumMg)
        potassium = format(result.potassiumMg)
        phosphorus = format(result.phosphorusMg)
        notes = result.notes
        kidneyWarning = Config.kidneyChecksEnabled ? result.kidneyWarning : ""
        heartWarning = Config.heartChecksEnabled ? result.heartWarning : ""
        sodiumWarning = (Config.kidneyChecksEnabled || Config.heartChecksEnabled) ? result.sodiumWarning : ""
        potassiumWarning = (Config.kidneyChecksEnabled || Config.heartChecksEnabled) ? result.potassiumWarning : ""
        phosphorusWarning = (Config.kidneyChecksEnabled || Config.heartChecksEnabled) ? result.phosphorusWarning : ""
        confidence = result.confidence
        modelUsed = result.modelUsed
        providerUsed = result.providerName
    }

    private func save() {
        let entry = FoodEntry(
            foodName: foodName.trimmingCharacters(in: .whitespacesAndNewlines),
            estimatedQuantity: quantity.trimmingCharacters(in: .whitespacesAndNewlines),
            calories: Int(calories) ?? 0,
            proteinG: Double(protein) ?? 0,
            carbsG: Double(carbs) ?? 0,
            fatG: Double(fat) ?? 0,
            fiberG: Double(fiber) ?? 0,
            sodiumMg: Double(sodium) ?? 0,
            potassiumMg: Double(potassium) ?? 0,
            phosphorusMg: Double(phosphorus) ?? 0,
            notes: "",
            kidneyWarning: kidneyChecksEnabled ? kidneyWarning.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            confidence: confidence,
            aiNotes: combinedAINotes(
                baseNotes: notes,
                heartWarning: heartChecksEnabled ? heartWarning : "",
                sodiumWarning: (kidneyChecksEnabled || heartChecksEnabled) ? sodiumWarning : "",
                potassiumWarning: (kidneyChecksEnabled || heartChecksEnabled) ? potassiumWarning : "",
                phosphorusWarning: (kidneyChecksEnabled || heartChecksEnabled) ? phosphorusWarning : "",
                provider: providerUsed,
                model: modelUsed
            ),
            imageData: image.jpegData(compressionQuality: 0.7)
        )

        modelContext.insert(entry)
        Task {
            try? await healthKitManager.save(entry: entry)
        }
        onSave()
    }
}

private struct TextAnalysisEntryView: View {
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKitManager
    @AppStorage("kidneyChecksEnabled") private var kidneyChecksEnabled = true
    @AppStorage("heartChecksEnabled") private var heartChecksEnabled = true

    @State private var description = ""
    @State private var phase: AnalysisPhase = .editing
    @State private var foodName = ""
    @State private var quantity = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""
    @State private var sodium = ""
    @State private var potassium = ""
    @State private var phosphorus = ""
    @State private var notes = ""
    @State private var kidneyWarning = ""
    @State private var heartWarning = ""
    @State private var sodiumWarning = ""
    @State private var potassiumWarning = ""
    @State private var phosphorusWarning = ""
    @State private var confidence = "manual"
    @State private var modelUsed = ""
    @State private var providerUsed = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if phase == .editing && foodName.isEmpty {
                        VStack(spacing: 20) {
                            TextField("Describe what you ate", text: $description, axis: .vertical)
                                .lineLimit(3...6)
                                .textFieldStyle(.roundedBorder)
                                .padding(.horizontal)

                            Button("Analyze Description") {
                                Task { await analyze() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !Config.isConfigured)
                            .padding(.horizontal)

                            if !Config.isConfigured {
                                InfoBanner(
                                    title: "API key required",
                                    message: "Text analysis needs an API key for the provider selected in Settings."
                                )
                                .padding(.horizontal)
                            }
                        }
                        .padding(.top, 20)
                    } else {
                        switch phase {
                        case .analyzing:
                            ProgressView("Analyzing description...")
                                .padding(.top, 40)

                        case .editing:
                            if kidneyChecksEnabled && !kidneyWarning.isEmpty {
                                WarningCard(message: kidneyWarning)
                                    .padding(.horizontal)
                            }

                            if heartChecksEnabled && !heartWarning.isEmpty {
                                WarningCard(message: heartWarning, tint: .pink)
                                    .padding(.horizontal)
                            }

                            if (kidneyChecksEnabled || heartChecksEnabled) && !sodiumWarning.isEmpty {
                                WarningCard(message: sodiumWarning, tint: .orange)
                                    .padding(.horizontal)
                            }

                            if (kidneyChecksEnabled || heartChecksEnabled) && !potassiumWarning.isEmpty {
                                WarningCard(message: potassiumWarning, tint: .yellow)
                                    .padding(.horizontal)
                            }

                            if (kidneyChecksEnabled || heartChecksEnabled) && !phosphorusWarning.isEmpty {
                                WarningCard(message: phosphorusWarning, tint: .purple)
                                    .padding(.horizontal)
                            }

                            if !modelUsed.isEmpty {
                                ModelInfoCard(provider: providerUsed, model: modelUsed, confidence: confidence)
                                    .padding(.horizontal)
                            }

                            if Config.isConfigured {
                                Button {
                                    Task { await analyze() }
                                } label: {
                                    Label("Redo AI Analysis", systemImage: "arrow.clockwise")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .padding(.horizontal)
                            }

                            MealEditor(
                                foodName: $foodName,
                                quantity: $quantity,
                                calories: $calories,
                                protein: $protein,
                                carbs: $carbs,
                                fat: $fat,
                                fiber: $fiber,
                                sodium: $sodium,
                                potassium: $potassium,
                                phosphorus: $phosphorus,
                                notes: $notes
                            )

                        case .error(let message):
                            ErrorStateView(message: message) {
                                Task { await analyze() }
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Describe Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if case .editing = phase, !foodName.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .fontWeight(.bold)
                    }
                }
            }
        }
    }

    private func analyze() async {
        phase = .analyzing

        do {
            let prompt = analysisDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try await ClaudeService.analyzeText(description: prompt)
            foodName = result.foodName
            quantity = result.estimatedQuantity
            calories = "\(result.calories)"
            protein = format(result.proteinG)
            carbs = format(result.carbsG)
            fat = format(result.fatG)
            fiber = format(result.fiberG)
            sodium = format(result.sodiumMg)
            potassium = format(result.potassiumMg)
            phosphorus = format(result.phosphorusMg)
            notes = result.notes
            kidneyWarning = Config.kidneyChecksEnabled ? result.kidneyWarning : ""
            heartWarning = Config.heartChecksEnabled ? result.heartWarning : ""
            sodiumWarning = (Config.kidneyChecksEnabled || Config.heartChecksEnabled) ? result.sodiumWarning : ""
            potassiumWarning = (Config.kidneyChecksEnabled || Config.heartChecksEnabled) ? result.potassiumWarning : ""
            phosphorusWarning = (Config.kidneyChecksEnabled || Config.heartChecksEnabled) ? result.phosphorusWarning : ""
            confidence = result.confidence
            modelUsed = result.modelUsed
            providerUsed = result.providerName
            phase = .editing
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private var analysisDescription: String {
        let trimmedFoodName = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuantity = quantity.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedFoodName.isEmpty {
            return description
        }

        if trimmedQuantity.isEmpty {
            return trimmedFoodName
        }

        return "\(trimmedQuantity) of \(trimmedFoodName)"
    }

    private func save() {
        let entry = FoodEntry(
            foodName: foodName.trimmingCharacters(in: .whitespacesAndNewlines),
            estimatedQuantity: quantity.trimmingCharacters(in: .whitespacesAndNewlines),
            calories: Int(calories) ?? 0,
            proteinG: Double(protein) ?? 0,
            carbsG: Double(carbs) ?? 0,
            fatG: Double(fat) ?? 0,
            fiberG: Double(fiber) ?? 0,
            sodiumMg: Double(sodium) ?? 0,
            potassiumMg: Double(potassium) ?? 0,
            phosphorusMg: Double(phosphorus) ?? 0,
            notes: "",
            kidneyWarning: kidneyChecksEnabled ? kidneyWarning.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            confidence: confidence,
            aiNotes: combinedAINotes(
                baseNotes: notes,
                heartWarning: heartChecksEnabled ? heartWarning : "",
                sodiumWarning: (kidneyChecksEnabled || heartChecksEnabled) ? sodiumWarning : "",
                potassiumWarning: (kidneyChecksEnabled || heartChecksEnabled) ? potassiumWarning : "",
                phosphorusWarning: (kidneyChecksEnabled || heartChecksEnabled) ? phosphorusWarning : "",
                provider: providerUsed,
                model: modelUsed
            ),
            imageData: nil
        )

        modelContext.insert(entry)
        Task {
            try? await healthKitManager.save(entry: entry)
        }
        onSave()
    }
}

private struct MealEditor: View {
    @Binding var foodName: String
    @Binding var quantity: String
    @Binding var calories: String
    @Binding var protein: String
    @Binding var carbs: String
    @Binding var fat: String
    @Binding var fiber: String
    @Binding var sodium: String
    @Binding var potassium: String
    @Binding var phosphorus: String
    @Binding var notes: String

    var body: some View {
        VStack(spacing: 16) {
            GroupBox("Food") {
                VStack(alignment: .leading, spacing: 12) {
                    expandingEditor("Food name", text: $foodName, lineLimit: 2...4)
                    Divider()
                    expandingEditor("Serving / quantity", text: $quantity, lineLimit: 2...6)
                }
            }
            .padding(.horizontal)

            GroupBox("Nutrition") {
                VStack(spacing: 10) {
                    numericRow("Calories", text: $calories, unit: "kcal", isInt: true)
                    Divider()
                    numericRow("Protein", text: $protein, unit: "g")
                    numericRow("Carbs", text: $carbs, unit: "g")
                    numericRow("Fat", text: $fat, unit: "g")
                    numericRow("Fiber", text: $fiber, unit: "g")
                    Divider()
                    numericRow("Sodium", text: $sodium, unit: "mg")
                    numericRow("Potassium", text: $potassium, unit: "mg")
                    numericRow("Phosphorus", text: $phosphorus, unit: "mg")
                }
            }
            .padding(.horizontal)

            GroupBox("Notes") {
                TextField("Assumptions or comments", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }
            .padding(.horizontal)
        }
    }

    private func expandingEditor(_ label: String, text: Binding<String>, lineLimit: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func numericRow(_ label: String, text: Binding<String>, unit: String, isInt: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            TextField("0", text: text)
                .keyboardType(isInt ? .numberPad : .decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 68)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
        }
    }
}

private struct TotalsCard: View {
    @AppStorage("kidneyChecksEnabled") private var kidneyChecksEnabled = true
    @AppStorage("heartChecksEnabled") private var heartChecksEnabled = true
    @AppStorage("ckdStage") private var ckdStageRaw = CKDStage.notSpecified.rawValue
    @AppStorage("userWeightKg") private var userWeightKg = ""
    @AppStorage("proteinTargetG") private var proteinTargetG = ""
    @AppStorage("sodiumTargetMg") private var sodiumTargetMg = ""
    @AppStorage("potassiumTargetMg") private var potassiumTargetMg = ""
    @AppStorage("phosphorusTargetMg") private var phosphorusTargetMg = ""

    let totals: NutritionTotals

    private var sodiumThreshold: Double {
        parsedTarget(sodiumTargetMg) ?? RecommendedTargets.defaultSodiumMg(heartChecksEnabled: heartChecksEnabled)
    }

    private var proteinThreshold: Double {
        parsedTarget(proteinTargetG) ?? RecommendedTargets.defaultProteinG(
            for: selectedCKDStage,
            weightKg: Double(userWeightKg.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }

    private var potassiumThreshold: Double? {
        parsedTarget(potassiumTargetMg) ?? (kidneyChecksEnabled ? RecommendedTargets.defaultPotassiumMg(for: selectedCKDStage) : nil)
    }

    private var phosphorusThreshold: Double? {
        parsedTarget(phosphorusTargetMg) ?? (kidneyChecksEnabled ? RecommendedTargets.defaultPhosphorusMg(for: selectedCKDStage) : nil)
    }

    private var selectedCKDStage: CKDStage {
        CKDStage(rawValue: ckdStageRaw) ?? .notSpecified
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(totals.calories)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                Text("kcal")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(totals.entriesCount) meals")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                MacroSummaryCard(title: "Protein", value: totals.proteinG, tint: .blue)
                MacroSummaryCard(title: "Carbs", value: totals.carbsG, tint: .green)
                MacroSummaryCard(title: "Fat", value: totals.fatG, tint: .orange)
                MacroSummaryCard(title: "Fiber", value: totals.fiberG, tint: .purple)
            }

            ProteinTargetRow(value: totals.proteinG, threshold: proteinThreshold)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Daily Mineral Totals")
                    .font(.headline)

                MineralTotalRow(
                    title: "Sodium",
                    value: totals.sodiumMg,
                    threshold: sodiumThreshold,
                    note: "Target \(Int(sodiumThreshold)) mg/day"
                )

                MineralTotalRow(
                    title: "Potassium",
                    value: totals.potassiumMg,
                    threshold: potassiumThreshold,
                    note: potassiumThreshold == nil ? "Tracking only" : "Target \(Int(potassiumThreshold ?? 0)) mg/day"
                )

                MineralTotalRow(
                    title: "Phosphorus",
                    value: totals.phosphorusMg,
                    threshold: phosphorusThreshold,
                    note: phosphorusThreshold == nil ? "Tracking only" : "Target \(Int(phosphorusThreshold ?? 0)) mg/day"
                )
            }
        }
        .padding(.vertical, 8)
    }

    private func parsedTarget(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }
}

private struct MacroSummaryCard: View {
    let title: String
    let value: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(Int(value.rounded()))g")
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct ProteinTargetRow: View {
    let value: Double
    let threshold: Double

    private var progress: Double {
        guard threshold > 0 else { return 0 }
        return value / threshold
    }

    private var tint: Color {
        switch progress {
        case ..<0.8:
            return .green
        case ..<1.0:
            return .yellow
        default:
            return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Protein target")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(value.rounded())) / \(Int(threshold.rounded())) g")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: min(progress, 1.0))
                .tint(tint)
        }
    }
}

private struct MineralTotalRow: View {
    let title: String
    let value: Double
    let threshold: Double?
    let note: String

    private var isHigh: Bool {
        guard let threshold else { return false }
        return value > threshold
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(Int(value.rounded())) mg")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(isHigh ? .red : .primary)
        }
        .padding(.vertical, 4)
    }
}

private struct BarGraphView: View {
    let totals: NutritionTotals
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Chart {
                BarMark(
                    x: .value("Nutrient", "Protein"),
                    y: .value("Amount", totals.proteinG)
                )
                .foregroundStyle(.blue)

                BarMark(
                    x: .value("Nutrient", "Fiber"),
                    y: .value("Amount", totals.fiberG)
                )
                .foregroundStyle(.green)

                BarMark(
                    x: .value("Nutrient", "Sodium"),
                    y: .value("Amount", totals.sodiumMg / 1000)
                )
                .foregroundStyle(.orange)

                BarMark(
                    x: .value("Nutrient", "Potassium"),
                    y: .value("Amount", totals.potassiumMg / 1000)
                )
                .foregroundStyle(.yellow)

                BarMark(
                    x: .value("Nutrient", "Phosphorus"),
                    y: .value("Amount", totals.phosphorusMg / 1000)
                )
                .foregroundStyle(.purple)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel("\(value.as(Double.self) ?? 0, specifier: "%.1f")")
                }
            }

            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Protein: \(Int(totals.proteinG.rounded()))g")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("Fiber: \(Int(totals.fiberG.rounded()))g")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("Sodium: \(Int(totals.sodiumMg.rounded()))mg")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Potassium: \(Int(totals.potassiumMg.rounded()))mg")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text("Phosphorus: \(Int(totals.phosphorusMg.rounded()))mg")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct DashboardRingItem: Identifiable {
    let id = UUID()
    let title: String
    let value: Double
    let target: Double
    let displayValue: String
    let targetLabel: String
    let accent: Color

    var progress: Double {
        guard target > 0 else { return 0 }
        return value / target
    }

    var normalizedProgress: Double {
        min(progress, 1.2)
    }

    var statusColor: Color {
        switch progress {
        case ..<0.8:
            return .green
        case ..<1.0:
            return .yellow
        default:
            return .red
        }
    }
}

private struct DashboardSparklineItem: Identifiable {
    let id = UUID()
    let title: String
    let values: [Double]
    let target: Double
    let accent: Color
    let unit: String

    var latestValueText: String {
        "\(Int((values.last ?? 0).rounded())) \(unit)"
    }
}

private struct DashboardStatusDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

private struct NutrientRingCard: View {
    let item: DashboardRingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.title)
                    .font(.headline)
                Spacer()
                Text(item.targetLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(item.accent.opacity(0.14), lineWidth: 14)

                    Circle()
                        .trim(from: 0, to: item.normalizedProgress)
                        .stroke(
                            AngularGradient(
                                colors: [item.accent.opacity(0.4), item.accent, item.statusColor],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Text("\(Int((item.progress * 100).rounded()))%")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                        Text("of goal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 108, height: 108)

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.displayValue)
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(.primary)
                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(item.statusColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var statusText: String {
        switch item.progress {
        case ..<0.8:
            return "On Track"
        case ..<1.0:
            return "Caution"
        default:
            return "Exceeded"
        }
    }
}

private struct NutrientSparklineRow: View {
    let item: DashboardSparklineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(item.latestValueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let values = item.values
                let maxValue = max(values.max() ?? 0, item.target, 1)
                let barWidth = max((proxy.size.width - 36) / 7, 8)

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(barColor(for: value))
                            .frame(
                                width: barWidth,
                                height: max(CGFloat(value / maxValue) * proxy.size.height, 6)
                            )
                    }
                }
            }
            .frame(height: 44)
        }
        .padding(.vertical, 2)
    }

    private func barColor(for value: Double) -> Color {
        let progress = value / item.target
        switch progress {
        case ..<0.8:
            return item.accent.opacity(0.72)
        case ..<1.0:
            return .yellow
        default:
            return .red
        }
    }
}

private struct MacroChip: View {
    let label: String
    let value: Double
    let tint: Color

    var body: some View {
        Text("\(label) \(Int(value))g")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

private struct ActionButtonLabel: View {
    let title: String
    let systemImage: String
    var fill: Color? = nil
    var foreground: Color = .green

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(foreground.opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(foreground)
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .padding(.horizontal, 4)
    }
}

private struct InfoBanner: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.blue.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct WarningCard: View {
    let message: String
    var tint: Color = .red

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.12))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(tint.opacity(0.30), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct ModelInfoCard: View {
    let provider: String
    let model: String
    let confidence: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cpu.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Result Details")
                    .font(.headline)
                Text("Provider: \(provider)")
                    .font(.footnote)
                Text("Model: \(model)")
                    .font(.footnote)
                Text("Confidence: \(confidence.capitalized)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.blue.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private func combinedAINotes(
    baseNotes: String,
    heartWarning: String,
    sodiumWarning: String,
    potassiumWarning: String,
    phosphorusWarning: String,
    provider: String,
    model: String
) -> String {
    var parts: [String] = []

    let trimmedNotes = baseNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedNotes.isEmpty {
        parts.append(trimmedNotes)
    }

    let trimmedHeartWarning = heartWarning.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedHeartWarning.isEmpty {
        parts.append("Heart warning: \(trimmedHeartWarning)")
    }

    let trimmedSodiumWarning = sodiumWarning.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedSodiumWarning.isEmpty {
        parts.append("Salt warning: \(trimmedSodiumWarning)")
    }

    let trimmedPotassiumWarning = potassiumWarning.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedPotassiumWarning.isEmpty {
        parts.append("Potassium warning: \(trimmedPotassiumWarning)")
    }

    let trimmedPhosphorusWarning = phosphorusWarning.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedPhosphorusWarning.isEmpty {
        parts.append("Phosphorus warning: \(trimmedPhosphorusWarning)")
    }

    if !provider.isEmpty || !model.isEmpty {
        parts.append("AI provider: \(provider) | Model: \(model)")
    }

    return parts.joined(separator: "\n")
}

private struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
                .padding(.top, 32)
            Text("Analysis failed")
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct FoodGroup: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let tint: Color
    let items: [String]
}

private struct MenuPlan: Identifiable {
    let id = UUID()
    let title: String
    let meals: [Meal]
}

private struct Meal: Identifiable {
    let id = UUID()
    let name: String
    let items: String
}

private struct MedicationPage: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let systemImage: String
    let tint: Color
    let subtitle: String
    let summary: String
    let safeItems: [String]
    let cautionItems: [String]
}

private struct HistorySection {
    let date: Date
    let entries: [FoodEntry]

    var title: String {
        date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var shortTitle: String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    var totals: NutritionTotals {
        NutritionTotals(entries: entries)
    }
}

private struct NutritionTotals {
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double
    let sodiumMg: Double
    let potassiumMg: Double
    let phosphorusMg: Double
    let entriesCount: Int

    init(entries: [FoodEntry]) {
        calories = entries.reduce(0) { $0 + $1.calories }
        proteinG = entries.reduce(0) { $0 + $1.proteinG }
        carbsG = entries.reduce(0) { $0 + $1.carbsG }
        fatG = entries.reduce(0) { $0 + $1.fatG }
        fiberG = entries.reduce(0) { $0 + $1.fiberG }
        sodiumMg = entries.reduce(0) { $0 + $1.sodiumMg }
        potassiumMg = entries.reduce(0) { $0 + $1.potassiumMg }
        phosphorusMg = entries.reduce(0) { $0 + $1.phosphorusMg }
        entriesCount = entries.count
    }
}

private struct NutritionTargets {
    let proteinG: Double
    let sodiumMg: Double
    let potassiumMg: Double?
    let phosphorusMg: Double?
}

private enum NutritionReportPDF {
    static func writeReport(
        for sections: [HistorySection],
        startDate: Date,
        endDate: Date,
        targets: NutritionTargets
    ) throws -> URL {
        let data = renderReport(
            for: sections,
            startDate: startDate,
            endDate: endDate,
            targets: targets
        )

        let fileName = "MealVue-Daily-Report-\(fileStamp(from: startDate))-\(fileStamp(from: endDate)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func renderReport(
        for sections: [HistorySection],
        startDate: Date,
        endDate: Date,
        targets: NutritionTargets
    ) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 40
        let contentWidth = pageRect.width - (margin * 2)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { context in
            var currentY: CGFloat = 0

            func beginPage() {
                context.beginPage()
                currentY = margin
            }

            func ensureSpace(_ height: CGFloat) {
                if currentY + height > pageRect.height - margin {
                    beginPage()
                }
            }

            func drawLine(_ text: String, font: UIFont, color: UIColor = .label, spacingAfter: CGFloat = 8) {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color
                ]
                let rect = NSString(string: text).boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                ensureSpace(rect.height + spacingAfter)
                NSString(string: text).draw(
                    in: CGRect(x: margin, y: currentY, width: contentWidth, height: rect.height),
                    withAttributes: attributes
                )
                currentY += rect.height + spacingAfter
            }

            beginPage()
            drawLine("MealVue Daily Nutrition Report", font: .boldSystemFont(ofSize: 24), spacingAfter: 10)
            drawLine(
                "\(startDate.formatted(date: .abbreviated, time: .omitted)) to \(endDate.formatted(date: .abbreviated, time: .omitted))",
                font: .systemFont(ofSize: 13),
                color: .secondaryLabel,
                spacingAfter: 18
            )
            drawLine("Targets", font: .boldSystemFont(ofSize: 16), spacingAfter: 8)
            drawLine("Protein: \(Int(targets.proteinG)) g/day", font: .systemFont(ofSize: 12), spacingAfter: 4)
            drawLine("Sodium: \(Int(targets.sodiumMg)) mg/day", font: .systemFont(ofSize: 12), spacingAfter: 4)
            drawLine(
                "Potassium: \(targets.potassiumMg.map { "\(Int($0)) mg/day" } ?? "Tracking only")",
                font: .systemFont(ofSize: 12),
                spacingAfter: 4
            )
            drawLine(
                "Phosphorus: \(targets.phosphorusMg.map { "\(Int($0)) mg/day" } ?? "Tracking only")",
                font: .systemFont(ofSize: 12),
                spacingAfter: 18
            )

            for section in sections {
                ensureSpace(130)
                drawLine(section.title, font: .boldSystemFont(ofSize: 16), spacingAfter: 6)
                drawLine(
                    "Meals: \(section.entries.count)    Calories: \(section.totals.calories) kcal",
                    font: .systemFont(ofSize: 12),
                    spacingAfter: 4
                )
                drawLine(
                    "Protein: \(Int(section.totals.proteinG)) g\(markerIfHigh(section.totals.proteinG, threshold: targets.proteinG))",
                    font: .systemFont(ofSize: 12),
                    spacingAfter: 4
                )
                drawLine(
                    "Sodium: \(Int(section.totals.sodiumMg)) mg\(markerIfHigh(section.totals.sodiumMg, threshold: targets.sodiumMg))",
                    font: .systemFont(ofSize: 12),
                    spacingAfter: 4
                )
                drawLine(
                    "Potassium: \(Int(section.totals.potassiumMg)) mg\(markerIfHigh(section.totals.potassiumMg, threshold: targets.potassiumMg))",
                    font: .systemFont(ofSize: 12),
                    spacingAfter: 4
                )
                drawLine(
                    "Phosphorus: \(Int(section.totals.phosphorusMg)) mg\(markerIfHigh(section.totals.phosphorusMg, threshold: targets.phosphorusMg))",
                    font: .systemFont(ofSize: 12),
                    spacingAfter: 12
                )
            }
        }
    }

    private static func markerIfHigh(_ value: Double, threshold: Double?) -> String {
        guard let threshold, value > threshold else { return "" }
        return "  HIGH"
    }

    private static func fileStamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private enum RecommendedTargets {
    static func defaultSodiumMg(heartChecksEnabled: Bool) -> Double {
        heartChecksEnabled ? 1500 : 2300
    }

    static func defaultProteinG(for stage: CKDStage, weightKg: Double?) -> Double {
        let safeWeight = max(weightKg ?? 70, 35)

        switch stage {
        case .notSpecified, .stage1, .stage2, .stage3a:
            return safeWeight * 0.8
        case .stage3b, .stage4, .stage3to4, .stage5NotDialysis:
            return safeWeight * 0.7
        case .dialysis:
            return safeWeight * 1.2
        }
    }

    static func defaultPotassiumMg(for stage: CKDStage) -> Double {
        switch stage {
        case .notSpecified, .stage1, .stage2:
            return 4700
        case .stage3a:
            return 3500
        case .stage3b, .stage4, .stage3to4, .stage5NotDialysis, .dialysis:
            return 3000
        }
    }

    static func defaultPhosphorusMg(for stage: CKDStage) -> Double {
        switch stage {
        case .notSpecified, .stage1, .stage2:
            return 1000
        case .stage3a:
            return 900
        case .stage3b, .stage4, .stage3to4, .stage5NotDialysis, .dialysis:
            return 800
        }
    }
}

private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private enum AIProvider: String, CaseIterable, Identifiable {
    case anthropic
    case gemini
    case openAI
    case openRouter
    case cloudflare

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .openAI: return "OpenAI"
        case .openRouter: return "OpenRouter"
        case .cloudflare: return "MealVue AI"
        }
    }
}

private protocol RankedAIModel {
    var id: String { get }
}

private struct AnthropicModel: Identifiable, Hashable {
    let id: String
    let displayName: String

    static let defaults: [AnthropicModel] = [
        AnthropicModel(id: "claude-opus-4-5", displayName: "Claude Opus 4.5"),
        AnthropicModel(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6"),
        AnthropicModel(id: "claude-sonnet-4-5", displayName: "Claude Sonnet 4.5"),
        AnthropicModel(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5"),
        AnthropicModel(id: "claude-sonnet-4-20250514", displayName: "Claude Sonnet 4")
    ]

    static let defaultModel = defaults[0]
}

private struct GeminiModel: Identifiable, Hashable, RankedAIModel {
    let id: String
    let displayName: String

    static let defaults: [GeminiModel] = [
        GeminiModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash"),
        GeminiModel(id: "gemini-2.5-flash-lite", displayName: "Gemini 2.5 Flash-Lite"),
        GeminiModel(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro")
    ]

    static let defaultModel = defaults[0]

    static func isVisionCapableID(_ id: String) -> Bool {
        let normalized = id.lowercased()
        return normalized.contains("flash") ||
            normalized.contains("pro") ||
            normalized.contains("vision")
    }

    static func shouldResetSelection(_ id: String) -> Bool {
        let normalized = id.lowercased()
        return normalized.contains("preview") ||
            normalized.contains("experimental") ||
            !isVisionCapableID(normalized)
    }
}

private struct OpenAIModel: Identifiable, Hashable, RankedAIModel {
    let id: String
    let displayName: String

    static let defaults: [OpenAIModel] = [
        OpenAIModel(id: "gpt-4.1", displayName: "GPT-4.1"),
        OpenAIModel(id: "gpt-4o", displayName: "GPT-4o"),
        OpenAIModel(id: "gpt-4.1-mini", displayName: "GPT-4.1 Mini"),
        OpenAIModel(id: "gpt-4o-mini", displayName: "GPT-4o Mini"),
        OpenAIModel(id: "gpt-5.5", displayName: "GPT-5.5"),
        OpenAIModel(id: "gpt-5.4", displayName: "GPT-5.4")
    ]

    static let defaultModel = defaults[0]

    static func isVisionCapableID(_ id: String) -> Bool {
        let normalized = id.lowercased()
        guard !normalized.contains("realtime"),
              !normalized.contains("audio"),
              !normalized.contains("image"),
              !normalized.contains("embedding"),
              !normalized.contains("moderation"),
              !normalized.contains("search-preview") else {
            return false
        }

        return normalized.hasPrefix("gpt-5") ||
            normalized.hasPrefix("gpt-4.1") ||
            normalized.hasPrefix("gpt-4o")
    }
}

private struct OpenRouterModel: Identifiable, Hashable, RankedAIModel {
    let id: String
    let displayName: String
    let supportsVision: Bool
    let isRouter: Bool

    static let autoRouter = OpenRouterModel(
        id: "openrouter/auto",
        displayName: "OpenRouter Auto Router",
        supportsVision: true,
        isRouter: true
    )

    static let freeRouter = OpenRouterModel(
        id: "openrouter/free",
        displayName: "OpenRouter Free Router",
        supportsVision: true,
        isRouter: true
    )

    static let recommended: [OpenRouterModel] = [
        .freeRouter,
        // Best for food image analysis - fast, accurate vision, low cost
        OpenRouterModel(id: "google/gemini-2.5-flash", displayName: "Gemini 2.5 Flash", supportsVision: true, isRouter: false),
        OpenRouterModel(id: "google/gemini-2.5-flash-lite", displayName: "Gemini 2.5 Flash-Lite", supportsVision: true, isRouter: false),
        OpenRouterModel(id: "openai/gpt-4o-mini", displayName: "GPT-4o Mini", supportsVision: true, isRouter: false),
        OpenRouterModel(id: "anthropic/claude-haiku-4.5", displayName: "Claude Haiku 4.5", supportsVision: true, isRouter: false),
        OpenRouterModel(id: "google/gemini-2.5-pro", displayName: "Gemini 2.5 Pro", supportsVision: true, isRouter: false),
        // Premium options
        OpenRouterModel(id: "anthropic/claude-sonnet-4.6", displayName: "Claude Sonnet 4.6", supportsVision: true, isRouter: false),
        OpenRouterModel(id: "anthropic/claude-sonnet-4.5", displayName: "Claude Sonnet 4.5", supportsVision: true, isRouter: false),
        OpenRouterModel(id: "anthropic/claude-opus-4.5", displayName: "Claude Opus 4.5", supportsVision: true, isRouter: false),
        OpenRouterModel(id: "openai/gpt-5.5", displayName: "GPT-5.5", supportsVision: true, isRouter: false),
        .autoRouter
    ]
}

private func rankModels<T: RankedAIModel>(_ models: [T], preferredIDs: [String]) -> [T] {
    models.sorted { lhs, rhs in
        let leftRank = preferredIDs.firstIndex(of: lhs.id) ?? Int.max
        let rightRank = preferredIDs.firstIndex(of: rhs.id) ?? Int.max

        if leftRank != rightRank {
            return leftRank < rightRank
        }

        return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
    }
}

private enum AnalysisPhase: Equatable {
    case analyzing
    case editing
    case error(String)
}

private struct NutritionResult {
    let foodName: String
    let estimatedQuantity: String
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double
    let sodiumMg: Double
    let potassiumMg: Double
    let phosphorusMg: Double
    let confidence: String
    let notes: String
    let kidneyWarning: String
    let heartWarning: String
    let sodiumWarning: String
    let potassiumWarning: String
    let phosphorusWarning: String
    let providerName: String
    let modelUsed: String
}

private enum Config {
    private static let defaults = UserDefaults.standard

    static var selectedProvider: AIProvider {
        AIProvider(rawValue: defaults.string(forKey: "aiProvider") ?? "") ?? .cloudflare
    }

    static var anthropicAPIKey: String {
        defaults.string(forKey: "anthropicAPIKey") ?? ""
    }

    static var anthropicModelID: String {
        let saved = defaults.string(forKey: "anthropicModelID") ?? ""
        return saved.isEmpty ? AnthropicModel.defaultModel.id : saved
    }

    static var geminiAPIKey: String {
        defaults.string(forKey: "geminiAPIKey") ?? ""
    }

    static var geminiModelID: String {
        let saved = defaults.string(forKey: "geminiModelID") ?? ""
        return saved.isEmpty || GeminiModel.shouldResetSelection(saved) ? GeminiModel.defaultModel.id : saved
    }

    static var openAIAPIKey: String {
        defaults.string(forKey: "openAIAPIKey") ?? ""
    }

    static var openAIModelID: String {
        let saved = defaults.string(forKey: "openAIModelID") ?? ""
        return saved.isEmpty ? OpenAIModel.defaultModel.id : saved
    }

    static var openRouterAPIKey: String {
        defaults.string(forKey: "openRouterAPIKey") ?? ""
    }

    static var mealvueClientToken: String {
        defaults.string(forKey: "mealvueClientToken") ?? ""
    }

    static var openRouterModelID: String {
        let saved = defaults.string(forKey: "openRouterModelID") ?? ""
        return saved.isEmpty ? OpenRouterModel.freeRouter.id : saved
    }

    static var isConfigured: Bool {
        switch selectedProvider {
        case .anthropic:
            return !anthropicAPIKey.isEmpty
        case .gemini:
            return !geminiAPIKey.isEmpty
        case .openAI:
            return !openAIAPIKey.isEmpty
        case .openRouter:
            return !openRouterAPIKey.isEmpty
        case .cloudflare:
            return true
        }
    }

    static var kidneyChecksEnabled: Bool {
        defaults.object(forKey: "kidneyChecksEnabled") as? Bool ?? true
    }

    static var heartChecksEnabled: Bool {
        defaults.object(forKey: "heartChecksEnabled") as? Bool ?? true
    }
}

private enum ClaudeService {
    private static let anthropicURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let anthropicVersion = "2023-06-01"
    private static let geminiModelsURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
    private static let openAIURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let openAIModelsURL = URL(string: "https://api.openai.com/v1/models")!
    private static let openRouterChatURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private static let openRouterModelsURL = URL(string: "https://openrouter.ai/api/v1/models")!
    private static let mealvueWorkerURL = URL(string: "https://mealvue-ai-backend.cryptobkk.workers.dev/v1/analyze")!

    static func analyzeFood(image: UIImage) async throws -> NutritionResult {
        switch Config.selectedProvider {
        case .anthropic:
            return try await analyzeFoodWithAnthropic(image: image)
        case .gemini:
            return try await analyzeFoodWithGemini(image: image)
        case .openAI:
            return try await analyzeFoodWithOpenAI(image: image)
        case .openRouter:
            return try await analyzeFoodWithOpenRouter(image: image)
        case .cloudflare:
            return try await analyzeFoodWithCloudflare(image: image)
        }
    }

    static func analyzeFood(image: UIImage, correctedDescription: String) async throws -> NutritionResult {
        switch Config.selectedProvider {
        case .anthropic:
            return try await analyzeFoodWithAnthropic(image: image, correctedDescription: correctedDescription)
        case .gemini:
            return try await analyzeFoodWithGemini(image: image, correctedDescription: correctedDescription)
        case .openAI:
            return try await analyzeFoodWithOpenAI(image: image, correctedDescription: correctedDescription)
        case .openRouter:
            return try await analyzeFoodWithOpenRouter(image: image, correctedDescription: correctedDescription)
        case .cloudflare:
            return try await analyzeFoodWithCloudflare(image: image, correctedDescription: correctedDescription)
        }
    }

    static func analyzeText(description: String) async throws -> NutritionResult {
        switch Config.selectedProvider {
        case .anthropic:
            return try await analyzeTextWithAnthropic(description: description)
        case .gemini:
            return try await analyzeTextWithGemini(description: description)
        case .openAI:
            return try await analyzeTextWithOpenAI(description: description)
        case .openRouter:
            return try await analyzeTextWithOpenRouter(description: description)
        case .cloudflare:
            return try await analyzeTextWithCloudflare(description: description)
        }
    }

    static func fetchOpenRouterModels(apiKey: String) async throws -> [OpenRouterModel] {
        var request = URLRequest(url: openRouterModelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.networkError
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.apiError(http.statusCode, body)
        }

        struct ModelsResponse: Decodable {
            let data: [Model]
        }

        struct Model: Decodable {
            struct Architecture: Decodable {
                let input_modalities: [String]?
                let output_modalities: [String]?
            }

            struct Pricing: Decodable {
                let prompt: String?
                let completion: String?
                let request: String?
            }

            let id: String
            let name: String
            let architecture: Architecture?
            let pricing: Pricing?
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)

        let preferredIDs = OpenRouterModel.recommended.map(\.id)
        let modelsFromAPI = decoded.data.filter { model in
            let outputs = model.architecture?.output_modalities ?? ["text"]
            guard outputs.contains("text") else { return false }
            return true
        }
        .map { model in
            let inputs = model.architecture?.input_modalities ?? []
            let supportsVision = inputs.contains("image")
            return OpenRouterModel(
                id: model.id,
                displayName: model.name,
                supportsVision: supportsVision,
                isRouter: false
            )
        }
        .sorted { sortOpenRouterModels($0, $1, preferredIDs: preferredIDs) }

        var models = OpenRouterModel.recommended
        models.append(contentsOf: modelsFromAPI)
        var seen = Set<String>()
        return models
            .filter { model in
                guard !seen.contains(model.id) else { return false }
                seen.insert(model.id)
                return true
            }
            .sorted { sortOpenRouterModels($0, $1, preferredIDs: preferredIDs) }
    }

    private static func sortOpenRouterModels(_ lhs: OpenRouterModel, _ rhs: OpenRouterModel, preferredIDs: [String]) -> Bool {
        let leftRank = preferredIDs.firstIndex(of: lhs.id) ?? Int.max
        let rightRank = preferredIDs.firstIndex(of: rhs.id) ?? Int.max

        if leftRank != rightRank {
            return leftRank < rightRank
        }

        if lhs.supportsVision != rhs.supportsVision {
            return lhs.supportsVision
        }

        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    static func fetchGeminiModels(apiKey: String) async throws -> [GeminiModel] {
        var components = URLComponents(url: geminiModelsURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey)
        ]

        guard let url = components?.url else {
            throw ClaudeError.parseError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.networkError
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.apiError(http.statusCode, body)
        }

        struct GeminiModelsResponse: Decodable {
            struct GeminiModelDTO: Decodable {
                struct InputTokenLimit: Decodable {}

                let name: String
                let displayName: String?
                let supportedGenerationMethods: [String]?
                let inputTokenLimit: Int?
            }

            let models: [GeminiModelDTO]?
        }

        let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)

        let models = (decoded.models ?? [])
            .filter { model in
                let methods = model.supportedGenerationMethods ?? []
                let id = model.name.replacingOccurrences(of: "models/", with: "")
                return methods.contains("generateContent") &&
                    GeminiModel.isVisionCapableID(id) &&
                    !GeminiModel.shouldResetSelection(id)
            }
            .map { model in
                let id = model.name.replacingOccurrences(of: "models/", with: "")
                return GeminiModel(
                    id: id,
                    displayName: model.displayName?.isEmpty == false ? model.displayName! : id
                )
            }
        let preferredIDs = GeminiModel.defaults.map(\.id)
        return rankModels(models, preferredIDs: preferredIDs)
    }

    static func fetchOpenAIModels(apiKey: String) async throws -> [OpenAIModel] {
        var request = URLRequest(url: openAIModelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.networkError
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.apiError(http.statusCode, body)
        }

        struct OpenAIModelsResponse: Decodable {
            struct OpenAIModelDTO: Decodable {
                let id: String
                let owned_by: String?
            }

            let data: [OpenAIModelDTO]
        }

        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)

        let blockedPrefixes = [
            "whisper",
            "tts-",
            "omni-moderation",
            "text-embedding",
            "davinci",
            "babbage",
            "gpt-image",
            "chatgpt-image",
            "gpt-realtime",
            "gpt-audio"
        ]

        let preferredPrefixes = [
            "gpt-5.5",
            "gpt-5.4",
            "gpt-5",
            "gpt-4.1",
            "gpt-4o"
        ]

        return decoded.data
            .filter { model in
                preferredPrefixes.contains { model.id.hasPrefix($0) } &&
                !blockedPrefixes.contains { model.id.hasPrefix($0) } &&
                OpenAIModel.isVisionCapableID(model.id)
            }
            .map { model in
                OpenAIModel(id: model.id, displayName: model.id)
            }
            .sorted { lhs, rhs in
                let preferredIDs = OpenAIModel.defaults.map(\.id)
                let leftRank = preferredIDs.firstIndex(of: lhs.id) ?? Int.max
                let rightRank = preferredIDs.firstIndex(of: rhs.id) ?? Int.max

                if leftRank != rightRank {
                    return leftRank < rightRank
                }

                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private static func analyzeFoodWithAnthropic(image: UIImage) async throws -> NutritionResult {
        let resized = resize(image, maxDimension: 1280)
        guard let jpeg = resized.jpegData(compressionQuality: 0.6) else {
            throw ClaudeError.imageEncodingFailed
        }

        let body: [String: Any] = [
            "model": Config.anthropicModelID,
            "max_tokens": 512,
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": jpeg.base64EncodedString()
                        ]
                    ],
                    [
                        "type": "text",
                        "text": imageNutritionPrompt
                    ]
                ]
            ]]
        ]

        return try await requestAnthropicResult(body: body, providerName: AIProvider.anthropic.displayName, modelUsed: Config.anthropicModelID)
    }

    private static func analyzeTextWithAnthropic(description: String) async throws -> NutritionResult {
        let prompt = textNutritionPrompt(for: description)

        let body: [String: Any] = [
            "model": Config.anthropicModelID,
            "max_tokens": 512,
            "messages": [[
                "role": "user",
                "content": prompt
            ]]
        ]

        return try await requestAnthropicResult(body: body, providerName: AIProvider.anthropic.displayName, modelUsed: Config.anthropicModelID)
    }

    private static func analyzeFoodWithAnthropic(image: UIImage, correctedDescription: String) async throws -> NutritionResult {
        let resized = resize(image, maxDimension: 1280)
        guard let jpeg = resized.jpegData(compressionQuality: 0.6) else {
            throw ClaudeError.imageEncodingFailed
        }

        let body: [String: Any] = [
            "model": Config.anthropicModelID,
            "max_tokens": 512,
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": jpeg.base64EncodedString()
                        ]
                    ],
                    [
                        "type": "text",
                        "text": correctedImageNutritionPrompt(for: correctedDescription)
                    ]
                ]
            ]]
        ]

        return try await requestAnthropicResult(body: body, providerName: AIProvider.anthropic.displayName, modelUsed: Config.anthropicModelID)
    }

    private static func analyzeFoodWithGemini(image: UIImage) async throws -> NutritionResult {
        let resized = resize(image, maxDimension: 960)
        guard let jpeg = resized.jpegData(compressionQuality: 0.55) else {
            throw ClaudeError.imageEncodingFailed
        }

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    [
                        "inline_data": [
                            "mime_type": "image/jpeg",
                            "data": jpeg.base64EncodedString()
                        ]
                    ],
                    [
                        "text": imageNutritionPrompt
                    ]
                ]
            ]],
            "generationConfig": geminiJSONGenerationConfig
        ]

        return try await requestGeminiResult(body: body, modelUsed: Config.geminiModelID)
    }

    private static func analyzeTextWithGemini(description: String) async throws -> NutritionResult {
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    [
                        "text": textNutritionPrompt(for: description)
                    ]
                ]
            ]],
            "generationConfig": geminiJSONGenerationConfig
        ]

        return try await requestGeminiResult(body: body, modelUsed: Config.geminiModelID)
    }

    private static func analyzeFoodWithGemini(image: UIImage, correctedDescription: String) async throws -> NutritionResult {
        let resized = resize(image, maxDimension: 960)
        guard let jpeg = resized.jpegData(compressionQuality: 0.55) else {
            throw ClaudeError.imageEncodingFailed
        }

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    [
                        "inline_data": [
                            "mime_type": "image/jpeg",
                            "data": jpeg.base64EncodedString()
                        ]
                    ],
                    [
                        "text": correctedImageNutritionPrompt(for: correctedDescription)
                    ]
                ]
            ]],
            "generationConfig": geminiJSONGenerationConfig
        ]

        return try await requestGeminiResult(body: body, modelUsed: Config.geminiModelID)
    }

    private static func analyzeFoodWithOpenAI(image: UIImage) async throws -> NutritionResult {
        let resized = resize(image, maxDimension: 1280)
        guard let jpeg = resized.jpegData(compressionQuality: 0.6) else {
            throw ClaudeError.imageEncodingFailed
        }

        let body: [String: Any] = [
            "model": Config.openAIModelID,
            "response_format": [
                "type": "json_object"
            ],
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "text",
                        "text": imageNutritionPrompt
                    ],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())",
                            "detail": "low"
                        ]
                    ]
                ]
            ]]
        ]

        return try await requestOpenAIResult(body: body, modelUsed: Config.openAIModelID)
    }

    private static func analyzeTextWithOpenAI(description: String) async throws -> NutritionResult {
        let body: [String: Any] = [
            "model": Config.openAIModelID,
            "response_format": [
                "type": "json_object"
            ],
            "messages": [[
                "role": "user",
                "content": textNutritionPrompt(for: description)
            ]]
        ]

        return try await requestOpenAIResult(body: body, modelUsed: Config.openAIModelID)
    }

    private static func analyzeFoodWithOpenAI(image: UIImage, correctedDescription: String) async throws -> NutritionResult {
        let resized = resize(image, maxDimension: 1280)
        guard let jpeg = resized.jpegData(compressionQuality: 0.6) else {
            throw ClaudeError.imageEncodingFailed
        }

        let body: [String: Any] = [
            "model": Config.openAIModelID,
            "response_format": [
                "type": "json_object"
            ],
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "text",
                        "text": correctedImageNutritionPrompt(for: correctedDescription)
                    ],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())",
                            "detail": "low"
                        ]
                    ]
                ]
            ]]
        ]

        return try await requestOpenAIResult(body: body, modelUsed: Config.openAIModelID)
    }

    private static func analyzeFoodWithOpenRouter(image: UIImage) async throws -> NutritionResult {
        let resized = resize(image, maxDimension: 1024)
        guard let jpeg = resized.jpegData(compressionQuality: 0.6) else {
            throw ClaudeError.imageEncodingFailed
        }

        let body: [String: Any] = [
            "model": Config.openRouterModelID,
            "max_tokens": 512,
            "response_format": openRouterJSONResponseFormat,
            "plugins": openRouterResponseHealingPlugin,
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "text",
                        "text": imageNutritionPrompt
                    ],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                        ]
                    ]
                ]
            ]]
        ]

        return try await requestOpenRouterResult(body: body)
    }

    private static func analyzeTextWithOpenRouter(description: String) async throws -> NutritionResult {
        let body: [String: Any] = [
            "model": Config.openRouterModelID,
            "max_tokens": 512,
            "response_format": openRouterJSONResponseFormat,
            "plugins": openRouterResponseHealingPlugin,
            "messages": [[
                "role": "user",
                "content": textNutritionPrompt(for: description)
            ]]
        ]

        return try await requestOpenRouterResult(body: body)
    }

    private static func analyzeFoodWithOpenRouter(image: UIImage, correctedDescription: String) async throws -> NutritionResult {
        let resized = resize(image, maxDimension: 1024)
        guard let jpeg = resized.jpegData(compressionQuality: 0.6) else {
            throw ClaudeError.imageEncodingFailed
        }

        let body: [String: Any] = [
            "model": Config.openRouterModelID,
            "max_tokens": 512,
            "response_format": openRouterJSONResponseFormat,
            "plugins": openRouterResponseHealingPlugin,
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "text",
                        "text": correctedImageNutritionPrompt(for: correctedDescription)
                    ],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                        ]
                    ]
                ]
            ]]
        ]

        return try await requestOpenRouterResult(body: body)
    }

    private static func analyzeFoodWithCloudflare(image: UIImage) async throws -> NutritionResult {
        let resized = resize(image, maxDimension: 960)
        guard let jpeg = resized.jpegData(compressionQuality: 0.55) else {
            throw ClaudeError.imageEncodingFailed
        }

        let body: [String: Any] = [
            "mode": "image",
            "provider": "cloudflare",
            "mimeType": "image/jpeg",
            "imageBase64": jpeg.base64EncodedString()
        ]

        return try await requestCloudflareResult(body: body)
    }

    private static func analyzeFoodWithCloudflare(image: UIImage, correctedDescription: String) async throws -> NutritionResult {
        let resized = resize(image, maxDimension: 960)
        guard let jpeg = resized.jpegData(compressionQuality: 0.55) else {
            throw ClaudeError.imageEncodingFailed
        }

        let body: [String: Any] = [
            "mode": "image",
            "provider": "cloudflare",
            "mimeType": "image/jpeg",
            "imageBase64": jpeg.base64EncodedString(),
            "description": correctedDescription
        ]

        return try await requestCloudflareResult(body: body)
    }

    private static func analyzeTextWithCloudflare(description: String) async throws -> NutritionResult {
        let body: [String: Any] = [
            "mode": "text",
            "provider": "cloudflare",
            "description": description
        ]

        return try await requestCloudflareResult(body: body)
    }

    private static func requestCloudflareResult(body: [String: Any]) async throws -> NutritionResult {
        var request = URLRequest(url: mealvueWorkerURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let token = Config.mealvueClientToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if (error as NSError).code == NSURLErrorTimedOut {
                throw ClaudeError.apiError(NSURLErrorTimedOut, "MealVue AI timed out. Try again in a moment.")
            }
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.networkError
        }

        guard http.statusCode == 200 else {
            throw ClaudeError.apiError(http.statusCode, summarizedResponseBody(data))
        }

        return try parseBackendNutrition(data)
    }

    private static func requestAnthropicResult(body: [String: Any], providerName: String, modelUsed: String) async throws -> NutritionResult {
        guard !Config.anthropicAPIKey.isEmpty else {
            throw ClaudeError.missingAPIKey
        }

        var request = URLRequest(url: anthropicURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.anthropicAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.networkError
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.apiError(http.statusCode, body)
        }

        struct APIResponse: Decodable {
            struct Block: Decodable {
                let type: String
                let text: String
            }

            let content: [Block]
        }

        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)

        guard let text = apiResponse.content.first?.text else {
            throw ClaudeError.noContent
        }

        return try parse(text, providerName: providerName, modelUsed: modelUsed)
    }

    private static func requestGeminiResult(body: [String: Any], modelUsed: String) async throws -> NutritionResult {
        guard !Config.geminiAPIKey.isEmpty else {
            throw ClaudeError.missingAPIKey
        }

        guard let model = modelUsed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw ClaudeError.parseError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if (error as NSError).code == NSURLErrorTimedOut {
                throw ClaudeError.apiError(NSURLErrorTimedOut, "Google Gemini timed out. Try Gemini 2.5 Flash or Flash-Lite, check the API key quota, or switch providers temporarily.")
            }
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.networkError
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.apiError(http.statusCode, body)
        }

        struct GeminiResponse: Decodable {
            struct PromptFeedback: Decodable {
                let blockReason: String?
            }

            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        let text: String?
                    }

                    let parts: [Part]
                }

                let content: Content?
            }

            let candidates: [Candidate]?
            let promptFeedback: PromptFeedback?
        }

        let decoded: GeminiResponse
        do {
            decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        } catch {
            throw ClaudeError.apiError(200, "Gemini returned an unexpected response: \(summarizedResponseBody(data))")
        }
        let text = decoded.candidates?
            .first?
            .content?
            .parts
            .compactMap { $0.text }
            .joined(separator: "\n") ?? ""

        guard !text.isEmpty else {
            if let blockReason = decoded.promptFeedback?.blockReason, !blockReason.isEmpty {
                throw ClaudeError.apiError(400, "Gemini blocked the request: \(blockReason)")
            }
            throw ClaudeError.apiError(200, "Gemini returned no usable text. Raw response: \(summarizedResponseBody(data))")
        }

        do {
            return try parse(text, providerName: AIProvider.gemini.displayName, modelUsed: modelUsed)
        } catch {
            throw ClaudeError.apiError(200, "Gemini returned unparseable text: \(summarizedText(text))")
        }
    }

    private static func requestOpenAIResult(body: [String: Any], modelUsed: String) async throws -> NutritionResult {
        guard !Config.openAIAPIKey.isEmpty else {
            throw ClaudeError.missingAPIKey
        }

        let (data, response) = try await performOpenAIRequest(body: body)

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.networkError
        }

        guard http.statusCode == 200 else {
            if [400, 404, 422].contains(http.statusCode),
               modelUsed != OpenAIModel.defaultModel.id {
                var fallbackBody = body
                fallbackBody["model"] = OpenAIModel.defaultModel.id
                let (fallbackData, fallbackResponse) = try await performOpenAIRequest(body: fallbackBody)

                guard let fallbackHTTP = fallbackResponse as? HTTPURLResponse else {
                    throw ClaudeError.networkError
                }

                guard fallbackHTTP.statusCode == 200 else {
                    let fallbackBodyText = String(data: fallbackData, encoding: .utf8) ?? ""
                    throw ClaudeError.apiError(fallbackHTTP.statusCode, fallbackBodyText)
                }

                return try decodeOpenAIResult(from: fallbackData, modelUsed: OpenAIModel.defaultModel.id)
            }

            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.apiError(http.statusCode, body)
        }

        return try decodeOpenAIResult(from: data, modelUsed: modelUsed)
    }

    private static func performOpenAIRequest(body: [String: Any]) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: openAIURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await URLSession.shared.data(for: request)
    }

    private static func decodeOpenAIResult(from data: Data, modelUsed: String) throws -> NutritionResult {
        struct OpenAIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?
                }

                let message: Message
            }

            let choices: [Choice]
        }

        let decoded: OpenAIResponse
        do {
            decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        } catch {
            throw ClaudeError.apiError(200, "OpenAI returned an unexpected response: \(summarizedResponseBody(data))")
        }
        guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
            throw ClaudeError.apiError(200, "OpenAI returned no usable text. Raw response: \(summarizedResponseBody(data))")
        }

        do {
            return try parse(text, providerName: AIProvider.openAI.displayName, modelUsed: modelUsed)
        } catch {
            throw ClaudeError.apiError(200, "OpenAI returned unparseable text: \(summarizedText(text))")
        }
    }

    private static func requestOpenRouterResult(body: [String: Any]) async throws -> NutritionResult {
        guard !Config.openRouterAPIKey.isEmpty else {
            throw ClaudeError.missingAPIKey
        }

        let normalizedBody = normalizedOpenRouterBody(from: body)
        let (data, response) = try await performOpenRouterRequest(body: normalizedBody)

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.networkError
        }

        guard http.statusCode == 200 else {
            if http.statusCode == 404,
               let selectedModel = normalizedBody["model"] as? String,
               selectedModel != OpenRouterModel.autoRouter.id {
                var fallbackBody = normalizedBody
                fallbackBody["model"] = OpenRouterModel.autoRouter.id
                let (fallbackData, fallbackResponse) = try await performOpenRouterRequest(body: fallbackBody)

                guard let fallbackHTTP = fallbackResponse as? HTTPURLResponse else {
                    throw ClaudeError.networkError
                }

                guard fallbackHTTP.statusCode == 200 else {
                    if fallbackHTTP.statusCode == 404 {
                        var freeRouterBody = normalizedBody
                        freeRouterBody["model"] = OpenRouterModel.freeRouter.id
                        let (freeData, freeResponse) = try await performOpenRouterRequest(body: freeRouterBody)

                        guard let freeHTTP = freeResponse as? HTTPURLResponse else {
                            throw ClaudeError.networkError
                        }

                        guard freeHTTP.statusCode == 200 else {
                            let freeBodyText = String(data: freeData, encoding: .utf8) ?? ""
                            throw ClaudeError.apiError(freeHTTP.statusCode, freeBodyText)
                        }

                        return try decodeOpenRouterResult(
                            from: freeData,
                            providerName: AIProvider.openRouter.displayName,
                            modelUsed: OpenRouterModel.freeRouter.id
                        )
                    }

                    let fallbackBodyText = String(data: fallbackData, encoding: .utf8) ?? ""
                    throw ClaudeError.apiError(fallbackHTTP.statusCode, fallbackBodyText)
                }

                return try decodeOpenRouterResult(
                    from: fallbackData,
                    providerName: AIProvider.openRouter.displayName,
                    modelUsed: OpenRouterModel.autoRouter.id
                )
            }

            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.apiError(http.statusCode, body)
        }

        let selectedModel = (normalizedBody["model"] as? String) ?? Config.openRouterModelID
        return try decodeOpenRouterResult(
            from: data,
            providerName: AIProvider.openRouter.displayName,
            modelUsed: selectedModel
        )
    }

    private static func normalizedOpenRouterBody(from body: [String: Any]) -> [String: Any] {
        var normalizedBody = body
        let selectedModel = (body["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        normalizedBody["model"] = selectedModel.isEmpty ? OpenRouterModel.autoRouter.id : selectedModel
        normalizedBody["provider"] = [
            "sort": "latency",
            "allow_fallbacks": true,
            "require_parameters": false
        ]
        return normalizedBody
    }

    private static var geminiJSONGenerationConfig: [String: Any] {
        [
            "response_mime_type": "application/json",
            "max_output_tokens": 700
        ]
    }

    private static var openRouterJSONResponseFormat: [String: Any] {
        [
            "type": "json_object"
        ]
    }

    private static var openRouterResponseHealingPlugin: [[String: Any]] {
        [
            ["id": "response-healing"]
        ]
    }

    private static func performOpenRouterRequest(body: [String: Any]) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: openRouterChatURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.openRouterAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("MealVue", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await URLSession.shared.data(for: request)
    }

    private static func decodeOpenRouterResult(from data: Data, providerName: String, modelUsed: String) throws -> NutritionResult {
        struct OpenRouterResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }

                let message: Message
            }

            let choices: [Choice]
        }

        let decoded: OpenRouterResponse
        do {
            decoded = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
        } catch {
            throw ClaudeError.incompatibleModel
        }
        guard let text = decoded.choices.first?.message.content else {
            throw ClaudeError.incompatibleModel
        }

        do {
            return try parse(text, providerName: providerName, modelUsed: modelUsed)
        } catch {
            throw ClaudeError.incompatibleModel
        }
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)

        guard longest > maxDimension else { return image }

        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func summarizedResponseBody(_ data: Data) -> String {
        let raw = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
        return summarizedText(raw)
    }

    private static func summarizedText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "<empty>" }
        if trimmed.count <= 600 {
            return trimmed
        }
        return String(trimmed.prefix(600)) + "..."
    }

    private static func parseBackendNutrition(_ data: Data) throws -> NutritionResult {
        let json: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ClaudeError.parseError
            }
            json = object
        } catch {
            throw ClaudeError.parseError
        }

        if let error = json["error"] as? String {
            throw ClaudeError.apiError(502, error)
        }

        func string(_ key: String) -> String {
            (json[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func double(_ key: String) -> Double {
            if let value = json[key] as? Double { return value }
            if let value = json[key] as? Int { return Double(value) }
            return 0
        }

        func int(_ key: String) -> Int {
            if let value = json[key] as? Int { return value }
            if let value = json[key] as? Double { return Int(value) }
            return 0
        }

        return NutritionResult(
            foodName: string("food_name").isEmpty ? "Unknown food" : string("food_name"),
            estimatedQuantity: string("estimated_quantity"),
            calories: int("calories"),
            proteinG: double("protein_g"),
            carbsG: double("carbs_g"),
            fatG: double("fat_g"),
            fiberG: double("fiber_g"),
            sodiumMg: double("sodium_mg"),
            potassiumMg: double("potassium_mg"),
            phosphorusMg: double("phosphorus_mg"),
            confidence: string("confidence").isEmpty ? "medium" : string("confidence"),
            notes: string("notes"),
            kidneyWarning: string("kidney_warning"),
            heartWarning: string("heart_warning"),
            sodiumWarning: string("sodium_warning"),
            potassiumWarning: string("potassium_warning"),
            phosphorusWarning: string("phosphorus_warning"),
            providerName: AIProvider.cloudflare.displayName,
            modelUsed: "cloudflare-workers-ai"
        )
    }

    private static func parse(_ text: String, providerName: String, modelUsed: String) throws -> NutritionResult {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            throw ClaudeError.parseError
        }

        let jsonString = String(text[start...end])
        guard let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError.parseError
        }

        func double(_ key: String) -> Double {
            if let value = json[key] as? Double { return value }
            if let value = json[key] as? Int { return Double(value) }
            return 0
        }

        func int(_ key: String) -> Int {
            if let value = json[key] as? Int { return value }
            if let value = json[key] as? Double { return Int(value) }
            return 0
        }

        func normalizedWarning(_ key: String) -> String {
            let raw = (json[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return "" }

            let lowered = raw.lowercased()

            // Suppress non-actionable warnings when the model only indicates a moderate amount.
            if lowered.contains("moderate") || lowered.contains("medium") {
                return ""
            }

            return raw
        }

        return NutritionResult(
            foodName: json["food_name"] as? String ?? "Unknown food",
            estimatedQuantity: json["estimated_quantity"] as? String ?? "",
            calories: int("calories"),
            proteinG: double("protein_g"),
            carbsG: double("carbs_g"),
            fatG: double("fat_g"),
            fiberG: double("fiber_g"),
            sodiumMg: double("sodium_mg"),
            potassiumMg: double("potassium_mg"),
            phosphorusMg: double("phosphorus_mg"),
            confidence: json["confidence"] as? String ?? "medium",
            notes: json["notes"] as? String ?? "",
            kidneyWarning: normalizedWarning("kidney_warning"),
            heartWarning: normalizedWarning("heart_warning"),
            sodiumWarning: normalizedWarning("sodium_warning"),
            potassiumWarning: normalizedWarning("potassium_warning"),
            phosphorusWarning: normalizedWarning("phosphorus_warning"),
            providerName: providerName,
            modelUsed: modelUsed
        )
    }

    private static var imageNutritionPrompt: String {
        """
    Analyze this food image and return ONLY a valid JSON object:

    {
      "food_name": "specific food name",
      "estimated_quantity": "e.g. 1 cup cooked rice, 200g chicken",
      "calories": 450,
      "protein_g": 28.0,
      "carbs_g": 45.0,
      "fat_g": 14.0,
      "fiber_g": 3.0,
      "sodium_mg": 950,
      "potassium_mg": 540,
      "phosphorus_mg": 320,
      "confidence": "high",
      "notes": "brief note on assumptions or portion estimate",
      "kidney_warning": "brief warning for someone with kidney disease, otherwise empty string",
      "heart_warning": "brief warning for someone focused on heart health, otherwise empty string",
      "sodium_warning": "brief warning if salt/sodium appears too high, otherwise empty string",
      "potassium_warning": "brief warning if potassium appears too high, otherwise empty string",
      "phosphorus_warning": "brief warning if phosphorus appears too high, otherwise empty string"
    }

    \(healthWarningRules)
    """
    }

    private static func textNutritionPrompt(for description: String) -> String {
        """
        The user described their food as: "\(description)"

        Return ONLY a valid JSON object:

        {
          "food_name": "specific food name",
          "estimated_quantity": "typical serving",
          "calories": 450,
          "protein_g": 28.0,
          "carbs_g": 45.0,
          "fat_g": 14.0,
          "fiber_g": 3.0,
          "sodium_mg": 950,
          "potassium_mg": 540,
          "phosphorus_mg": 320,
          "confidence": "medium",
          "notes": "brief note on assumptions or portion estimate",
          "kidney_warning": "brief warning for someone with kidney disease, otherwise empty string",
          "heart_warning": "brief warning for someone focused on heart health, otherwise empty string",
          "sodium_warning": "brief warning if salt/sodium appears too high, otherwise empty string",
          "potassium_warning": "brief warning if potassium appears too high, otherwise empty string",
          "phosphorus_warning": "brief warning if phosphorus appears too high, otherwise empty string"
        }

        \(healthWarningRules)
        """
    }

    private static func correctedImageNutritionPrompt(for correctedDescription: String) -> String {
        """
        The user corrected the photo analysis and says this image shows: "\(correctedDescription)".

        Use that correction as the primary description of the meal. Use the image to refine portion size and nutrition estimates, but do not rename the food to something inconsistent with the user's correction unless the image clearly proves the correction is impossible.

        Return ONLY a valid JSON object:

        {
          "food_name": "specific food name",
          "estimated_quantity": "typical serving",
          "calories": 450,
          "protein_g": 28.0,
          "carbs_g": 45.0,
          "fat_g": 14.0,
          "fiber_g": 3.0,
          "sodium_mg": 950,
          "potassium_mg": 540,
          "phosphorus_mg": 320,
          "confidence": "medium",
          "notes": "brief note on assumptions or portion estimate",
          "kidney_warning": "brief warning for someone with kidney disease, otherwise empty string",
          "heart_warning": "brief warning for someone focused on heart health, otherwise empty string",
          "sodium_warning": "brief warning if salt/sodium appears too high, otherwise empty string",
          "potassium_warning": "brief warning if potassium appears too high, otherwise empty string",
          "phosphorus_warning": "brief warning if phosphorus appears too high, otherwise empty string"
        }

        \(healthWarningRules)
        """
    }

    private static var healthWarningRules: String {
        var rules: [String] = [
            "- All numeric fields must be numbers, not strings",
            "- calories must be an integer",
            "- Estimate sodium_mg, potassium_mg, and phosphorus_mg as daily nutrient amounts for this meal in milligrams"
        ]

        if Config.kidneyChecksEnabled {
            rules.append("- If the food appears risky for kidney disease because it is high in sodium, potassium, phosphorus, or otherwise commonly restricted, set kidney_warning to a short warning. Otherwise set kidney_warning to an empty string.")
        } else {
            rules.append("- Set kidney_warning to an empty string.")
        }

        if Config.heartChecksEnabled {
            rules.append("- If the food appears risky for heart health because it is high in sodium, saturated fat, trans fat, or heavily processed, set heart_warning to a short warning. Otherwise set heart_warning to an empty string.")
        } else {
            rules.append("- Set heart_warning to an empty string.")
        }

        if Config.kidneyChecksEnabled || Config.heartChecksEnabled {
            rules.append("- Only set sodium_warning when sodium is clearly high for the meal. Do not warn for moderate or borderline sodium. Otherwise set sodium_warning to an empty string.")
            rules.append("- Only set potassium_warning when potassium is clearly high for the meal. Do not warn for moderate or borderline potassium. Otherwise set potassium_warning to an empty string.")
            rules.append("- Only set phosphorus_warning when phosphorus is clearly high for the meal. Do not warn for moderate or borderline phosphorus. Otherwise set phosphorus_warning to an empty string.")
        } else {
            rules.append("- Set sodium_warning, potassium_warning, and phosphorus_warning to empty strings.")
        }

        return rules.joined(separator: "\n")
    }
}

private enum ClaudeError: LocalizedError {
    case missingAPIKey
    case imageEncodingFailed
    case networkError
    case apiError(Int, String)
    case noContent
    case parseError
    case incompatibleModel

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            switch Config.selectedProvider {
            case .anthropic:
                return "Add your Anthropic API key in Settings."
            case .gemini:
                return "Add your Google Gemini API key in Settings."
            case .openAI:
                return "Add your OpenAI API key in Settings."
            case .openRouter:
                return "Add your OpenRouter API key in Settings."
            case .cloudflare:
                return "MealVue AI is not available. Try again later or use manual entry."
            }
        case .imageEncodingFailed:
            return "Could not encode image."
        case .networkError:
            return "Network error."
        case .apiError(let code, let body):
            if code == NSURLErrorTimedOut {
                return body
            }
            if code == 404 {
                return "API error 404. The selected model or endpoint was not found for the current provider."
            }
            if code == 402 {
                return "API error 402. This model may require payment or credits on the current provider."
            }
            if code == 429 {
                return "AI rate limit reached. Wait a moment and try again, or switch to another model/provider."
            }
            if body.localizedCaseInsensitiveContains("does not support image") ||
                body.localizedCaseInsensitiveContains("vision") ||
                body.localizedCaseInsensitiveContains("multimodal") ||
                body.localizedCaseInsensitiveContains("incompatible") {
                return "The selected AI model is not compatible with food photos. Choose a vision-compatible model or use MealVue AI."
            }
            if body.isEmpty {
                return "API error \(code)."
            }
            return "API error \(code): \(body)"
        case .noContent:
            return "No content returned."
        case .parseError:
            return "Could not parse the AI response."
        case .incompatibleModel:
            return "Incompatible Model - Choose Another Model"
        }
    }
}

private struct GuideCard: View {
    let group: FoodGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: group.systemImage)
                    .foregroundStyle(group.tint)
                Text(group.title)
                    .font(.headline)
            }

            ForEach(group.items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(group.tint)
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)
                    Text(item)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct MenuPlanCard: View {
    let plan: MenuPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(plan.title)
                .font(.headline)

            ForEach(plan.meals) { meal in
                VStack(alignment: .leading, spacing: 3) {
                    Text(meal.name)
                        .font(.subheadline.weight(.semibold))
                    Text(meal.items)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct MedicationPageCard: View {
    let page: MedicationPage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: page.systemImage)
                    .foregroundStyle(page.tint)
                Text(page.title)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(page.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct MedicationDetailView: View {
    let page: MedicationPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(page.title, systemImage: page.systemImage)
                        .font(.title.bold())
                        .foregroundStyle(page.tint)
                    Text(page.summary)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [page.tint.opacity(0.16), Color.blue.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                MedicationSectionCard(
                    title: "Usually Better Or Commonly Used",
                    tint: .green,
                    items: page.safeItems
                )

                MedicationSectionCard(
                    title: "Use Caution Or Ask First",
                    tint: .orange,
                    items: page.cautionItems
                )
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MedicationSectionCard: View {
    let title: String
    let tint: Color
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(tint)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)
                    Text(item)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    var onImage: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: ImagePicker

        init(parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true) {
                guard let image else { return }
                self.parent.onImage(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

private func format(_ value: Double) -> String {
    if value.truncatingRemainder(dividingBy: 1) == 0 {
        return "\(Int(value))"
    }

    return String(format: "%.1f", value)
}

#Preview {
    ContentView()
        .modelContainer(for: FoodEntry.self, inMemory: true)
}
