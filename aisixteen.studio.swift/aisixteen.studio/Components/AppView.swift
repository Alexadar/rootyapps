//
//  AppView.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 20.11.2023.
//

import SwiftUI

struct AppView: View {
    @EnvironmentObject var mainProvider: MainProvider
    @State private var tasks: [FantasticTask] = []
    @State private var user: FantasticUser?
    @State private var packs: [CreditsPack] = []
    @State private var prices: Prices?
    @State private var chatRecords: [ChatRecord] = []
    
    // UI State
    @State private var openModal: Bool = false
    @State private var showCreateTask: Bool = false
    @State private var showChat: Bool = false
    @State private var showBuyPacks: Bool = false
    @State private var showAccount: Bool = false
    @State private var showActionPopup: Bool = false
    @State private var selectedTask: FantasticTask?
    @State private var createTask: FantasticTask = FantasticTask()
    @State private var isLoading: Bool = false
    @State private var page: Int = 1
    @State private var pageSize: Int = 20
    @State private var totalCount: Int = 0
    
    // Managers
    @StateObject private var snackbarManager = SnackbarManager()
    
    func fetchData() async {
        isLoading = true
        do {
            let response = try await Api.shared.getTasks(page: page, pageSize: pageSize)
            tasks = response.tasks
            totalCount = response.totalCount
        } catch {
            snackbarManager.show(message: "Error loading images: \(error.localizedDescription)")
            tasks = []
        }
        isLoading = false
    }
    
    func fetchUser() async {
        do {
            user = try await Api.shared.getMe()
        } catch {
            snackbarManager.show(message: "Error loading user data")
        }
    }
    
    func fetchPacks() async {
        do {
            let response = try await Api.shared.getPacks()
            packs = response.packs
            prices = response.prices
        } catch {
            snackbarManager.show(message: "Error loading packs")
        }
    }
    
    func fetchChatMessages() async {
        do {
            chatRecords = try await Api.shared.getChatMessages()
        } catch {
            snackbarManager.show(message: "Error loading chat messages")
        }
    }
    
    func createTaskAction(task: FantasticTask, quantity: Int) {
        Task {
            isLoading = true
            do {
                try await Api.shared.postDiffuseTask(task, quantity: quantity)
                snackbarManager.show(message: "\(quantity) image(s) put in queue successfully")
                await fetchData()
                await fetchUser()
                showCreateTask = false
            } catch {
                handleError(error)
            }
            isLoading = false
        }
    }
    
    func deleteTask(_ task: FantasticTask) {
        Task {
            isLoading = true
            do {
                try await Api.shared.deleteTasks([task.id])
                snackbarManager.show(message: "Image deleted successfully")
                await fetchData()
                showActionPopup = false
            } catch {
                handleError(error)
            }
            isLoading = false
        }
    }
    
    func upscaleTask(_ task: FantasticTask) {
        Task {
            isLoading = true
            do {
                try await Api.shared.postUpscaleTask(task)
                snackbarManager.show(message: "Image upscale put in queue successfully")
                await fetchData()
                await fetchUser()
                showActionPopup = false
            } catch {
                handleError(error)
            }
            isLoading = false
        }
    }
    
    func createSimilarTask(_ task: FantasticTask, quantity: Int) {
        Task {
            isLoading = true
            do {
                try await Api.shared.postRepaintTask(task, quantity: quantity)
                snackbarManager.show(message: "\(quantity) similar image(s) put in queue successfully")
                await fetchData()
                await fetchUser()
                showActionPopup = false
            } catch {
                handleError(error)
            }
            isLoading = false
        }
    }
    
    func sendChatMessage(_ message: String) {
        Task {
            do {
                chatRecords = try await Api.shared.sendChatMessage(message)
            } catch {
                handleError(error)
            }
        }
    }
    
    func purchasePack(_ packId: Int) {
        Task {
            do {
                let checkoutUrl = try await Api.shared.getCheckoutUrl(packId)
                if let url = URL(string: checkoutUrl) {
                    UIApplication.shared.open(url)
                }
            } catch {
                handleError(error)
            }
        }
    }
    
