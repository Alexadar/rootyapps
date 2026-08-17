//
//  MainProvider.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 21.11.2023.
//

import Foundation

public class MainProvider: ObservableObject {
    @Published var dataProvider: any DataProviderProtocol

    init(mock: Bool) {
        self.dataProvider = mock ? MockDataProvider() : DataProvider()
    }

    func login(token: String) async {
        await dataProvider.login(provder: .apple, token: token)
    }

    func logout() {
        dataProvider.logout()
    }
}
