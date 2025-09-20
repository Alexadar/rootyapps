//
//  Created by Oleksandr Koreniuk on 19.11.2023.
//

import Foundation
import SwiftUI

struct ImagesView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass: UserInterfaceSizeClass?

    private static let maxWidth: CGFloat = 500
    var gridColumns: [GridItem] {
        let initialColumns = Int(ceil(UIScreen.main.bounds.width / ImagesView.maxWidth))
        let numColumns = initialColumns
        return Array(repeating: GridItem(.flexible(), spacing: 0), count: numColumns)
    }

    @Binding var tasks: [FantasticTask] // External array of FantasticTask
    
    var body: some View {
        ScrollView {
                ZStack{
                    Color.clear.ignoresSafeArea().background(.clear)
                    LazyVGrid(columns: gridColumns, spacing: 0) {
                        ForEach(tasks) { item in
                            FantasticImage(
                                onDelete: nil,
                                onRestart: nil,
                                onInfo: nil,
                                onHandleMouseOver: nil,
                                isHoveringId: nil,
                                hideHeader: nil,
                                useParentIdForThumb: false,
                                thumb: false,
                                showGradBG: nil,
                                model: FantasticImageModel(task: item, thumb: true)
                            )
                            .frame(maxWidth: .infinity)
                    } 
                }
            }
            .foregroundColor(.clear)
            .foregroundStyle(.clear)
            .padding(.top, 50)
        }
    }
}

struct ImagesView_Previews: PreviewProvider {
    static var previews: some View {
        ImagesView(tasks: .constant(Array(0..<4).map { i in FantasticTask(
            id: -i,
            type: FantasticTaskTypes.image, 
            state: FantasticTaskStates.stateDone) 
        }))
    }
}
