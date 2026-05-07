//  SparklineView.swift
//  MealVue
//  Mini bar chart for nutrient trends
//

import SwiftUI
import SwiftData

struct SparklineView: View {
    let title: String
    let data: [Double]
    let target: Double
    let unit: String
    let color: Color
    let days: Int
    
    private var maxValue: Double {
        let maxData = data.max() ?? 0
        return max(maxData, target) * 1.2
    }
    
    private var averageValue: Double {
        guard !data.isEmpty else { return 0 }
        return data.reduce(0, +) / Double(data.count)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Avg: \(Int(averageValue)) \(unit)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Mini bar chart
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<min(data.count, days), id: \.self) { index in
                    let value = data[index]
                    let height = max(value / maxValue, 0.05) // Min 5% height for visibility
                    
                    VStack(spacing: 2) {
                        // Target line indicator
                        if value > target {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 4, height: 4)
                        }
                        
                        Rectangle()
                            .fill(barColor(for: value))
                            .frame(width: nil, height: height * 40)
                            .cornerRadius(2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 44)
            
            // Target line
            HStack {
                Text("Target: \(Int(target)) \(unit)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Simple legend
                HStack(spacing: 4) {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                    Text("OK")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text(">")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func barColor(for value: Double) -> Color {
        if value > target {
            return .red
        } else if value > target * 0.8 {
            return .yellow
        } else {
            return color
        }
    }
}

struct NutrientSparklinesView: View {
    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var entries: [FoodEntry]
    let proteinTarget: Double
    let sodiumTarget: Double
    let potassiumTarget: Double
    let phosphorusTarget: Double
    
    private var last7DaysData: [(date: Date, protein: Double, sodium: Double, potassium: Double, phosphorus: Double)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let dayStart = date
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            
            let dayEntries = entries.filter { entry in
                entry.timestamp >= dayStart && entry.timestamp < dayEnd
            }
            
            return (
                date: date,
                protein: dayEntries.reduce(0) { $0 + $1.proteinG },
                sodium: dayEntries.reduce(0) { $0 + $1.sodiumMg },
                potassium: dayEntries.reduce(0) { $0 + $1.potassiumMg },
                phosphorus: dayEntries.reduce(0) { $0 + $1.phosphorusMg }
            )
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("7-Day Trends")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 8) {
                SparklineView(
                    title: "Protein",
                    data: last7DaysData.map { $0.protein },
                    target: proteinTarget,
                    unit: "g",
                    color: .blue,
                    days: 7
                )
                
                SparklineView(
                    title: "Sodium",
                    data: last7DaysData.map { $0.sodium },
                    target: sodiumTarget,
                    unit: "mg",
                    color: .orange,
                    days: 7
                )
                
                SparklineView(
                    title: "Potassium",
                    data: last7DaysData.map { $0.potassium },
                    target: potassiumTarget,
                    unit: "mg",
                    color: .yellow,
                    days: 7
                )
                
                SparklineView(
                    title: "Phosphorus",
                    data: last7DaysData.map { $0.phosphorus },
                    target: phosphorusTarget,
                    unit: "mg",
                    color: .purple,
                    days: 7
                )
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    VStack {
        SparklineView(
            title: "Sodium",
            data: [1800, 2200, 1900, 2500, 1700, 2000, 2100],
            target: 2000,
            unit: "mg",
            color: .orange,
            days: 7
        )
        .padding()
        
        NutrientSparklinesView(
            proteinTarget: 80,
            sodiumTarget: 2000,
            potassiumTarget: 3000,
            phosphorusTarget: 1000
        )
    }
}
