//
//  Item.swift
//  MealVue
//
//  Created by Quinn Rieman on 28/4/26.
//

import Foundation
import SwiftData
import UIKit

@Model
final class FoodEntry {
    var id: UUID
    var timestamp: Date
    var foodName: String
    var estimatedQuantity: String
    var calories: Int
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
    var sodiumMg: Double
    var potassiumMg: Double
    var phosphorusMg: Double
    var notes: String
    var kidneyWarning: String
    var confidence: String
    var aiNotes: String
    @Attribute(.externalStorage) var imageData: Data?

    init(
        foodName: String,
        estimatedQuantity: String = "",
        calories: Int = 0,
        proteinG: Double = 0,
        carbsG: Double = 0,
        fatG: Double = 0,
        fiberG: Double = 0,
        sodiumMg: Double = 0,
        potassiumMg: Double = 0,
        phosphorusMg: Double = 0,
        notes: String = "",
        kidneyWarning: String = "",
        confidence: String = "manual",
        aiNotes: String = "",
        imageData: Data? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.foodName = foodName
        self.estimatedQuantity = estimatedQuantity
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sodiumMg = sodiumMg
        self.potassiumMg = potassiumMg
        self.phosphorusMg = phosphorusMg
        self.notes = notes
        self.kidneyWarning = kidneyWarning
        self.confidence = confidence
        self.aiNotes = aiNotes
        self.imageData = imageData
    }

    var uiImage: UIImage? {
        guard let imageData else { return nil }
        return UIImage(data: imageData)
    }
}
