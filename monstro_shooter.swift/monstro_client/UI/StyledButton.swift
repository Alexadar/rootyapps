import SwiftUI

// MARK: - Primary Button (PLAY style)
struct PrimaryButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: UIStyleGuide.Button.Primary.fontSize, weight: .bold))
                .foregroundColor(Color(UIStyleGuide.Button.Primary.textColor))
                .shadow(
                    color: Color(UIStyleGuide.Button.Primary.textColor).opacity(UIStyleGuide.Button.Primary.textShadowOpacity),
                    radius: UIStyleGuide.Button.Primary.textShadowRadius,
                    x: 0, y: 0
                )
                .padding(.horizontal, UIStyleGuide.Button.Primary.paddingHorizontal)
                .padding(.vertical, UIStyleGuide.Button.Primary.paddingVertical)
                .background(
                    RoundedRectangle(cornerRadius: UIStyleGuide.Button.Primary.cornerRadius)
                        .fill(Color(UIStyleGuide.Button.Primary.backgroundColor).opacity(UIStyleGuide.Button.Primary.backgroundOpacity))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: UIStyleGuide.Button.Primary.cornerRadius)
                        .stroke(Color(UIStyleGuide.Button.Primary.borderColor), lineWidth: UIStyleGuide.Button.Primary.borderWidth)
                        .shadow(
                            color: Color(UIStyleGuide.Button.Primary.borderColor).opacity(UIStyleGuide.Button.Primary.borderShadowOpacity),
                            radius: UIStyleGuide.Button.Primary.borderShadowRadius,
                            x: 0, y: 0
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Secondary Button (SETTINGS style)
struct SecondaryButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: UIStyleGuide.Button.Secondary.fontSize, weight: .bold))
                .foregroundColor(Color(UIStyleGuide.Button.Secondary.textColor))
                .shadow(
                    color: Color(UIStyleGuide.Button.Secondary.textColor).opacity(UIStyleGuide.Button.Secondary.textShadowOpacity),
                    radius: UIStyleGuide.Button.Secondary.textShadowRadius,
                    x: 0, y: 0
                )
                .padding(.horizontal, UIStyleGuide.Button.Secondary.paddingHorizontal)
                .padding(.vertical, UIStyleGuide.Button.Secondary.paddingVertical)
                .background(
                    RoundedRectangle(cornerRadius: UIStyleGuide.Button.Secondary.cornerRadius)
                        .fill(Color(UIStyleGuide.Button.Secondary.backgroundColor).opacity(UIStyleGuide.Button.Secondary.backgroundOpacity))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: UIStyleGuide.Button.Secondary.cornerRadius)
                        .stroke(Color(UIStyleGuide.Button.Secondary.borderColor), lineWidth: UIStyleGuide.Button.Secondary.borderWidth)
                        .shadow(
                            color: Color(UIStyleGuide.Button.Secondary.borderColor).opacity(UIStyleGuide.Button.Secondary.borderShadowOpacity),
                            radius: UIStyleGuide.Button.Secondary.borderShadowRadius,
                            x: 0, y: 0
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
