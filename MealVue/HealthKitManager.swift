import Foundation
import HealthKit
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class HealthKitManager {
    enum AuthorizationState {
        case unavailable
        case capabilityMissing
        case idle
        case requesting
        case authorized
        case partial
        case failed
    }

    private let healthStore = HKHealthStore()
    private let nutritionIdentifiers: [HKQuantityTypeIdentifier] = [
        .dietaryEnergyConsumed,
        .dietaryFiber,
        .dietaryProtein,
        .dietarySodium,
        .dietaryPotassium,
        .dietaryPhosphorus
    ]
    private let exportedNutritionIdentifiers: [HKQuantityTypeIdentifier] = [
        .dietaryEnergyConsumed,
        .dietaryCarbohydrates,
        .dietaryFatTotal,
        .dietaryFiber,
        .dietaryProtein,
        .dietarySodium,
        .dietaryPotassium,
        .dietaryPhosphorus
    ]

    var authorizationState: AuthorizationState
    var isLoading = false
    var lastError = ""
    var statusDetail = ""
    var snapshot = HealthTrendsSnapshot.empty

    init() {
        authorizationState = HKHealthStore.isHealthDataAvailable() ? .idle : .unavailable
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var supportsClinicalRecords: Bool {
        isAvailable && healthStore.supportsHealthRecords()
    }

    var canRequestAuthorization: Bool {
        isAvailable && !isLoading
    }

    func requestAuthorization() async {
        guard isAvailable else {
            authorizationState = .unavailable
            lastError = "Health data is not available on this device."
            return
        }

        authorizationState = .requesting
        isLoading = true
        lastError = ""

        do {
            try await healthStore.requestAuthorization(
                toShare: nutritionSampleTypes,
                read: requestedReadTypes
            )
            await refresh()
        } catch {
            authorizationState = .failed
            lastError = error.localizedDescription
            statusDetail = "HealthKit authorization request failed."
            isLoading = false
        }
    }

    func refresh() async {
        guard isAvailable else {
            authorizationState = .unavailable
            lastError = "Health data is not available on this device."
            return
        }

        isLoading = true
        lastError = ""

        do {
            async let nutrition = fetchNutritionTrend(days: 7)
            async let labs = fetchRecentKidneyLabs(limit: 20)
            let refreshedSnapshot = try await HealthTrendsSnapshot(
                dailyNutrition: nutrition,
                recentLabs: labs
            )
            snapshot = refreshedSnapshot
            updateAuthorizationStatus()
        } catch {
            authorizationState = .failed
            lastError = error.localizedDescription
            statusDetail = "HealthKit read failed."
        }

        isLoading = false
    }

    func save(entry: FoodEntry) async throws {
        guard isAvailable else { return }

        guard let foodCorrelation = foodCorrelation(for: entry) else { return }
        try await save(samples: [foodCorrelation])
    }

    func deleteExportedMeal(entryID: UUID) async throws {
        guard isAvailable else { return }

        guard let correlation = try await exportedFoodCorrelation(for: entryID) else { return }
        let objects = Array(correlation.objects)

        if !objects.isEmpty {
            try await healthStore.delete(objects)
        }

        try await healthStore.delete(correlation)
    }

    private var nutritionSampleTypes: Set<HKSampleType> {
        Set(exportedNutritionIdentifiers.compactMap(HKObjectType.quantityType))
    }

    private var requestedReadTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>(nutritionIdentifiers.compactMap(HKObjectType.quantityType))

        if let labType = HKObjectType.clinicalType(forIdentifier: .labResultRecord),
           supportsClinicalRecords {
            types.insert(labType)
        }

        return types
    }

    private func updateAuthorizationStatus() {
        let writeStatuses = exportedNutritionIdentifiers.map { identifier in
            healthStore.authorizationStatus(for: HKObjectType.quantityType(forIdentifier: identifier)!)
        }

        if writeStatuses.allSatisfy({ $0 == .sharingAuthorized }) {
            authorizationState = .authorized
            statusDetail = "MealVue can write nutrition samples to Apple Health."
            return
        }

        if writeStatuses.allSatisfy({ $0 == .notDetermined }) {
            authorizationState = .capabilityMissing
            statusDetail = "HealthKit did not register this app. Check the target HealthKit capability and reinstall."
            return
        }

        authorizationState = .partial
        statusDetail = "HealthKit is available, but write access for one or more nutrition types is missing."
    }

    private func fetchNutritionTrend(days: Int) async throws -> [HealthNutritionDay] {
        let calendar = Calendar.current

        return try await withThrowingTaskGroup(of: HealthNutritionDay.self) { group in
            for offset in 0..<days {
                group.addTask { [healthStore, nutritionIdentifiers] in
                    let date = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: Date())) ?? Date()
                    let endDate = calendar.date(byAdding: .day, value: 1, to: date) ?? date

                    async let protein = Self.fetchCumulativeValue(
                        for: .dietaryProtein,
                        unit: .gram(),
                        startDate: date,
                        endDate: endDate,
                        healthStore: healthStore
                    )
                    async let calories = Self.fetchCumulativeValue(
                        for: .dietaryEnergyConsumed,
                        unit: .largeCalorie(),
                        startDate: date,
                        endDate: endDate,
                        healthStore: healthStore
                    )
                    async let fiber = Self.fetchCumulativeValue(
                        for: .dietaryFiber,
                        unit: .gram(),
                        startDate: date,
                        endDate: endDate,
                        healthStore: healthStore
                    )
                    async let sodium = Self.fetchCumulativeValue(
                        for: .dietarySodium,
                        unit: .gramUnit(with: .milli),
                        startDate: date,
                        endDate: endDate,
                        healthStore: healthStore
                    )
                    async let potassium = Self.fetchCumulativeValue(
                        for: .dietaryPotassium,
                        unit: .gramUnit(with: .milli),
                        startDate: date,
                        endDate: endDate,
                        healthStore: healthStore
                    )
                    async let phosphorus = Self.fetchCumulativeValue(
                        for: .dietaryPhosphorus,
                        unit: .gramUnit(with: .milli),
                        startDate: date,
                        endDate: endDate,
                        healthStore: healthStore
                    )

                    _ = nutritionIdentifiers

                    return HealthNutritionDay(
                        date: date,
                        summary: HealthNutritionSummary(
                            calories: try await calories,
                            proteinG: try await protein,
                            fiberG: try await fiber,
                            sodiumMg: try await sodium,
                            potassiumMg: try await potassium,
                            phosphorusMg: try await phosphorus
                        )
                    )
                }
            }

            var days: [HealthNutritionDay] = []
            for try await day in group {
                days.append(day)
            }
            return days.sorted(by: { $0.date < $1.date })
        }
    }

    private func fetchRecentKidneyLabs(limit: Int) async throws -> [KidneyLabResult] {
        guard supportsClinicalRecords,
              let labType = HKObjectType.clinicalType(forIdentifier: .labResultRecord) else {
            return []
        }

        let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKClinicalRecord], Error>) in
            let query = HKSampleQuery(
                sampleType: labType,
                predicate: nil,
                limit: limit,
                sortDescriptors: sortDescriptors
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: results as? [HKClinicalRecord] ?? [])
            }

            healthStore.execute(query)
        }

        return samples.compactMap(Self.parseKidneyLab)
    }

    private static func fetchCumulativeValue(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        startDate: Date,
        endDate: Date,
        healthStore: HKHealthStore
    ) async throws -> Double {
        let quantityType = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let samplePredicate = HKSamplePredicate.quantitySample(type: quantityType, predicate: predicate)
        let descriptor = HKStatisticsQueryDescriptor(predicate: samplePredicate, options: .cumulativeSum)
        let result = try await descriptor.result(for: healthStore)
        return result?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    private func nutritionSamples(for entry: FoodEntry) -> [HKQuantitySample] {
        let values: [(HKQuantityTypeIdentifier, Double, HKUnit)] = [
            (.dietaryEnergyConsumed, Double(entry.calories), .largeCalorie()),
            (.dietaryCarbohydrates, entry.carbsG, .gram()),
            (.dietaryFatTotal, entry.fatG, .gram()),
            (.dietaryFiber, entry.fiberG, .gram()),
            (.dietaryProtein, entry.proteinG, .gram()),
            (.dietarySodium, entry.sodiumMg, .gramUnit(with: .milli)),
            (.dietaryPotassium, entry.potassiumMg, .gramUnit(with: .milli)),
            (.dietaryPhosphorus, entry.phosphorusMg, .gramUnit(with: .milli))
        ]

        return values.compactMap { identifier, amount, unit in
            guard amount > 0 else { return nil }
            let quantityType = HKQuantityType(identifier)
            let quantity = HKQuantity(unit: unit, doubleValue: amount)
            return HKQuantitySample(
                type: quantityType,
                quantity: quantity,
                start: entry.timestamp,
                end: entry.timestamp,
                metadata: [
                    HKMetadataKeyFoodType: entry.foodName,
                    HKMetadataKeyExternalUUID: entry.entryId.uuidString
                ]
            )
        }
    }

    private func foodCorrelation(for entry: FoodEntry) -> HKCorrelation? {
        let samples = nutritionSamples(for: entry)
        guard !samples.isEmpty else { return nil }

        let foodType = HKCorrelationType(.food)
        let metadata: [String: Any] = [
            HKMetadataKeyFoodType: entry.foodName,
            HKMetadataKeyExternalUUID: entry.entryId.uuidString,
            "MealVueEstimatedQuantity": entry.estimatedQuantity,
            "MealVueConfidence": entry.confidence
        ]

        return HKCorrelation(
            type: foodType,
            start: entry.timestamp,
            end: entry.timestamp,
            objects: Set(samples),
            metadata: metadata
        )
    }

    private func save(samples: [HKSample]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(samples) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitManagerError.saveFailed)
                }
            }
        }
    }

    private func exportedFoodCorrelation(for entryID: UUID) async throws -> HKCorrelation? {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            operatorType: .equalTo,
            value: entryID.uuidString
        )

        let results = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCorrelation], Error>) in
            let query = HKSampleQuery(
                sampleType: HKCorrelationType(.food),
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: samples as? [HKCorrelation] ?? [])
            }

            healthStore.execute(query)
        }

        return results.first
    }

    private static func parseKidneyLab(from record: HKClinicalRecord) -> KidneyLabResult? {
        guard let resource = record.fhirResource else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: resource.data) as? [String: Any] else {
            return nil
        }

        let title = normalizedObservationName(from: json) ?? record.displayName
        guard matchesKidneyLab(title) else {
            return nil
        }

        let issuedDate = observationDate(from: json) ?? record.endDate
        let source = resource.sourceURL?.host ?? record.sourceRevision.source.name

        if let components = json["component"] as? [[String: Any]] {
            for component in components {
                let componentTitle = normalizedObservationName(from: component) ?? title
                guard matchesKidneyLab(componentTitle) else { continue }
                if let result = makeLabResult(title: componentTitle, payload: component, date: issuedDate, source: source) {
                    return result
                }
            }
        }

        return makeLabResult(title: title, payload: json, date: issuedDate, source: source)
    }

    private static func makeLabResult(
        title: String,
        payload: [String: Any],
        date: Date,
        source: String
    ) -> KidneyLabResult? {
        guard let valueQuantity = payload["valueQuantity"] as? [String: Any] else {
            return KidneyLabResult(
                name: title,
                valueText: "Available in Health Records",
                date: date,
                source: source
            )
        }

        let value: String
        if let number = valueQuantity["value"] as? Double {
            value = number.formatted(.number.precision(.fractionLength(0...2)))
        } else if let number = valueQuantity["value"] as? NSNumber {
            value = number.doubleValue.formatted(.number.precision(.fractionLength(0...2)))
        } else {
            value = "Recorded"
        }

        let unit = valueQuantity["unit"] as? String ?? valueQuantity["code"] as? String ?? ""
        let display = unit.isEmpty ? value : "\(value) \(unit)"

        return KidneyLabResult(
            name: title,
            valueText: display,
            date: date,
            source: source
        )
    }

    private static func normalizedObservationName(from payload: [String: Any]) -> String? {
        if let code = payload["code"] as? [String: Any] {
            if let text = code["text"] as? String, !text.isEmpty {
                return text
            }

            if let codings = code["coding"] as? [[String: Any]] {
                for coding in codings {
                    if let display = coding["display"] as? String, !display.isEmpty {
                        return display
                    }
                }
            }
        }

        return nil
    }

    private static func observationDate(from payload: [String: Any]) -> Date? {
        let formatter = ISO8601DateFormatter()
        let keys = ["effectiveDateTime", "issued"]

        for key in keys {
            if let string = payload[key] as? String,
               let date = formatter.date(from: string) {
                return date
            }
        }

        return nil
    }

    private static func matchesKidneyLab(_ title: String) -> Bool {
        let normalized = title.lowercased()

        return normalized.contains("creatinine")
            || normalized.contains("egfr")
            || normalized.contains("glomerular filtration")
            || normalized.contains("potassium")
            || normalized.contains("phosphorus")
            || normalized.contains("phosphate")
    }
}

