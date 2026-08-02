//
//  FantasticTask.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 19.11.2023.
//

import Foundation
import SwiftUI

enum FantasticTaskStates: Int, Decodable {
    case stateCreated = 100
    case stateQueued = 101
    case statePickedUp = 200
    case stateCanceled = 300
    case stateCanceledTimeout = 301
    case stateCanceledError = 302
    case stateCanceledStartup = 303
    case stateCanceledNFSW = 304
    case stateCanceledCannotDownloadImage = 305
    case stateCanceledCannotProcessImageExternalApi = 306
    case stateDone = 400
    case stateDoneFileDownloaded = 401
    case stateDeleted = 500
    case stateDeletedCleanedUp = 501
    case stateDeletedNonExistent = 502
}

enum FantasticTaskTypes: Int, Decodable  {
    case image = 101
    case imageToImage = 102
    case upscale = 103
}

enum AiArtist: Int, Decodable  {
    case general = 1
}

struct FantasticTaskDefaults {
    static let w: Int = 512
    static let h: Int = 512
    static let strength: Double = 0.62
    static let cfg: Double = 7.5
    static let steps: Int = 20
    static let eta: Int = 0
}

struct Colors: Decodable {
    // decoded from values like this:
    // [[[211, 192, 162], 1348], [[212, 193, 163], 1321], [[211, 193, 163], 1298]]
    var values: [Color]
    
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Color] = []
        while !container.isAtEnd {
            let color = try container.decode([Int].self)
            values.append(Color(red: Double(color[0]) / 255, green: Double(color[1]) / 255, blue: Double(color[2]) / 255))
        }
        self.values = values
    }
}

struct FantasticTaskDetails: Decodable {
    var prompt: String?
    var neg_prompt: String?
    var baseimage: String?
    var base_image_url: String?
    var strength: Double?
    var w: Int?
    var h: Int?
    var cfg: Double?
    var steps: Int?
    var eta: Int?
    var repeatRate: Int?
    var position_h: Int?
//    var colors: Colors?
}

class FantasticTask: Decodable, Identifiable {
    var id: Int
    var collectionId: Int?
    var state: FantasticTaskStates
    var type: FantasticTaskTypes
//    var aiArtist: AiArtist
    var parentFantasticTaskId: Int?
//    var createDate: Date
//    var updateDate: Date
    var details: FantasticTaskDetails
    
    init(id: Int = -1, type: FantasticTaskTypes = .image, state: FantasticTaskStates = .stateCreated) {
        self.id = id
        self.state = state
        self.type = type
//        self.aiArtist = .general
//        self.createDate = Date()
//        self.updateDate = Date()
        self.details = FantasticTaskDetails()
    }
}

func canDownload(FantasticTask: FantasticTask) -> Bool {
    return [FantasticTaskStates.stateDone].contains(FantasticTask.state)
}

func canDelete(FantasticTask: FantasticTask) -> Bool {
    return ![FantasticTaskStates.statePickedUp].contains(FantasticTask.state)
}

func canUpscale(FantasticTask: FantasticTask) -> Bool {
    return FantasticTask.id != 0 &&
        FantasticTask.state == .stateDone &&
        (FantasticTask.type == .image || FantasticTask.type == .imageToImage)
}

func canCreateSimilar(FantasticTask: FantasticTask) -> Bool {
    return FantasticTask.id != 0 &&
        [FantasticTaskTypes.image, FantasticTaskTypes.imageToImage].contains(FantasticTask.type) &&
        FantasticTask.state == .stateDone
}

func createDummyParent(FantasticTask: FantasticTask) -> FantasticTask {
    let dummyFantasticTask = FantasticTask
    dummyFantasticTask.id = 0
    dummyFantasticTask.state = .stateDone
    return dummyFantasticTask
}

func FantasticTaskToFantasticTaskType(FantasticTask: FantasticTask) -> String {
    switch FantasticTask.type {
    case .image:
        return "Text to image"
    case .imageToImage:
        return "Similar image"
    case .upscale:
        return "Upscaled image \(Int(pow(2, Double(FantasticTask.details.repeatRate ?? 1) * 2)))X"
    }
}

func maxViewport(FantasticTask: FantasticTask) -> Int {
    switch FantasticTask.type {
    case .image, .imageToImage:
        return 512
    case .upscale:
        return 2048 * (FantasticTask.details.repeatRate ?? 1)
    }
}
