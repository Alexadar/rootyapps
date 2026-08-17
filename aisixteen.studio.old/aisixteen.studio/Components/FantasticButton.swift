import SwiftUI

struct FantasticButton: View {
    let label: String
    let disabled: Bool
    let action: () -> Void
    let width: CGFloat

    init(label: String, disabled: Bool = false, width:CGFloat = 0, action: @escaping () -> Void) {
        self.label = label
        self.disabled = disabled
        self.action = action
        self.width = width
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .padding(10)
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .if(self.width != 0) {
                    view in view.frame(width: self.width)
                }
        }
        .if(!disabled) { view in
            view
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(hue: 0.103, saturation: 0.97, brightness: 0.7, opacity: 0.9),
                            Color(hue: 0.913, saturation: 0.7, brightness: 0.58)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.clear)
        }
        .if(disabled) {
            view in
                view
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(hue: 0.103, saturation: 0.97, brightness: 0.7, opacity: 0.9),
                            Color(hue: 0.913, saturation: 0.7, brightness: 0.58, opacity: 0.9)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .cornerRadius(5) /// make the background rounded
        .overlay( /// apply a rounded border
            RoundedRectangle(cornerRadius: 5)
                .stroke(.white, lineWidth: 0.5)
        )
        .disabled(disabled)
    }
}

struct FantasticButton_Previews: PreviewProvider {
    static var previews: some View {
        FantasticButton(label: "Button aaa", disabled: true, width: 200, action: {})
    }
}
