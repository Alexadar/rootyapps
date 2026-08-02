//
//  ContentView.swift
//  circlemath.swift
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SwiftUI
import Foundation

struct ContentView: View {
    @State private var radiusText: String = ""
    @State private var areaText: String = ""
    @State private var circumferenceText: String = ""
    
    @State private var lastEditedField: FieldType = .none
    
    enum FieldType {
        case radius, area, circumference, none
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    // Header with vector circle and title
                    VStack(spacing: 16) {
                        // Large vector circle with formulas
                        ZStack {
                            // Main circle
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.blue, .purple]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 6
                                )
                                .frame(width: 200, height: 200)
                            
                            // Radius line
                            Path { path in
                                path.move(to: CGPoint(x: 100, y: 100)) // center
                                path.addLine(to: CGPoint(x: 200, y: 100)) // right edge
                            }
                            .stroke(Color.orange, lineWidth: 3)
                            .frame(width: 200, height: 200)
                            
                            // Center dot
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                            
                            // Radius label
                            Text("r")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                                .position(x: 150, y: 80)
                            
                            // Area formula positioned in center
                            VStack(spacing: 2) {
                                Text("Area")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.green)
                                Text("π × r²")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.green)
                            }
                            .position(x: 105, y: 150)
                            
                            // Circumference formula positioned along the circle
                            VStack(spacing: 2) {
                                Text("Circumference")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.purple)
                                Text("2 × π × r")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.purple)
                            }
                            .position(x: 105, y: 60)
                            
                            // Dotted circumference indicator
                            Circle()
                                .stroke(Color.purple.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                                .frame(width: 180, height: 180)
                        }
                        .frame(width: 220, height: 220)
                        
                        Text("Circle Math")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .purple]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        HStack {
                            Spacer()
                            Button("Reset") {
                                resetCalculation()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                
                    // Main card content
                    VStack(spacing: 20) {
                    // Radius section
                    VStack(spacing: 10) {
                        HStack {
                            Image(systemName: "ruler")
                                .foregroundColor(.orange)
                            Text("Radius")
                                .font(.headline)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        
                        TextField("Enter radius", text: $radiusText)
                            .textFieldStyle(.roundedBorder)
                            .font(.title2)
                            .multilineTextAlignment(.center)
                            .onChange(of: radiusText) { _, newValue in
                                lastEditedField = .radius
                                calculateFromRadius(newValue)
                            }
                            .onTapGesture {
                                lastEditedField = .radius
                            }
                    }
                    
                    // Area section
                    VStack(spacing: 10) {
                        HStack {
                            Image(systemName: "square.fill")
                                .foregroundColor(.green)
                            Text("Area")    
                                .font(.headline)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        
                        TextField("Enter area", text: $areaText)
                            .textFieldStyle(.roundedBorder)
                            .font(.title2)
                            .multilineTextAlignment(.center)
                            .onChange(of: areaText) { _, newValue in
                                lastEditedField = .area
                                calculateFromArea(newValue)
                            }
                            .onTapGesture {
                                lastEditedField = .area
                            }
                    }
                    
                    // Circumference section
                    VStack(spacing: 10) {
                        HStack {
                            Image(systemName: "circle.dotted")
                                .foregroundColor(.purple)
                            Text("Circumference")
                                .font(.headline)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        
                        TextField("Enter circumference", text: $circumferenceText)
                            .textFieldStyle(.roundedBorder)
                            .font(.title2)
                            .multilineTextAlignment(.center)
                            .onChange(of: circumferenceText) { _, newValue in
                                lastEditedField = .circumference
                                calculateFromCircumference(newValue)
                            }
                            .onTapGesture {
                                lastEditedField = .circumference
                            }
                    }
                    
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.gray.opacity(0.1))
                            .shadow(color: .gray.opacity(0.2), radius: 5, x: 0, y: 2)
                    )
                    .padding(.horizontal)
                    
                    // Bottom spacer to ensure content fits viewport
                    Spacer(minLength: 20)
                }
                .frame(minHeight: geometry.size.height)
            }
            .background(Color(.systemBackground))
        }
    }
    
    private func calculateFromRadius(_ radiusString: String) {
        guard !radiusString.isEmpty,
              let radius = Double(radiusString),
              radius > 0 else {
            if radiusString.isEmpty && lastEditedField == .radius {
                areaText = ""
                circumferenceText = ""
            }
            return
        }
        
        let area = Double.pi * radius * radius
        let circumference = 2 * Double.pi * radius
        
        if lastEditedField == .radius {
            areaText = formatNumber(area)
            circumferenceText = formatNumber(circumference)
        }
    }
    
    private func calculateFromArea(_ areaString: String) {
        guard !areaString.isEmpty,
              let area = Double(areaString),
              area > 0 else {
            if areaString.isEmpty && lastEditedField == .area {
                radiusText = ""
                circumferenceText = ""
            }
            return
        }
        
        let radius = sqrt(area / Double.pi)
        let circumference = 2 * Double.pi * radius
        
        if lastEditedField == .area {
            radiusText = formatNumber(radius)
            circumferenceText = formatNumber(circumference)
        }
    }
    
    private func calculateFromCircumference(_ circumferenceString: String) {
        guard !circumferenceString.isEmpty,
              let circumference = Double(circumferenceString),
              circumference > 0 else {
            if circumferenceString.isEmpty && lastEditedField == .circumference {
                radiusText = ""
                areaText = ""
            }
            return
        }
        
        let radius = circumference / (2 * Double.pi)
        let area = Double.pi * radius * radius
        
        if lastEditedField == .circumference {
            radiusText = formatNumber(radius)
            areaText = formatNumber(area)
        }
    }
    
    private func formatNumber(_ number: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: number)) ?? "0"
    }
    
    private func resetCalculation() {
        radiusText = ""
        areaText = ""
        circumferenceText = ""
        lastEditedField = .none
    }
}

#Preview {
    ContentView()
}
