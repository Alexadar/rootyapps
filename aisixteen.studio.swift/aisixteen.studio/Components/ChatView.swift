//
//  ChatView.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 20.11.2023.
//

import SwiftUI

struct ChatView: View {
    @Binding var isPresented: Bool
    @State private var message: String = ""
    @State private var chatRecords: [ChatRecord] = []
    @State private var isLoading: Bool = false
    
    let onSendMessage: (String) -> Void
    
    private let suggestedQuestions = [
        "How does AI image generation work?",
        "What makes a good prompt?",
        "How to improve image quality?",
        "What are negative prompts?",
        "How to use different AI models?"
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Chat Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(chatRecords) { record in
                                ChatMessageView(record: record)
                                    .id(record.id)
                            }
                            
                            if isLoading {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("AI is thinking...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding()
                            }
                        }
                        .padding()
                    }
                    .onChange(of: chatRecords.count) { _ in
                        if let lastRecord = chatRecords.last {
                            withAnimation {
                                proxy.scrollTo(lastRecord.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Input Area
                VStack(spacing: 8) {
                    // Suggested Questions (show when no messages)
                    if chatRecords.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestedQuestions, id: \.self) { question in
                                    Button(question) {
                                        message = question
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(16)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Message Input
                    HStack {
                        TextField("Type your question here, in any language", text: $message, axis: .vertical)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .lineLimit(1...4)
                            .disabled(isLoading)
                        
                        Button(action: sendMessage) {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(canSend ? .blue : .gray)
                        }
                        .disabled(!canSend)
                    }
                    .padding()
                }
            }
            .navigationTitle("Chat with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        chatRecords.removeAll()
                    }
                    .disabled(chatRecords.isEmpty)
                }
            }
        }
    }
    
    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }
    
    private func sendMessage() {
        let userMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        
        // Add user message
        let userRecord = ChatRecord(
            id: UUID().uuidString,
            role: .user,
            content: userMessage,
            timestamp: Date()
        )
        chatRecords.append(userRecord)
        
        // Clear input and show loading
        message = ""
        isLoading = true
        
        // Send message
        onSendMessage(userMessage)
    }
    
    func addBotResponse(_ response: String) {
        let botRecord = ChatRecord(
            id: UUID().uuidString,
            role: .bot,
            content: response,
            timestamp: Date()
        )
        chatRecords.append(botRecord)
        isLoading = false
    }
    
    func setLoading(_ loading: Bool) {
        isLoading = loading
    }
}

struct ChatMessageView: View {
    let record: ChatRecord
    
    var body: some View {
        HStack {
            if record.role == .user {
                Spacer()
                VStack(alignment: .trailing) {
                    Text(record.content)
                        .padding(12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .frame(maxWidth: 250, alignment: .trailing)
                    
                    Text(formatTime(record.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading) {
                    Text(record.content)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                        .frame(maxWidth: 250, alignment: .leading)
                    
                    Text(formatTime(record.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        ChatView(
            isPresented: .constant(true),
            onSendMessage: { _ in }
        )
    }
}
