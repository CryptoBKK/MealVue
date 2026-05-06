//
//  SampleData.swift
//  MealVue
//
//  Created for testing with Thai patient profiles
//

import Foundation
import SwiftData
import UIKit

// MARK: - Patient Profiles

struct PatientProfile {
    let name: String
    let age: Int
    let sex: String
    let ckdStage: Int
    let weight: Double // kg
    let height: Double // cm
    let onDialysis: Bool
    let dailyTargets: DailyTargets
    let recentLabs: LabResults
}

struct DailyTargets {
    let protein: Double // grams
    let sodium: Double // mg
    let potassium: Double // mg
    let phosphorus: Double // mg
    let calories: Int
}

struct LabResults {
    let eGFR: Double // mL/min/1.73m²
    let creatinine: Double // mg/dL
    let potassium: Double // mEq/L
    let phosphorus: Double // mg/dL
    let calcium: Double? // mg/dL
}

// MARK: - Sample Thai Patient Data

enum SamplePatient {
    case somchai // CKD Stage 3a
    case malee // CKD Stage 4
    case prasert // CKD Stage 5 on dialysis
    
    var profile: PatientProfile {
        switch self {
        case .somchai:
            return PatientProfile(
                name: "Somchai", age: 58, sex: "Male",
                ckdStage: 3, weight: 72, height: 168, onDialysis: false,
                dailyTargets: DailyTargets(
                    protein: 80, sodium: 2000, potassium: 3000,
                    phosphorus: 1000, calories: 2200
                ),
                recentLabs: LabResults(
                    eGFR: 52, creatinine: 1.4, potassium: 4.2,
                    phosphorus: 3.5, calcium: 9.2
                )
            )
            
        case .malee:
            return PatientProfile(
                name: "Malee", age: 64, sex: "Female",
                ckdStage: 4, weight: 58, height: 156, onDialysis: false,
                dailyTargets: DailyTargets(
                    protein: 58, sodium: 1500, potassium: 2000,
                    phosphorus: 800, calories: 1800
                ),
                recentLabs: LabResults(
                    eGFR: 28, creatinine: 2.8, potassium: 5.1,
                    phosphorus: 5.8, calcium: 8.8
                )
            )
            
        case .prasert:
            return PatientProfile(
                name: "Prasert", age: 71, sex: "Male",
                ckdStage: 5, weight: 68, height: 170, onDialysis: true,
                dailyTargets: DailyTargets(
                    protein: 85, sodium: 2000, potassium: 2000,
                    phosphorus: 1000, calories: 2400
                ),
                recentLabs: LabResults(
                    eGFR: 12, creatinine: 5.1, potassium: 5.8,
                    phosphorus: 6.5, calcium: 8.5
                )
            )
        }
    }
}

// MARK: - Thai Food Entries (30 Days)

