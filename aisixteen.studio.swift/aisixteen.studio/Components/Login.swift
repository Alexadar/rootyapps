import AuthenticationServices
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import GoogleSignInSwift
import SwiftUI

let exampleImages = [
  URL(string: "https://storage.googleapis.com/aisixteen_public/studio/examples/1_1.jpg")!,
  URL(string: "https://storage.googleapis.com/aisixteen_public/studio/examples/1_2.jpg")!,
  URL(string: "https://storage.googleapis.com/aisixteen_public/studio/examples/1_3.jpg")!,
  URL(string: "https://storage.googleapis.com/aisixteen_public/studio/examples/1_4.jpg")!,
  URL(string: "https://storage.googleapis.com/aisixteen_public/studio/examples/1_1.jpg")!,
]

let bgImages = [
  URL(string: "https://storage.googleapis.com/aisixteen_public/studio/bg/1.jpg")!,
  URL(string: "https://storage.googleapis.com/aisixteen_public/studio/bg/2.jpg")!,
  URL(string: "https://storage.googleapis.com/aisixteen_public/studio/bg/3.jpg")!,
  URL(string: "https://storage.googleapis.com/aisixteen_public/studio/bg/4.jpg")!,
  URL(string: "https://storage.googleapis.com/aisixteen_public/studio/bg/5.jpg")!,
  URL(string: "https://storage.googleapis.com/aisixteen_public/studio/bg/6.jpg")!,
  URL(string: "https://storage.googleapis.com/aisixteen_public/studio/bg/7.jpg")!,
  URL(string: "https://storage.googleapis.com/aisixteen_public/studio/bg/8.jpg")!,
  URL(string: "https://storage.googleapis.com/aisixteen_public/studio/bg/9.jpg")!,
  URL(string: "https://storage.googleapis.com/aisixteen_public/studio/bg/10.jpg")!,
]

struct LoginPage: View {

  @EnvironmentObject var mainProvider: MainProvider
  let signInWithAppleViewModel = SignInWithAppleViewModel()

  private func showAppleLoginView() {
    signInWithAppleViewModel.setProvider(mainProvider: self.mainProvider)
    // 1. Instantiate the AuthorizationAppleIDProvider
    let provider = ASAuthorizationAppleIDProvider()
    // 2. Create a request with the help of provider - ASAuthorizationAppleIDRequest
    let request = provider.createRequest()
    // 3. Scope to contact information to be requested from the user during authentication.
    request.requestedScopes = [.email]
    // 4. A controller that manages authorization requests created by a provider.
    let controller = ASAuthorizationController(authorizationRequests: [request])
    // 5. Set delegate to perform action
    controller.delegate = signInWithAppleViewModel
    // 6. Initiate the authorization flows.
    controller.performRequests()
  }

  var randomImageURL: URL {
    bgImages.randomElement()!
  }

  var body: some View {
    ZStack {
      AsyncImage(url: randomImageURL) { image in
        image.resizable()
      } placeholder: {
        ProgressView()
      }
      .scaledToFill()
      .edgesIgnoringSafeArea(.all)

      VStack {
        Spacer()
        FantasticModal {
          Image(uiImage: (UIImage(named: "AppIcon"))!)
            .antialiased( /*@START_MENU_TOKEN@*/true /*@END_MENU_TOKEN@*/)
            .resizable()
            .frame(width: 128, height: 128)
            .scaledToFit()

          Spacer().frame(height: 30)

          Text("AISixteen Studio")
            .font(.headline)
            .fontWeight(.bold)
            .foregroundColor(.white)

          Spacer().frame(height: 20)

          QuickSignInWithApple()
              .frame(width: 135, height: 10)
              .onTapGesture(perform: showAppleLoginView)
              .padding(10)

          Link(destination: URL(string: "https://aisixteen.com/studio")!) {
            Text("How It Works")
          }
          .foregroundColor(.white)
          .padding()
        }
        Spacer()
      }
    }
  }
}

struct LoginPage_Previews: PreviewProvider {
  static var previews: some View {
    LoginPage()
  }
}
