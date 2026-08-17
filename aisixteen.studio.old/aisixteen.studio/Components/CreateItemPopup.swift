//
//  CreateItemPopup.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 20.11.2023.
//

import SwiftUI

enum CreateItemTab: Int, CaseIterable {
    case prompt = 0
    case negative = 1
    case details = 2
    case model = 3
    
    var title: String {
        switch self {
        case .prompt: return "Prompt"
        case .negative: return "Negative"
        case .details: return "Details"
        case .model: return "Model"
        }
    }
    
    var icon: String {
        switch self {
        case .prompt: return "text.badge.plus"
        case .negative: return "text.badge.minus"
        case .details: return "gearshape"
        case .model: return "square.grid.3x3"
        }
    }
}

enum ImageOrientation: String, CaseIterable {
    case portrait = "Portrait"
    case square = "Square"
    case landscape = "Landscape"
    
    var dimensions: (width: Int, height: Int) {
        switch self {
        case .portrait: return (832, 1216)
        case .square: return (1024, 1024)
        case .landscape: return (1216, 832)
        }
    }
    
    var icon: String {
        switch self {
        case .portrait: return "rectangle.portrait"
        case .square: return "square"
        case .landscape: return "rectangle"
        }
    }
}

enum CreativityLevel: String, CaseIterable {
    case creative = "Creative"
    case balanced = "Balanced"
    case precise = "Precise"
    
    var cfg: Double {
        switch self {
        case .creative: return 4.0
        case .balanced: return 7.0
        case .precise: return 10.0
        }
    }
}

struct AvailableModel {
    let modelName: AiArtistDiffuse
    let description: String
    let imageUrl: String
}

struct CreateItemPopup: View {
    @Binding var isPresented: Bool
    @Binding var task: FantasticTask
    @State private var selectedTab: CreateItemTab = .prompt
    @State private var quantity: Int = 1
    @State private var selectedImagePreview: String? = nil
    
    let user: FantasticUser
    let prices: Prices
    let onCancel: () -> Void
    let onCreate: (FantasticTask, Int) -> Void
    
    private let availableModels: [AvailableModel] = [
        AvailableModel(
            modelName: .juggernaut_xl,
            description: "Finetuned for realism",
            imageUrl: "https://storage.googleapis.com/aisixteen_public/studio/examples/example_jugg.jpg"
        )
    ]
    
    private var selectedModelIndex: Int {
        availableModels.firstIndex { $0.modelName == task.aiArtist } ?? 0
    }
    
    private var selectedModel: AvailableModel {
        availableModels[selectedModelIndex]
    }
    
    private var isValid: Bool {
        !task.details.prompt.isEmpty && task.details.prompt.count <= 2048 &&
        task.details.neg_prompt.count <= 2048
    }
    
