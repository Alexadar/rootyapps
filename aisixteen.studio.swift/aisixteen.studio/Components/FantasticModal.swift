import Foundation
import SwiftUI

struct FantasticModal<Content: View>: View {
    let content: Content
    let showCloseButton: Bool
    let onClose: (() -> Void)?
    
    init(showCloseButton: Bool = false, onClose: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.showCloseButton = showCloseButton
        self.onClose = onClose
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack{
                content
            }
            .padding(50)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hue: 37/360, saturation: 0.97, brightness: 0.7).opacity(0.1),
                        Color(hue: 329/360, saturation: 0.7, brightness: 0.58).opacity(0.6)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .background(.ultraThinMaterial)
            .border(Color.white.opacity(0.5), width: 0.1)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.5), lineWidth: 1))
            if showCloseButton {
                Button(action: {
                    onClose?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
                .offset(x: -15, y: -15)
            }
        }
    }
}

struct FantasticModal_Previews: PreviewProvider {
    static var previews: some View {
        FantasticModal(showCloseButton: true) {
            VStack {
                Text("param")
                
                HStack {
                    Button(action: {
                        // Button 1 action
                    }) {
                        Text("Button 1")
                    }
                    
                    Button(action: {
                        // Button 2 action
                    }) {
                        Text("Button 2")
                    }
                    
                    Button(action: {
                        // Button 3 action
                    }) {
                        Text("Button 3")
                    }
                }
            }
        }
    }
}
