//
//  TopBar.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 20.11.2023.
//

import Foundation
import SwiftUI

struct TopBar: View {
    @Binding var openMenu: Bool
    @Binding var openCreateTask: Bool
    var body: some View {
        HStack(alignment: .center) {
            Button(action: { openMenu = !openMenu }) {
                Image(systemName: "line.horizontal.3")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
            }
            
            Spacer()

            HStack {
                Image(uiImage: (UIImage(named: "AppIcon"))! )
                    .antialiased(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
                    .resizable()
                    .frame(width: 30, height: 30)
                    .scaledToFit()
                
                Text("AI Sixteen")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            Spacer()
            
            FantasticButton(label: "Create", action: {
                openCreateTask = true
            })
        }
        .padding(.top, 10)
        .padding(.trailing, 25)
        .padding(.leading, 25)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }
}

struct TopBar_Previews: PreviewProvider {
    static var previews: some View {
        TopBar(openMenu: .constant(false), openCreateTask: .constant(false))
    }
}
