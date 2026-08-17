//
//  ActionPopup.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 20.11.2023.
//

import SwiftUI

struct ActionPopup: View {
    @Binding var isPresented: Bool
    let task: FantasticTask
    let user: FantasticUser
    let prices: Prices
    
    let onCreateSimilar: (FantasticTask, Int) -> Void
    let onCreateSamePrompt: (FantasticTask, Int) -> Void
    let onUpscale: (FantasticTask) -> Void
    let onDelete: (FantasticTask) -> Void
    let onDownload: (FantasticTask) -> Void
    
    @State private var quantity: Int = 1
    @State private var showingDeleteConfirmation = false
    
    private var canUpscale: Bool {
        task.state == .stateDone && task.type == .image
    }
    
    private var canCreateSimilar: Bool {
        task.state == .stateDone && !task.details.resultUrl.isEmpty
    }
    
    private var canDownload: Bool {
        task.state == .stateDone && !task.details.resultUrl.isEmpty
    }
    
    private var totalCost: Double {
        // Calculate cost based on operation type
        return Double(quantity) * 1.0 // Placeholder cost calculation
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Image Preview
                if !task.details.resultUrl.isEmpty {
                    AsyncImage(url: URL(string: task.details.resultUrl)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
                    .padding()
                }
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Task Info
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Prompt")
                                .font(.headline)
                            Text(task.details.prompt)
                                .font(.body)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            
                            if !task.details.neg_prompt.isEmpty {
                                Text("Negative Prompt")
                                    .font(.headline)
                                Text(task.details.neg_prompt)
                                    .font(.body)
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                            }
                            
                            // Technical Details
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Size: \(task.details.w)x\(task.details.h)")
                                    Text("Model: \(task.aiArtist.rawValue)")
                                    Text("CFG: \(task.details.cfg, specifier: "%.1f")")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.5))
                        .cornerRadius(12)
                        
                        // Actions
                        VStack(spacing: 12) {
                            // Create Similar
                            if canCreateSimilar {
                                ActionButton(
                                    title: "Create Similar",
                                    subtitle: "Generate similar image",
                                    icon: "photo.on.rectangle.angled",
                                    color: .blue
                                ) {
                                    onCreateSimilar(task, quantity)
                                }
                            }
                            
                            // Create Same Prompt
                            ActionButton(
                                title: "Create Same Prompt",
                                subtitle: "Use same prompt for new image",
                                icon: "doc.text",
                                color: .green
                            ) {
                                onCreateSamePrompt(task, quantity)
                            }
                            
                            // Upscale
                            if canUpscale {
                                ActionButton(
                                    title: "Upscale Image",
                                    subtitle: "Enhance image resolution",
                                    icon: "arrow.up.right.square",
                                    color: .purple
                                ) {
                                    onUpscale(task)
                                }
                            }
                            
                            // Download
                            if canDownload {
                                ActionButton(
                                    title: "Download Image",
                                    subtitle: "Save to device",
                                    icon: "square.and.arrow.down",
                                    color: .orange
                                ) {
                                    onDownload(task)
                                }
                            }
                            
                            // Delete
                            ActionButton(
                                title: "Delete Image",
                                subtitle: "Remove permanently",
                                icon: "trash",
                                color: .red
                            ) {
                                showingDeleteConfirmation = true
                            }
                        }
                        
                        // Quantity Selection (for create operations)
                        if canCreateSimilar {
                            VStack {
                                HStack {
                                    Text("Quantity:")
                                    Stepper(value: $quantity, in: 1...64) {
                                        Text("\(quantity)")
                                    }
                                }
                                .padding(.horizontal)
                                
                                Text("Cost: \(totalCost, specifier: "%.1f")💎, \(user.credits, specifier: "%.1f")💎 left")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Image Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        isPresented = false
                    }
                }
            }
        }
        .alert("Delete Image", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete(task)
            }
        } message: {
            Text("Are you sure you want to delete this image? This action cannot be undone.")
        }
    }
}

struct ActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ActionPopup_Previews: PreviewProvider {
    static var previews: some View {
        ActionPopup(
            isPresented: .constant(true),
            task: FantasticTask(
                id: 1,
                type: .image,
                state: .stateDone,
                details: FantasticTaskDetails(
                    prompt: "A beautiful landscape",
                    resultUrl: "https://example.com/image.jpg"
                )
            ),
            user: FantasticUser(credits: 1000),
            prices: Prices(),
            onCreateSimilar: { _, _ in },
            onCreateSamePrompt: { _, _ in },
            onUpscale: { _ in },
            onDelete: { _ in },
            onDownload: { _ in }
        )
    }
}
