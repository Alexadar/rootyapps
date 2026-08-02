//
//  AccountModal.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 20.11.2023.
//

import SwiftUI

struct AccountModal: View {
    @Binding var isPresented: Bool
    let user: FantasticUser
    let onBuyMore: () -> Void
    let onLogout: () -> Void
    
    @State private var selectedLanguage: String = "en"
    
    private let availableLanguages = [
        ("en", "English"),
        ("ua", "Українська")
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // User Info Section
                VStack(spacing: 16) {
                    // Profile Image Placeholder
                    Circle()
                        .fill(Color.blue.gradient)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Text(String(user.displayName?.first ?? "U"))
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )
                    
                    Text("Hello, \(user.displayName ?? "User")!")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    // Balance
                    HStack {
                        Image(systemName: "diamond.fill")
                            .foregroundColor(.blue)
                        Text("Balance: \(user.credits, specifier: "%.0f") 💎")
                            .font(.headline)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                // Actions Section
                VStack(spacing: 16) {
                    // Buy More Credits
                    Button(action: onBuyMore) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Buy More Credits")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    // Language Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Language")
                            .font(.headline)
                        
                        Picker("Language", selection: $selectedLanguage) {
                            ForEach(availableLanguages, id: \.0) { code, name in
                                Text(name).tag(code)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Support Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Support")
                            .font(.headline)
                        
                        Text("If you have any issues, write here 💬")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button("Contact Support") {
                            // Open support chat or email
                            if let url = URL(string: "mailto:support@aisixteen.com") {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                Spacer()
                
                // Logout Button
                Button(action: onLogout) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Logout")
                    }
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
            }
            .padding()
            .navigationTitle("Account")
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

struct AccountModal_Previews: PreviewProvider {
    static var previews: some View {
        AccountModal(
            isPresented: .constant(true),
            user: FantasticUser(
                id: "1",
                displayName: "John Doe",
                email: "john@example.com",
                credits: 1500.0
            ),
            onBuyMore: {},
            onLogout: {}
        )
    }
}
