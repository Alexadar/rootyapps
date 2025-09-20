//
//  SideMenu.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 20.11.2023.
//

import Foundation
import SwiftUI

struct MainMenu: View {

    @Binding var isPresented: Bool 
    var body: some View {
        FantasticModal(
            showCloseButton: true,
            onClose: {
                isPresented.toggle()
            }
        ) {
            VStack {
                FantasticButton(label: "Create image", width: 200, action: {})
                FantasticButton(label: "Profile", width: 200, action: {})
                FantasticButton(label: "Logout", width: 200, action: {})
            }
        }
    }
}

struct MainMenu_Previews: PreviewProvider {
    static var previews: some View {
        MainMenu(isPresented: .constant(true))
    }
}
