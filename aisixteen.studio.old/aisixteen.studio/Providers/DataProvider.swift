//
//  UserProvider.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 20.11.2023.
//

import Foundation
import Combine
import CryptoKit
import AuthenticationServices

public class DataProvider: ObservableObject, DataProviderProtocol {
    
    @Published var isLoggedIn = false
    
    var loginProvider: loginProvider = .apple
    let userTokenString = "userToken"
    
    public init() {}
    
    func appleLogin() {

    }

    func tryAutoLogin() async -> Bool {
        if let token = UserDefaults.standard.string(forKey: userTokenString) {
            do {
                print("tryAutoLogin")
                try await login(provder: .apple, token: token)
                print("tryAutoLogin success")
                return true
            } catch {
                print("tryAutoLogin error")
                return false
            }
        }
        print("tryAutoLogin - no key")
        return false
    }
    
    func login(provder: loginProvider = .apple, token: String) async {
        do {
            self.loginProvider = provder
            try await Api.shared.authenticateWithFirebase(token: token)
            UserDefaults.standard.set(token, forKey: userTokenString)
            isLoggedIn = true
        } catch {
            isLoggedIn = false
        }
    }
    
    func logout() {
        isLoggedIn = false
    }
    
}