enum HealthKitManagerError: LocalizedError {
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "HealthKit did not confirm the nutrition samples were saved."
        }
    }
}

struct HealthTrendsSnapshot {
    let dailyNutrition: [HealthNutritionDay]
    let recentLabs: [KidneyLabResult]

    static let empty = HealthTrendsSnapshot(dailyNutrition: [], recentLabs: [])

    var todayNutrition: HealthNutritionSummary {
        dailyNutrition.last?.summary ?? .zero
    }
}

struct HealthNutritionDay: Identifiable {
    let date: Date
    let summary: HealthNutritionSummary

    var id: Date { date }
}

struct HealthNutritionSummary {
    let calories: Double
    let proteinG: Double
    let fiberG: Double
    let sodiumMg: Double
    let potassiumMg: Double
    let phosphorusMg: Double

    static let zero = HealthNutritionSummary(
        calories: 0,
        proteinG: 0,
        fiberG: 0,
        sodiumMg: 0,
        potassiumMg: 0,
        phosphorusMg: 0
    )
}

struct KidneyLabResult: Identifiable {
    let id = UUID()
    let name: String
    let valueText: String
    let date: Date
    let source: String
}

struct HealthTrendsView: View {
    @Environment(HealthKitManager.self) private var healthKitManager
    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var entries: [FoodEntry]