class SampleDataGenerator {
    static func generateThaiMeals() -> [FoodEntry] {
        let calendar = Calendar.current
        let today = Date()
        
        var entries: [FoodEntry] = []
        
        // Sample Thai foods with kidney-relevant nutrition
        let thaiFoods: [(name: String, quantity: String, calories: Int,
                         protein: Double, carbs: Double, fat: Double,
                         sodium: Double, potassium: Double, phosphorus: Double,
                         warning: String)] = [
            
            // Breakfast items
            ("Jok (Rice Porridge)", "1 bowl (250g)", 180, 6, 35, 2, 450, 120, 95, ""),
            ("Kai Jeow (Thai Omelet)", "1 piece (150g)", 280, 14, 8, 22, 680, 280, 220, "High sodium from fish sauce"),
            ("Pa Tong Go (Fried Dough)", "3 pieces (90g)", 320, 6, 55, 10, 380, 150, 110, ""),
            ("Soy Milk (Unsweetened)", "1 glass (250ml)", 80, 7, 4, 4, 120, 380, 110, "Watch potassium if stage 4+"),
            
            // Lunch items
            ("Som Tam (Papaya Salad)", "1 plate (200g)", 120, 3, 18, 4, 890, 420, 65, "High sodium. Limit fish sauce."),
            ("Tom Yum Goong", "1 bowl (350ml)", 180, 15, 12, 8, 1200, 380, 180, "Very high sodium. Consider low-sodium version."),
            ("Pad Thai (Shrimp)", "1 plate (300g)", 450, 18, 65, 14, 950, 320, 220, "Moderate sodium and phosphorus."),
            ("Gaeng Daeng (Red Curry)", "1 bowl (250g)", 320, 12, 15, 24, 780, 450, 180, "High fat and sodium. Limit coconut milk."),
            ("Khao Pad (Fried Rice)", "1 plate (300g)", 380, 10, 55, 14, 850, 280, 165, "High sodium from soy sauce."),
            ("Pla Rad Prik (Fried Fish)", "1 piece (200g)", 290, 22, 12, 18, 560, 520, 280, "High potassium and phosphorus from fish."),
            
            // Snacks
            ("Mango Sticky Rice", "1 serving (200g)", 380, 5, 72, 10, 120, 450, 130, "High potassium from mango. Limit portion."),
            ("Fresh Papaya", "1 cup (150g)", 60, 1, 15, 0, 10, 360, 25, ""),
            ("Coconut Water", "1 young coconut", 45, 1, 9, 1, 105, 470, 40, "High potassium. Limit to 1/2 cup."),
            ("Thai Iced Tea", "1 glass (300ml)", 180, 2, 30, 6, 95, 150, 85, ""),
            
            // Dinner items
            ("Tom Kha Gai", "1 bowl (300ml)", 220, 14, 8, 16, 920, 420, 160, "High sodium. Reduce fish sauce."),
            ("Pad Kra Pao (Basil Pork)", "1 plate (300g)", 420, 24, 35, 20, 1100, 480, 250, "Very high sodium. Use low-sodium sauce."),
            ("Gaeng Keow Wan (Green Curry)", "1 bowl (250g)", 350, 15, 18, 26, 820, 520, 200, "High potassium from eggplant + potassium-rich veggies."),
            ("Stir-Fried Morning Glory", "1 plate (150g)", 90, 3, 8, 6, 680, 380, 65, "High sodium from oyster sauce."),
            ("Steamed Fish with Lime", "1 piece (200g)", 260, 24, 6, 16, 480, 580, 260, "High potassium and phosphorus. Small portion."),
        ]
        
        // Generate 30 days of sample meals (2-3 meals per day)
        for dayOffset in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            
            // Breakfast
            if let food = thaiFoods.randomElement() {
                let entry = FoodEntry(
                    foodName: food.name,
                    estimatedQuantity: food.quantity,
                    calories: food.calories,
                    proteinG: food.protein,
                    carbsG: food.carbs,
                    fatG: food.fat,
                    sodiumMg: food.sodium,
                    potassiumMg: food.potassium,
                    phosphorusMg: food.phosphorus,
                    notes: "Sample data - Day \(30 - dayOffset)",
                    kidneyWarning: food.warning,
                    confidence: "sample",
                    aiNotes: "This is sample Thai food data for testing.",
                    imageData: nil
                )
                // Override timestamp to set proper date
                entry.timestamp = date
                entries.append(entry)
            }
            
            // Lunch (70% chance)
            if Double.random(in: 0...1) < 0.7,
               let food = thaiFoods.randomElement() {
                let entry = FoodEntry(
                    foodName: food.name,
                    estimatedQuantity: food.quantity,
                    calories: food.calories,
                    proteinG: food.protein,
                    carbsG: food.carbs,
                    fatG: food.fat,
                    sodiumMg: food.sodium,
                    potassiumMg: food.potassium,
                    phosphorusMg: food.phosphorus,
                    notes: "Sample lunch - Day \(30 - dayOffset)",
                    kidneyWarning: food.warning,
                    confidence: "sample",
                    aiNotes: "Thai lunch sample for MealVue testing.",
                    imageData: nil
                )
                // Set to noon-ish
                if let lunchDate = calendar.date(bySettingHour: 12, minute: 30, second: 0, of: date) {
                    entry.timestamp = lunchDate
                }
                entries.append(entry)
            }
            
            // Dinner (50% chance)
            if Double.random(in: 0...1) < 0.5,
               let food = thaiFoods.randomElement() {
                let entry = FoodEntry(
                    foodName: food.name,
                    estimatedQuantity: food.quantity,
                    calories: food.calories,
                    proteinG: food.protein,
                    carbsG: food.carbs,
                    fatG: food.fat,
                    sodiumMg: food.sodium,
                    potassiumMg: food.potassium,
                    phosphorusMg: food.phosphorus,
                    notes: "Sample dinner - Day \(30 - dayOffset)",
                    kidneyWarning: food.warning,
                    confidence: "sample",
                    aiNotes: "Evening meal sample data.",
                    imageData: nil
                )
                // Set to evening
                if let dinnerDate = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: date) {
                    entry.timestamp = dinnerDate
                }
                entries.append(entry)
            }
        }
        
        return entries
    }
    
    // MARK: - Load Sample Data Button Action
    
    static func loadSampleData(into context: ModelContext) {
        let sampleEntries = generateThaiMeals()
        
        for entry in sampleEntries {
            context.insert(entry)
        }
        
        do {
            try context.save()
            print("✅ Loaded \(sampleEntries.count) sample Thai meal entries")
        } catch {
            print("❌ Failed to save sample data: \(error)")
        }
    }
    
    static func clearSampleData(from context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<FoodEntry>(
                predicate: #Predicate { $0.confidence == "sample" }
            )
            let sampleEntries = try context.fetch(descriptor)
            
            for entry in sampleEntries {
                context.delete(entry)
            }
            
            try context.save()
            print("✅ Cleared \(sampleEntries.count) sample entries")
        } catch {
            print("❌ Failed to clear sample data: \(error)")
        }
    }
}
