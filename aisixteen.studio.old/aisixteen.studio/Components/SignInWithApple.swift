import SwiftUI
import AuthenticationServices

struct QuickSignInWithApple: UIViewRepresentable {
  
  func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
    return ASAuthorizationAppleIDButton(type: .signIn,
                                        style: .white)
  }

  func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
  }
}