    private var recentMealVueSummary: HealthNutritionSummary {
        let cutoff = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? .distantPast
        let recentEntries = entries.filter { $0.timestamp >= cutoff }

        return HealthNutritionSummary(
            calories: Double(recentEntries.reduce(0) { $0 + $1.calories }),
            proteinG: recentEntries.reduce(0) { $0 + $1.proteinG },
            fiberG: recentEntries.reduce(0) { $0 + $1.fiberG },
            sodiumMg: recentEntries.reduce(0) { $0 + $1.sodiumMg },
            potassiumMg: recentEntries.reduce(0) { $0 + $1.potassiumMg },
            phosphorusMg: recentEntries.reduce(0) { $0 + $1.phosphorusMg }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Apple Health Access") {
                    if !healthKitManager.isAvailable {
                        Text("Health data is not available on this device.")
                            .foregroundStyle(.secondary)
                    } else {
                        Button(healthKitManager.isLoading ? "Working..." : "Authorize Apple Health") {
                            Task { await healthKitManager.requestAuthorization() }
                        }
                        .disabled(!healthKitManager.canRequestAuthorization)

                        Button("Refresh Health Trends") {
                            Task { await healthKitManager.refresh() }
                        }
                        .disabled(healthKitManager.isLoading)

                        Text(accessSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if !healthKitManager.statusDetail.isEmpty {
                            Text(healthKitManager.statusDetail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if !healthKitManager.lastError.isEmpty {
                            Text(healthKitManager.lastError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Today In Apple Health") {
                    HealthMetricGrid(summary: healthKitManager.snapshot.todayNutrition, valueText: valueText)
                }

                Section("MealVue Last 7 Days") {
                    HealthMetricGrid(summary: recentMealVueSummary, valueText: valueText)
                }

                Section("Health Nutrition Trend") {
                    if healthKitManager.snapshot.dailyNutrition.isEmpty {
                        Text("Authorize Apple Health to read nutrition samples and build a 7-day trend.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(healthKitManager.snapshot.dailyNutrition.reversed()) { day in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(day.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.headline)

                                HealthMetricGrid(summary: day.summary, valueText: valueText)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Recent Kidney Labs") {
                    if healthKitManager.snapshot.recentLabs.isEmpty {
                        Text(healthKitManager.supportsClinicalRecords ? "No kidney-related lab results were found in Health Records yet." : "Clinical Health Records are not available on this device or account.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(healthKitManager.snapshot.recentLabs) { lab in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(lab.name)
                                        .font(.headline)
                                    Spacer()
                                    Text(lab.valueText)
                                        .font(.headline)
                                        .foregroundStyle(.green)
                                }

                                Text("\(lab.date.formatted(date: .abbreviated, time: .omitted)) • \(lab.source)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Health Trends")
        }
    }

    private var accessSummary: String {
        switch healthKitManager.authorizationState {
        case .unavailable:
            return "HealthKit is unavailable."
        case .capabilityMissing:
            return "Apple Health did not register MealVue."
        case .idle:
            return "Grant access to nutrition samples and clinical lab records."
        case .requesting:
            return "Waiting for HealthKit authorization."
        case .authorized:
            return "HealthKit is connected. Refresh to pull the latest samples."
        case .partial:
            return "Apple Health access is incomplete."
        case .failed:
            return "HealthKit authorization or loading failed."
        }
    }

    private func valueText(_ value: Double, suffix: String) -> String {
        "\(Int(value.rounded())) \(suffix)"
    }
}

private struct HealthMetricGrid: View {
    let summary: HealthNutritionSummary
    let valueText: (Double, String) -> String

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            HealthMetricChip(title: "Calories", value: valueText(summary.calories, "kcal"), tint: .green)
            HealthMetricChip(title: "Protein", value: valueText(summary.proteinG, "g"), tint: .blue)
            HealthMetricChip(title: "Fiber", value: valueText(summary.fiberG, "g"), tint: .green)
            HealthMetricChip(title: "Sodium", value: valueText(summary.sodiumMg, "mg"), tint: .orange)
            HealthMetricChip(title: "Potassium", value: valueText(summary.potassiumMg, "mg"), tint: .yellow)
            HealthMetricChip(title: "Phosphorus", value: valueText(summary.phosphorusMg, "mg"), tint: .purple)
        }
    }
}

private struct HealthMetricChip: View {
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
