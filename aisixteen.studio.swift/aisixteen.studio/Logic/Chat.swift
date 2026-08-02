//
//  Chat.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 19.11.2023.
//

import Foundation
enum ChatbotRoles: Int, Decodable {
  case user = 1
  case bot = 2
  case system = 3
}

enum ChatbotMessageStates: Int, Decodable {
  case stateCreated = 100
  case stateProcessing = 200
  case stateErrored = 300
  case stateDone = 400
}

class ChatRecord: Decodable {
  var id: Int!
  var role: ChatbotRoles!
  var content: String!
  var state: ChatbotMessageStates!
  var date: Int!
}

let chatQuestions = [
  "What functions does the app offer?",
  "How do I create an image from a text prompt?",
  "What are the options in the prompt tab?",
  "Can I upscale an image through the app?",
  "Can I get a refund for my purchase?",
  "How do I purchase credits?",
  "How can I get customer support?",
  "What is the delivery policy for the app?",
  "Where can I find the privacy policy?",
  "What is the Create image popup?",
  "How can I access the Create image popup?",
  "What can I do with the Create image popup?",
  "What are the tabs in the Create image popup?",
  "What settings are available in the Details tab of the Create image popup?",
  "How many images can I generate with the Create image popup?",
  "How is the cost of using the Create image popup calculated?",
  "How can I set the dimensions of the image in the Create image popup?",
  "What is the Upscale image popup?",
  "What can be done with the Upscale image popup?",
  "How do I access the Upscale image popup?",
  "What is the Make banners popup?"
]

