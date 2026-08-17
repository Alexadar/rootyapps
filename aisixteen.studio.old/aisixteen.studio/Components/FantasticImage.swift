//
//  FantasticImage.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 19.11.2023.
//

import Foundation
import SwiftUI

struct FantasticImageView: View {
    @ObservedObject var model: FantasticImageModel
    //    if useParentIdForThumb {
    var body: some View {
        ZStack {
            AsyncImage(url: model.imageUrl){ image in
                image.resizable()
            } placeholder: {
                ProgressView()
            }
           .scaledToFill()
           .edgesIgnoringSafeArea(.all)
        }
        //    } else {
        //
        //        switch task.state {
        //        case .stateDone:
        //            return ZStack {
        //                AsyncImage(url: getImageUrl(id: task.id, thumb: thumb)){ image in
        //                    image.resizable()
        //                } placeholder: {
        //                    ProgressView()
        //                }
        //                .scaledToFill()
        //                .edgesIgnoringSafeArea(.all)
        //            }
        //        default:
        //            return ZStack {
        //                Image(uiImage: UIImage(named: "dummy") ?? UIImage())
        //                    .resizable()
        //                    .aspectRatio(contentMode: .fit)
        //                    .onAppear {
        //                        // Handle image loading completion
        //                    }
        //            }
        //        }
        //    }
    }
}

func infoHeader(model: FantasticImageModel) -> some View {
    func getErrorText(task: FantasticTask) -> String {
        switch task.state {
        case .stateCanceledNFSW:
            return "Image processing was canceled due to NSFW content."
        case .stateCanceledCannotDownloadImage:
            return "Image processing was canceled because the image could not be downloaded."
        case .stateCanceledCannotProcessImageExternalApi:
            return "Image processing was canceled because the image could not be processed by an external API."
        default:
            return "An error occurred while processing image with ID \(task.id)."
        }
    }
    
    func getErrorLine(task: FantasticTask) -> String {
        switch task.state {
        case .stateCanceledNFSW:
            return "Please try another prompt."
        case .stateCanceledCannotDownloadImage:
            return "Please try another image."
        case .stateCanceledCannotProcessImageExternalApi:
            return "Please try another image."
        default:
            return "Please report this issue to support."
        }
    }
    
    switch model.task.state {
    case .stateCanceledError, .stateCanceledNFSW, .stateCanceledCannotDownloadImage, .stateCanceledCannotProcessImageExternalApi, .stateCanceledStartup, .stateCanceledTimeout:
        return AnyView(
            VStack {
                Image(systemName: "xmark.circle")
                Text(getErrorText(task: model.task))
                Text(getErrorLine(task: model.task))
            }
                .padding()
        )
    case .stateCreated, .statePickedUp, .stateQueued:
        return AnyView(
            VStack {
                ZStack {
                    Rectangle()
                        .fill(Color.gray)
                        .opacity(0.5)
                    
                    Rectangle()
                        .fill(Color.white)
                        .opacity(0.8)
                        .cornerRadius(8)
                        .scaleEffect(0.8)
                        .animation(Animation.easeInOut(duration: 1).repeatForever(), value: true)
                }
                .padding()
                .background(Color.white)
            }
        )
    default:
        return AnyView(EmptyView())
    }
}

// func header(task: FantasticTask, hideHeader: Bool?, isHoveringId: Int? = nil, onDelete: ((Int) -> Void)? = nil, onInfo: ((FantasticTask) -> Void)? = nil) -> some View {
//     let iconSx: [String: Any] = [
//         "fill": "white",
//         "marginLeft": "80px",
//         "marginRight": "80px",
//         "fontSize": 60,
//         "stroke": "black",
//         "strokeWidth": "0.5px",
//         "backdropFilter": "blur(10px)",
//         "filter": "drop-shadow(3px 5px 2px rgb(0 0 0 / 0.4)) opacity(0.7)",
//         "borderRadius": 16
//     ]

//     let iconButtonSx: [String: Any] = [
//         "borderRadius": 0,
//         "width": "120px",
//         "height": "80px"
//     ]

