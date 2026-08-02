//
//  SnackbarView.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 20.11.2023.
//

import SwiftUI

struct SnackbarView: View {
    let message: String
    let isVisible: Bool
    let onDismiss: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            
            if isVisible {
                HStack {
                    Text(message)
                        .foregroundColor(.white)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .font(.caption)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.8))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.bottom, 100) // Above tab bar
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: isVisible)
            }
        }
        .allowsHitTesting(isVisible)
    }
}

// Observable class to manage snackbar state
class SnackbarManager: ObservableObject {
    @Published var message: String = ""
    @Published var isVisible: Bool = false
    
    private var dismissTimer: Timer?
    
    func show(message: String, duration: TimeInterval = 3.0) {
        self.message = message
        self.isVisible = true
        
        // Auto-dismiss after duration
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            self.dismiss()
        }
    }
    
    func dismiss() {
        isVisible = false
        dismissTimer?.invalidate()
        dismissTimer = nil
    }
}

// View modifier for easy snackbar integration
struct SnackbarModifier: ViewModifier {
    @ObservedObject var snackbarManager: SnackbarManager
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            SnackbarView(
                message: snackbarManager.message,
                isVisible: snackbarManager.isVisible,
                onDismiss: snackbarManager.dismiss
            )
        }
    }
}

extension View {
    func snackbar(_ manager: SnackbarManager) -> some View {
        modifier(SnackbarModifier(snackbarManager: manager))
    }
}

struct SnackbarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Text("Main Content")
            Spacer()
        }
        .snackbar(SnackbarManager())
        .onAppear {
            let manager = SnackbarManager()
            manager.show(message: "This is a test snackbar message!")
        }
    }
}