    private var totalCost: Double {
        // Calculate cost based on task type and quantity
        return Double(quantity) * 1.0 // Placeholder cost calculation
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if let previewUrl = selectedImagePreview {
                    AsyncImage(url: URL(string: previewUrl)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture {
                        selectedImagePreview = nil
                    }
                } else {
                    VStack {
                        // Tab Content
                        TabView(selection: $selectedTab) {
                            promptTab
                                .tag(CreateItemTab.prompt)
                            
                            negativeTab
                                .tag(CreateItemTab.negative)
                            
                            detailsTab
                                .tag(CreateItemTab.details)
                            
                            modelTab
                                .tag(CreateItemTab.model)
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                        
                        Spacer()
                        
                        // Tab Bar
                        HStack {
                            ForEach(CreateItemTab.allCases, id: \.self) { tab in
                                Button(action: {
                                    selectedTab = tab
                                }) {
                                    VStack {
                                        Image(systemName: tab.icon)
                                        Text(tab.title)
                                            .font(.caption)
                                    }
                                    .foregroundColor(selectedTab == tab ? .blue : .gray)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding()
                        
                        // Quantity and Cost
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
                        
                        // Action Buttons
                        HStack {
                            Button("Close") {
                                onCancel()
                            }
                            .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button("CREATE") {
                                onCreate(task, quantity)
                            }
                            .disabled(!isValid)
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(task.type == .image ? "Create Image" : "Create Similar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
    
    private var promptTab: some View {
        VStack {
            HStack {
                Text("Enter Prompt")
                    .font(.headline)
                Spacer()
                Button(action: {
                    // Load example prompt
                    task.details.prompt = "A beautiful landscape with mountains and a lake, highly detailed, 8k resolution"
                }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding()
            
            TextEditor(text: $task.details.prompt)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal)
            
            if task.details.prompt.count > 2048 {
                Text("Please shorten prompt by \(task.details.prompt.count - 2048) characters")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Spacer()
        }
    }
    
    private var negativeTab: some View {
        VStack {
            HStack {
                Text("Enter Negative Prompt")
                    .font(.headline)
                Spacer()
                Button(action: {
                    // Load example negative prompt
                    task.details.neg_prompt = "blurry, low quality, distorted, ugly, bad anatomy"
                }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding()
            
            TextEditor(text: $task.details.neg_prompt)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal)
            
            if task.details.neg_prompt.count > 2048 {
                Text("Please shorten negative prompt by \(task.details.neg_prompt.count - 2048) characters")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Spacer()
        }
    }
    
    private var detailsTab: some View {
        VStack(spacing: 20) {
            Text("Image Details")
                .font(.headline)
                .padding()
            
            // Orientation Selection
            VStack {
                Text("Orientation")
                    .font(.subheadline)
                
                HStack {
                    ForEach(ImageOrientation.allCases, id: \.self) { orientation in
                        Button(action: {
                            let dims = orientation.dimensions
                            task.details.w = dims.width
                            task.details.h = dims.height
                        }) {
                            VStack {
                                Image(systemName: orientation.icon)
                                Text(orientation.rawValue)
                                    .font(.caption)
                                Text("\(orientation.dimensions.width)x\(orientation.dimensions.height)")
                                    .font(.caption2)
                            }
                            .padding()
                            .background(task.details.w == orientation.dimensions.width ? Color.blue : Color(.systemGray6))
                            .foregroundColor(task.details.w == orientation.dimensions.width ? .white : .primary)
                            .cornerRadius(8)
                        }
                    }
                }
            }
            
            // Creativity Level
            VStack {
                Text("Creativity")
                    .font(.subheadline)
                
                HStack {
                    ForEach(CreativityLevel.allCases, id: \.self) { level in
                        Button(action: {
                            task.details.cfg = level.cfg
                        }) {
                            Text(level.rawValue)
                                .padding()
                                .background(task.details.cfg == level.cfg ? Color.blue : Color(.systemGray6))
                                .foregroundColor(task.details.cfg == level.cfg ? .white : .primary)
                                .cornerRadius(8)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var modelTab: some View {
        VStack {
            Text("AI Model")
                .font(.headline)
                .padding()
            
            VStack {
                HStack {
                    Button(action: {
                        let currentIndex = selectedModelIndex
                        let newIndex = currentIndex > 0 ? currentIndex - 1 : availableModels.count - 1
                        task.aiArtist = availableModels[newIndex].modelName
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title)
                    }
                    
                    Spacer()
                    
                    VStack {
                        AsyncImage(url: URL(string: selectedModel.imageUrl)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 150, height: 150)
                        .cornerRadius(8)
                        .onTapGesture {
                            selectedImagePreview = selectedModel.imageUrl
                        }
                        
                        Text(selectedModel.modelName.rawValue)
                            .font(.headline)
                        
                        Text(selectedModel.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        let currentIndex = selectedModelIndex
                        let newIndex = currentIndex < availableModels.count - 1 ? currentIndex + 1 : 0
                        task.aiArtist = availableModels[newIndex].modelName
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.title)
                    }
                }
                .padding()
            }
            
            Spacer()
        }
    }
}

struct CreateItemPopup_Previews: PreviewProvider {
    static var previews: some View {
        CreateItemPopup(
            isPresented: .constant(true),
            task: .constant(FantasticTask()),
            user: FantasticUser(),
            prices: Prices(),
            onCancel: {},
            onCreate: { _, _ in }
        )
    }
}