    func downloadImage(_ task: FantasticTask) {
        guard !task.details.resultUrl.isEmpty,
              let url = URL(string: task.details.resultUrl) else {
            snackbarManager.show(message: "No image to download")
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    snackbarManager.show(message: "Image saved to Photos")
                }
            } catch {
                snackbarManager.show(message: "Failed to download image")
            }
        }
    }
    
    func handleError(_ error: Error) {
        // Parse error and show appropriate message
        snackbarManager.show(message: "An error occurred. Please try again.")
    }
    
    func logout() {
        Task {
            await mainProvider.dataProvider.logout()
        }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.ignoresSafeArea().background(.ultraThinMaterial)
            
            TopBar(
                openMenu: $openModal,
                openCreateTask: $showCreateTask
            )
            .zIndex(2.0)
            .background(.ultraThinMaterial)
            
            VStack {
                if totalCount == 0 && !isLoading {
                    // Empty state
                    VStack(spacing: 20) {
                        Spacer()
                        Text("No images yet")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        Button("Create your first image") {
                            createTask = FantasticTask()
                            showCreateTask = true
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                } else {
                    ImagesView(
                        tasks: $tasks,
                        onTaskTap: { task in
                            selectedTask = task
                            showActionPopup = true
                        },
                        onDeleteTask: deleteTask
                    )
                    .zIndex(1.0)
                    
                    // Pagination
                    if totalCount > pageSize {
                        HStack {
                            Button("Previous") {
                                if page > 1 {
                                    page -= 1
                                    Task { await fetchData() }
                                }
                            }
                            .disabled(page <= 1)
                            
                            Spacer()
                            
                            Text("Page \(page) of \(Int(ceil(Double(totalCount) / Double(pageSize))))")
                                .font(.caption)
                            
                            Spacer()
                            
                            Button("Next") {
                                if page < Int(ceil(Double(totalCount) / Double(pageSize))) {
                                    page += 1
                                    Task { await fetchData() }
                                }
                            }
                            .disabled(page >= Int(ceil(Double(totalCount) / Double(pageSize))))
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                    }
                }
            }
        }
        .snackbar(snackbarManager)
        .fullScreenCover(isPresented: $openModal) {
            MainMenu(
                isPresented: $openModal,
                onCreateImage: {
                    createTask = FantasticTask()
                    showCreateTask = true
                },
                onAccount: {
                    showAccount = true
                },
                onChat: {
                    showChat = true
                },
                onFAQ: {
                    // TODO: Implement FAQ view
                },
                onLogout: logout
            )
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showCreateTask) {
            if let user = user, let prices = prices {
                CreateItemPopup(
                    isPresented: $showCreateTask,
                    task: $createTask,
                    user: user,
                    prices: prices,
                    onCancel: { showCreateTask = false },
                    onCreate: createTaskAction
                )
            }
        }
        .sheet(isPresented: $showChat) {
            ChatView(
                isPresented: $showChat,
                onSendMessage: sendChatMessage
            )
        }
        .sheet(isPresented: $showBuyPacks) {
            BuyPacksPopup(
                isPresented: $showBuyPacks,
                packs: packs,
                onPurchase: purchasePack
            )
        }
        .sheet(isPresented: $showAccount) {
            if let user = user {
                AccountModal(
                    isPresented: $showAccount,
                    user: user,
                    onBuyMore: { showBuyPacks = true },
                    onLogout: logout
                )
            }
        }
        .sheet(isPresented: $showActionPopup) {
            if let task = selectedTask, let user = user, let prices = prices {
                ActionPopup(
                    isPresented: $showActionPopup,
                    task: task,
                    user: user,
                    prices: prices,
                    onCreateSimilar: createSimilarTask,
                    onCreateSamePrompt: { task, quantity in
                        createTask = task
                        createTask.details.baseimage = ""
                        showCreateTask = true
                        showActionPopup = false
                    },
                    onUpscale: upscaleTask,
                    onDelete: deleteTask,
                    onDownload: downloadImage
                )
            }
        }
        .onAppear {
            Task {
                await fetchData()
                await fetchUser()
                await fetchPacks()
                await fetchChatMessages()
            }
        }
        .refreshable {
            Task {
                await fetchData()
                await fetchUser()
            }
        }
    }
}

struct AppView_Previews: PreviewProvider {
    static var previews: some View {
        AppView()
            .environmentObject(MainProvider(mock: true))
    }
}
