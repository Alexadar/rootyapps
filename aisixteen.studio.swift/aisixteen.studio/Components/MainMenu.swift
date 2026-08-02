//
//  SideMenu.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 20.11.2023.
//

import Foundation
import SwiftUI

struct MainMenu: View {
    @Binding var isPresented: Bool
    
    let onCreateImage: () -> Void
    let onAccount: () -> Void
    let onChat: () -> Void
    let onFAQ: () -> Void
    let onLogout: () -> Void
    
    init(
        isPresented: Binding<Bool>,
        onCreateImage: @escaping () -> Void = {},
        onAccount: @escaping () -> Void = {},
        onChat: @escaping () -> Void = {},
        onFAQ: @escaping () -> Void = {},
        onLogout: @escaping () -> Void = {}
    ) {
        self._isPresented = isPresented
        self.onCreateImage = onCreateImage
        self.onAccount = onAccount
        self.onChat = onChat
        self.onFAQ = onFAQ
        self.onLogout = onLogout
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundColor(.blue)
                    
                    Text("AISixteen Studio")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Menu Items
                VStack(spacing: 16) {
                    MenuButton(
                        title: "Create Image",
                        subtitle: "Generate AI artwork",
                        icon: "plus.circle.fill",
                        color: .blue
                    ) {
                        onCreateImage()
                        isPresented = false
                    }
                    
                    MenuButton(
                        title: "Chat with AI",
                        subtitle: "Ask questions about AI art",
                        icon: "message.circle.fill",
                        color: .green
                    ) {
                        onChat()
                        isPresented = false
                    }
                    
                    MenuButton(
                        title: "Account",
                        subtitle: "Manage your profile",
                        icon: "person.circle.fill",
                        color: .orange
                    ) {
                        onAccount()
                        isPresented = false
                    }
                    
                    MenuButton(
                        title: "FAQ",
                        subtitle: "Frequently asked questions",
                        icon: "questionmark.circle.fill",
                        color: .purple
                    ) {
                        onFAQ()
                        isPresented = false
                    }
                }
                
                Spacer()
                
                // Logout Button
                Button(action: {
                    onLogout()
                    isPresented = false
                }) {
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
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

struct MenuButton: View {
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
        .padding(.horizontal)
    }
}

struct MainMenu_Previews: PreviewProvider {
    static var previews: some View {
        MainMenu(isPresented: .constant(true))
    }
}
