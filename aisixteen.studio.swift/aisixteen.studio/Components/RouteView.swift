//
//  Router.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 20.11.2023.
//

import SwiftUI

struct RouterView: View {
    @EnvironmentObject var mainProvider: MainProvider
    @State private var tryingAutoLogin: Bool = true
    
    var body: some View {
        Group {
            if tryingAutoLogin {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if mainProvider.dataProvider.isLoggedIn {
                AppView()
                    .environmentObject(mainProvider)
            } else {
                LoginPage()
                    .environmentObject(mainProvider)
            }
        }
        .onAppear {
            Task {
                let loginResult = await mainProvider.dataProvider.tryAutoLogin()
                tryingAutoLogin = false
            }
        }
    }
}

struct RouterPreview: PreviewProvider {
    static var previews: some View {
        RouterView()
            .environmentObject(MainProvider.init(mock: true))
    }
}
