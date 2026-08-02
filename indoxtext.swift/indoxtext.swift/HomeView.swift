import SwiftUI

#if !os(macOS)
struct HomeView: View {
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            VStack(spacing: 10) {
                Text("Indox Text")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 20)
            }
            
            VStack(spacing: 15) {
                Button(action: {
                    navigationCoordinator.navigate(to: .fromText)
                }) {
                    HStack {
                        Image(systemName: "text.alignleft")
                            .font(.title2)
                            .foregroundColor(.white)
                        Text("Summarize text")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                
                Button(action: {
                    navigationCoordinator.navigate(to: .fromFile)
                }) {
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.title2)
                            .foregroundColor(.white)
                        Text("Summarize file")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    HomeView()
        .environmentObject(NavigationCoordinator())
}
#endif
