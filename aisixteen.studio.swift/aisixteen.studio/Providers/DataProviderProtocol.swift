//
//  DataProviderProtocol.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 21.11.2023.
//

import Foundation

enum loginProvider {
    case apple
    case google
}

protocol DataProviderProtocol: ObservableObject {
    var isLoggedIn: Bool { get }
    
    func login(provder: loginProvider, token: String) async

    func tryAutoLogin() async -> Bool
    
    func logout()
}
