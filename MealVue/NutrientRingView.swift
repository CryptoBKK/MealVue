//  NutrientRingView.swift
//  MealVue
//  Created for Phase 2.2 Dashboard UI
//

import SwiftUI

struct NutrientRingView: View {
    let title: String
    let current: Double
    let target: Double
    let unit: String
    let color: Color
    var size: CGFloat = 120
    
    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(current / target, 1.5) // Cap visual at 150% for overflow indication
    }
    
    private var statusColor: Color {
        let percentage = current / target
        if percentage >= 1.0 {
            return .red
        } else if percentage >= 0.8 {
            return .yellow
        } else {
            return color
        }
    }
    
    private var isOverTarget: Bool {
        current > target
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 10)
                    .frame(width: size, height: size)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(statusColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: progress)
                
                // Center content
                VStack(spacing: 2) {
                    Text("\(Int(current))")
                        .font(.system(size: size * 0.18, weight: .bold))
                        .foregroundColor(isOverTarget ? .red : .primary)
                    
                    Text(unit)
                        .font(.system(size: size * 0.1))
                        .foregroundColor(.secondary)
                    
                    if isOverTarget {
                        Text("OVER")
                            .font(.system(size: size * 0.08, weight: .bold))
                            .foregroundColor(.red)
                    }
                }
            }
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

struct NutrientRingsView: View {
    let proteinG: Double
    let proteinTarget: Double
    let sodiumMg: Double
    let sodiumTarget: Double
    let potassiumMg: Double
    let potassiumTarget: Double
    let phosphorusMg: Double
    let phosphorusTarget: Double
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 20) {
            NutrientRingView(
                title: "Protein",
                current: proteinG,
                target: proteinTarget,
                unit: "g",
                color: .blue,
                size: 110
            )
            
            NutrientRingView(
                title: "Sodium",
                current: sodiumMg,
                target: sodiumTarget,
                unit: "mg",
                color: .orange,
                size: 110
            )
            
            NutrientRingView(
                title: "Potassium",
                current: potassiumMg,
                target: potassiumTarget,
                unit: "mg",
                color: .yellow,
                size: 110
            )
            
            NutrientRingView(
                title: "Phosphorus",
                current: phosphorusMg,
                target: phosphorusTarget,
                unit: "mg",
                color: .purple,
                size: 110
            )
        }
        .padding(.horizontal)
    }
}

#Preview {
    VStack {
        NutrientRingsView(
            proteinG: 65,
            proteinTarget: 80,
            sodiumMg: 1800,
            sodiumTarget: 2000,
            potassiumMg: 2500,
            potassiumTarget: 3000,
            phosphorusMg: 850,
            phosphorusTarget: 1000
        )
        
        NutrientRingView(
            title: "Test",
            current: 120,
            target: 100,
            unit: "mg",
            color: .red,
            size: 80
        )
    }
    .padding()
}
