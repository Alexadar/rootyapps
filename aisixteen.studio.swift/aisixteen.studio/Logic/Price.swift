//
//  Price.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 19.11.2023.
//

import Foundation

struct Prices: Decodable {
  let create: [CreatePrice]
  let upscale: [UpscalePrice]
}

struct CreatePrice: Decodable {
  let price: Double
  let pixels: Int
}

struct UpscalePrice: Decodable {
  let rate: Int
  let price: Double
}

func getTaskPrice(taskType: TaskTypes, task: FantasticTask, currentPrices: Prices) -> Double {
  switch taskType {
  case .image, .imageToImage:
    return currentPrices.create[0].price
  case .upscale:
    return (currentPrices.upscale.first { $0.rate == (task.details.repeatRate ?? 1) }?.price ?? 0)
  }
}

enum TaskTypes {
  case image
  case imageToImage
  case upscale
}

