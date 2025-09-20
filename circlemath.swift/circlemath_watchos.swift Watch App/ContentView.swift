//
//  ContentView.swift
//  circlemath_watchos.swift Watch App
//
//  Created by Oleksandr Koreniuk on 20.09.2025.
//

import SwiftUI

struct ContentView: View {
    @State private var radius: String = ""
    @State private var area: String = ""
    @State private var circumference: String = ""
    @State private var lastEditedField: EditedField = .none
    
    enum EditedField {
        case radius, area, circumference, none
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    // Title
                    Text("Circle Math")
                        .font(.headline)
                        .foregroundColor(.orange)
                        .padding(.bottom, 8)
                    
                    // Circle visualization
                    ZStack {
                        Circle()
                            .stroke(Color.orange, lineWidth: 2)
                            .frame(width: 60, height: 60)
                        
                        // Radius line
                        Path { path in
                            path.move(to: CGPoint(x: 30, y: 30))
                            path.addLine(to: CGPoint(x: 60, y: 30))
                        }
                        .stroke(Color.orange, lineWidth: 1)
                        
                        Text("r")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .offset(x: 20, y: -8)
                    }
                    .padding(.bottom, 8)
                    
                    // Input fields
                    VStack(spacing: 8) {
                        // Radius
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Radius")
                                .font(.caption)
                                .foregroundColor(.orange)
                            TextField("0", text: $radius)
                                .onChange(of: radius) { oldValue, newValue in
                                    if lastEditedField != .radius {
                                        lastEditedField = .radius
                                        updateFromRadius()
                                    }
                                }
                        }
                        
                        // Area
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Area")
                                .font(.caption)
                                .foregroundColor(.green)
                            TextField("0", text: $area)
                                .onChange(of: area) { oldValue, newValue in
                                    if lastEditedField != .area {
                                        lastEditedField = .area
                                        updateFromArea()
                                    }
                                }
                        }
                        
                        // Circumference
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Circumference")
                                .font(.caption)
                                .foregroundColor(.purple)
                            TextField("0", text: $circumference)
                                .onChange(of: circumference) { oldValue, newValue in
                                    if lastEditedField != .circumference {
                                        lastEditedField = .circumference
                                        updateFromCircumference()
                                    }
                                }
                        }
                    }
                    
                    // Reset button
                    Button("Reset") {
                        resetFields()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray)
                    .font(.caption)
                }
                .padding(.horizontal, 8)
            }
        }
    }
    
    private func updateFromRadius() {
        guard let r = Double(radius), r > 0 else {
            area = ""
            circumference = ""
            return
        }
        
        let calculatedArea = Double.pi * r * r
        let calculatedCircumference = 2 * Double.pi * r
        
        area = String(format: "%.3f", calculatedArea)
        circumference = String(format: "%.3f", calculatedCircumference)
    }
    
    private func updateFromArea() {
        guard let a = Double(area), a > 0 else {
            radius = ""
            circumference = ""
            return
        }
        
        let calculatedRadius = sqrt(a / Double.pi)
        let calculatedCircumference = 2 * Double.pi * calculatedRadius
        
        radius = String(format: "%.3f", calculatedRadius)
        circumference = String(format: "%.3f", calculatedCircumference)
    }
    
    private func updateFromCircumference() {
        guard let c = Double(circumference), c > 0 else {
            radius = ""
            area = ""
            return
        }
        
        let calculatedRadius = c / (2 * Double.pi)
        let calculatedArea = Double.pi * calculatedRadius * calculatedRadius
        
        radius = String(format: "%.3f", calculatedRadius)
        area = String(format: "%.3f", calculatedArea)
    }
    
    private func resetFields() {
        radius = ""
        area = ""
        circumference = ""
        lastEditedField = .none
    }
}

#Preview {
    ContentView()
}
