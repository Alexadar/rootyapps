import AuthenticationServices
import CryptoKit
import FirebaseAuth
import SwiftUI

public class SignInWithAppleViewModel: NSObject, ASAuthorizationControllerDelegate, ObservableObject {
    var mainProvider: MainProvider? = nil
    
    public func setProvider(mainProvider: MainProvider) {
        self.mainProvider = mainProvider
    }
    
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        print("\n -- ASAuthorizationControllerDelegate -\(#function) -- \n")
        if let appleIdCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            print("authorization is an ASAuthorizationAppleIDCredential")
            Task {
                print("run firebaseAuth")
                try await self.firebaseAuth(appleIDCredential: appleIdCredential)
            }
        } else {
            // Handle the case when the authorization is not an ASAuthorizationAppleIDCredential
            print("authorization is not an ASAuthorizationAppleIDCredential")
        }
    }
    
    public func authorizationController(
        controller: ASAuthorizationController, didCompleteWithError error: Error
    ) {
        print("\n -- ASAuthorizationControllerDelegate -\(#function) -- \n")
        print(error)
        // Give Call Back to UI
    }
}

extension SignInWithAppleViewModel {
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError(
                "Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)"
            )
        }
        
        let charset: [Character] =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        
        let nonce = randomBytes.map { byte in
            // Pick a random character from the set, wrapping around if needed.
            charset[Int(byte) % charset.count]
        }
        
        return String(nonce)
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
    
    private func firebaseAuth(appleIDCredential: ASAuthorizationAppleIDCredential) async throws {
        let nonce = randomNonceString()
        // Initialize a Firebase credential, including the user's full name.
        let credential = OAuthProvider.appleCredential(
            withIDToken: String(data: appleIDCredential.identityToken!, encoding: .utf8)!,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName)
        
        do {
            // Sign in with Firebase.
            let authResult = try await Auth.auth().signIn(with: credential)
            
            do {
                print("authResult.user.getIDToken")
                let token = try await authResult.user.getIDToken()
                do {
                    await self.mainProvider!.login(token: token)
                }
            } catch {
                print("error getIDToken")
                throw error
            }
            
        } catch {
            print(error)
            DispatchQueue.main.async {
                self.mainProvider!.logout()
            }
        }
    }
}