//     return Group {
//         if let hideHeader = hideHeader, let isHoveringId = isHoveringId, !hideHeader && isHoveringId == task.id {
//             VStack {
//                 HStack {
//                     if canDownload(task) {
//                         Button(action: {
//                             guard let url = URL(string: taskImageUrl(task)) else { return }
//                             UIApplication.shared.open(url)
//                         }, label: {
//                             DownloadForOffline()
//                                 .foregroundColor(.white)
//                                 .frame(width: 60, height: 60)
//                                 .padding(.top, 8)
//                         })
//                         .buttonStyle(PlainButtonStyle())
//                         .frame(width: 120, height: 80)
//                     }

//                     Button(action: {
//                         onInfo?(task)
//                     }, label: {
//                         InfoIcon()
//                             .foregroundColor(.white)
//                             .frame(width: 60, height: 60)
//                     })
//                     .buttonStyle(PlainButtonStyle())
//                     .frame(width: 120, height: 80)

//                     if canDelete(task) {
//                         Button(action: {
//                             onDelete?(task.id)
//                         }, label: {
//                             DeleteIcon()
//                                 .foregroundColor(.white)
//                                 .frame(width: 60, height: 60)
//                         })
//                         .buttonStyle(PlainButtonStyle())
//                         .frame(width: 120, height: 80)
//                     }
//                 }
//                 .padding()
//                 .background(Color.black.opacity(0.5))
//                 .cornerRadius(32)
//                 .border(Color.white.opacity(0.3), width: 1)
//             }
//             .frame(height: UIScreen.main.bounds.height)
//             .position(x: UIScreen.main.bounds.width / 2, y: 0)
//             .zIndex(100)
//             .edgesIgnoringSafeArea(.all)
//         } else {
//             EmptyView()
//         }
//     }
// }

class FantasticImageModel: ObservableObject {
    @Published var imageUrl: URL? = nil
    public var task: FantasticTask
    var thumb: Bool

    init(task: FantasticTask, thumb: Bool = false) {
        self.task = task
        self.thumb = thumb
        loadUrl()
    }
    
    func getImageUrl(id: Int, thumb: Bool = true) -> URL {
        if id <= 0 {
            return exampleImages.randomElement()!
        } else {
            let baseUrl = Api.shared.api_base_url
            let thumbSuffix = thumb ? "thumb" : ""
            let url = URL(string: "\(baseUrl)task/image\(thumbSuffix)/\(id).jpg")
            return url!
        }
    }

    func loadUrl() {
        DispatchQueue.main.async { [self] in
            Task {
                do {
                    if !ImageCache.cacheExist(id: self.task.id) {
                        print("put to cache \(getImageUrl(id: self.task.id))")
                        try await ImageCache.processExternalUrl(id: self.task.id, url: getImageUrl(id: self.task.id))
                    }
                    
                    if ImageCache.cacheExist(id: self.task.id) {
                        print("get from cache \(ImageCache.get(id: self.task.id))")
                        self.imageUrl = URL(string: ImageCache.get(id: self.task.id))
                        self.objectWillChange.send()
                    }
                } catch {
                    //todo handle
                    print(error)
                }
            }
        }
    }
}

struct FantasticImage: View {
    let onDelete: ((Int) -> Void)?
    let onRestart: ((Int) -> Void)?
    let onInfo: ((FantasticTask) -> Void)?
    let onHandleMouseOver: ((Int?) -> Void)?
    let isHoveringId: Int?
    let hideHeader: Bool?
    let useParentIdForThumb: Bool
    let thumb: Bool
    let showGradBG: Bool?
    @State var model: FantasticImageModel
    
    var body: some View {
        return ZStack {
            // ImageListItem()
            //     .key(task.id)
            //     .onMouseOver { onHandleMouseOver?(task.id) }
            //     .onMouseOut { onHandleMouseOver?(nil) }
            
            FantasticImageView(model: model)
            //            header(task, hideHeader, isHoveringId, onDelete, onInfo)
            infoHeader(model: model)
        }
//        .background(
//            showGradBG ?? false && task.details.colors != nil ? LinearGradient(
//                gradient: Gradient(colors: task.details.colors!.values),
//                startPoint: .leading,
//                endPoint: .trailing
//            ) : nil
//        )
        
    }
}

struct FantasticImage_Previews: PreviewProvider {
    static var previews: some View {
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
            model: FantasticImageModel(task: FantasticTask(type: FantasticTaskTypes.image, state: FantasticTaskStates.stateDone)))
        .frame(width: 256, height: 256)
    }
}
