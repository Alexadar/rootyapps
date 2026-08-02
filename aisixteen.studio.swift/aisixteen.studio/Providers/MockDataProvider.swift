//
//  MockDataProvider.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 21.11.2023.
//

import Foundation

public class MockDataProvider: ObservableObject, DataProviderProtocol {
    @Published public var isLoggedIn: Bool = false
    
    public init() {}
    
    func login(provder: loginProvider = .apple, token: String) {
        isLoggedIn = true
    }

    func tryAutoLogin() -> Bool {
        return false
    }
    
    func logout() {
        isLoggedIn = false
    }
    
}
