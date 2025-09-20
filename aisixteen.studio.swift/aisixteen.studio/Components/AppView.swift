//
//  AppView.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 20.11.2023.
//

import SwiftUI

struct AppView: View {
    @State private var tasks: [FantasticTask] = []
    @State private var openModal: Bool = false
    
    func fetchData() async {
        do {
            let response = try await Api.shared.getTasks()
            tasks = response.tasks
        } catch {
            //todo: handle
            print(error)
            tasks = []
        }
//        tasks = Array(0..<10).map { i in FantasticTask(
//            id: -i,
//            type: FantasticTaskTypes.image,
//            state: FantasticTaskStates.stateDone)
//        }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.ignoresSafeArea().background(.ultraThinMaterial)
            TopBar(openMenu: $openModal, openCreateTask: .constant(false))
                .zIndex(2.0)
                .background(.ultraThinMaterial)
            ImagesView(tasks: $tasks)
                    .zIndex(1.0)
        }.fullScreenCover(
            isPresented: $openModal,
            onDismiss: {
                openModal = false
            }) {
            VStack{
                MainMenu(isPresented: $openModal)
            }
            .presentationBackground(.ultraThinMaterial)
        }.onAppear {
            Task {
                await fetchData()
            }
        }
    }
}

struct AppView_Previews: PreviewProvider {
    static var previews: some View {
        AppView()
    }
}

