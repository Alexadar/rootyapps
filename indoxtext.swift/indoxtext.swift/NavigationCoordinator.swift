import SwiftUI
import Combine

enum NavigationDestination: Hashable {
    case home
    case fromText
    case fromFile
    case result
}

class NavigationCoordinator: ObservableObject {
    @Published var currentDestination: NavigationDestination = .home
    @Published var navigationPath = NavigationPath()
    
    func navigate(to destination: NavigationDestination) {
        currentDestination = destination
        navigationPath.append(destination)
    }
    
    func navigateBack() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }
    
    func navigateToRoot() {
        navigationPath = NavigationPath()
        currentDestination = .home
    }
}
