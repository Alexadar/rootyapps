//
//  BuyPacksPopup.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 20.11.2023.
//

import SwiftUI

struct BuyPacksPopup: View {
    @Binding var isPresented: Bool
    let packs: [CreditsPack]
    let onPurchase: (Int) -> Void
    
    private var sortedPacks: [CreditsPack] {
        packs.sorted { $0.order < $1.order }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(sortedPacks, id: \.id) { pack in
                        PackCard(pack: pack, onPurchase: onPurchase)
                    }
                }
                .padding()
            }
            .navigationTitle("Buy Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

struct PackCard: View {
    let pack: CreditsPack
    let onPurchase: (Int) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Text(getPackLabel(pack.label))
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Text("Get \(pack.amount) 💎")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("for $\(pack.cost, specifier: "%.2f")")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button("Buy") {
                onPurchase(pack.id)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .frame(minHeight: 150)
        .background(
            pack.highlight ? 
            LinearGradient(
                colors: [Color.orange.opacity(0.9), Color.pink.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ) :
            LinearGradient(
                colors: [Color(.systemGray6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(pack.highlight ? Color.white.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }
    
    private func getPackLabel(_ label: String) -> String {
        switch label {
        case "tryIt": return "Starter"
        case "doGallery": return "Advanced"
        case "doMore": return "Pro"
        default: return label.capitalized
        }
    }
}

struct BuyPacksPopup_Previews: PreviewProvider {
    static var previews: some View {
        BuyPacksPopup(
            isPresented: .constant(true),
            packs: [
                CreditsPack(id: 1, label: "tryIt", amount: 100, cost: 0.99, order: 1, highlight: false),
                CreditsPack(id: 2, label: "doGallery", amount: 2000, cost: 19.99, order: 2, highlight: true),
                CreditsPack(id: 3, label: "doMore", amount: 10000, cost: 99.99, order: 3, highlight: false)
            ],
            onPurchase: { _ in }
        )
    }
}
