//
//  Api.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 19.11.2023.
//

import Foundation
import SocketIO

class Api {
  static let shared = Api()  // Singleton instance

  let manager = SocketManager(
    socketURL: URL(string: "Your_SocketIO_URL")!, config: [.log(true), .compress])
//  #if DEBUG
//    let api_base_url = "http://localhost:8000/api/fantastic/"
//  #else
      let api_base_url = "https://api.aisixteen.com/api/fantastic/"
//  #endif
  let createURL = { (methodName: String) -> URL in
    return URL(string: "\(Api.shared.api_base_url)\(methodName)")!
  }
  var socket: SocketIOClient!

  public init() {

  }

  //api

  func shouldLogIn() -> Bool {
    if let authCookie = HTTPCookieStorage.shared.cookies?.first(where: { $0.name == "auth" }) {
      return authCookie.expiresDate ?? Date() > Date()
    } else {
      return false
    }
  }
  
  // Perform HTTP request
  func performRequest(
    url: String, method: String = "GET", body: [String: Any]? = nil, setCookies: Bool = false
  ) async throws -> (Data, URLResponse?) {
    print("performRequest")
    var request = URLRequest(url: createURL(url))
    request.httpMethod = method

    if let body = body {
      request.addValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    }

    print("requesting from \(request.url!)")
    let (data, response) = try await URLSession.shared.data(for: request)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    print("got response from \(request.url!), code is \(code)")
    if code != 200 {
      throw NSError(domain: "HTTPError", code: code, userInfo: nil)
    }
    if setCookies, let httpResponse = response as? HTTPURLResponse {
      let cookies = HTTPCookie.cookies(
        withResponseHeaderFields: httpResponse.allHeaderFields as! [String: String],
        for: httpResponse.url!)
      HTTPCookieStorage.shared.setCookies(cookies, for: httpResponse.url!, mainDocumentURL: nil)
    }

    return (data, response)
  }

  // auth
    
  func authenticateWithFirebase(token: String) async throws -> (Data, URLResponse?) {
      print("authenticateWithFirebase")
      return try await performRequest(
      url: "firebase_auth", method: "POST", body: ["token": token], setCookies: true) 
  }

  func logout() async throws -> (Data, URLResponse?) {
      return try await performRequest(url: "logout", method: "POST", setCookies: true)
  }
    
  // tasks
    
  public class GetTaskResponse: Decodable {
      var tasks: [FantasticTask] = []
      var totalCount: Int = 0
  }
    
  func getTasks(page: Int = 1, pageSize: Int = 10) async throws -> GetTaskResponse {
      
    let body: [String: Any] = ["paging": ["page": page, "pageSize": pageSize], "where": [:]]
    let (data, response) = try await performRequest(url: "tasks", method: "POST", body: body, setCookies: true)
    let dataAsString = String(data: data, encoding: .utf8)!
    let decoder = JSONDecoder()
      do {
          let decodedData = try decoder.decode(GetTaskResponse.self, from: data)
          return decodedData
      }
      catch let decodingError as DecodingError {
        print(decodingError)
        throw decodingError
      }
      catch {
          throw error
      }
  }

  //ws

  func connect_ws() {
    socket = manager.defaultSocket

    socket.on(clientEvent: .connect) { data, ack in
      print("socket connected")
    }

    socket.connect()
  }

  func onEvent(evtname: String, cb: @escaping (Any) -> Void) -> () -> Void {
    socket.on(evtname) { payload, arg in
      cb(payload)
    }
    let unsub = { [self] in
      socket.removeAllHandlers()
    }
    return unsub
  }

  // User methods
  func getMe() async throws -> FantasticUser {
    let (data, _) = try await performRequest(url: "me", method: "GET")
    let decoder = JSONDecoder()
    return try decoder.decode(FantasticUser.self, from: data)
  }
  
  // Task operations
  func postDiffuseTask(_ task: FantasticTask, quantity: Int) async throws {
    let body: [String: Any] = [
      "task": [
        "type": task.type.rawValue,
        "aiArtist": task.aiArtist.rawValue,
        "details": [
          "prompt": task.details.prompt,
          "neg_prompt": task.details.neg_prompt,
          "w": task.details.w,
          "h": task.details.h,
          "cfg": task.details.cfg,
          "steps": task.details.steps,
          "baseimage": task.details.baseimage
        ]
      ],
      "quantity": quantity
    ]
    let _ = try await performRequest(url: "diffuse", method: "POST", body: body)
  }
  
  func postRepaintTask(_ task: FantasticTask, quantity: Int) async throws {
    let body: [String: Any] = [
      "task": [
        "type": task.type.rawValue,
        "aiArtist": task.aiArtist.rawValue,
        "details": [
          "prompt": task.details.prompt,
          "neg_prompt": task.details.neg_prompt,
          "w": task.details.w,
          "h": task.details.h,
          "cfg": task.details.cfg,
          "steps": task.details.steps,
          "baseimage": task.details.resultUrl
        ]
      ],
      "quantity": quantity
    ]
    let _ = try await performRequest(url: "repaint", method: "POST", body: body)
  }
  
  func postUpscaleTask(_ task: FantasticTask) async throws {
    let body: [String: Any] = [
      "task": [
        "type": "upscale",
        "details": [
          "baseimage": task.details.resultUrl
        ]
      ]
    ]
    let _ = try await performRequest(url: "upscale", method: "POST", body: body)
  }
  
  func deleteTasks(_ taskIds: [Int]) async throws {
    let body: [String: Any] = ["taskIds": taskIds]
    let _ = try await performRequest(url: "tasks/delete", method: "POST", body: body)
  }
  
  func getTasksByIds(_ taskIds: [Int]) async throws -> GetTaskResponse {
    let body: [String: Any] = ["taskIds": taskIds]
    let (data, _) = try await performRequest(url: "tasks/by_ids", method: "POST", body: body)
    let decoder = JSONDecoder()
    return try decoder.decode(GetTaskResponse.self, from: data)
  }
  
  // Packs and pricing
  public class GetPacksResponse: Decodable {
    var packs: [CreditsPack] = []
    var prices: Prices = Prices()
  }
  
  func getPacks() async throws -> GetPacksResponse {
    let (data, _) = try await performRequest(url: "packs", method: "GET")
    let decoder = JSONDecoder()
    return try decoder.decode(GetPacksResponse.self, from: data)
  }
  
  func getCheckoutUrl(_ packId: Int) async throws -> String {
    let body: [String: Any] = ["packId": packId]
    let (data, _) = try await performRequest(url: "checkout", method: "POST", body: body)
    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
       let url = json["checkoutUrl"] as? String {
      return url
    }
    throw NSError(domain: "APIError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid checkout response"])
  }
  
  func getLatestPurchase() async throws -> [String: Any] {
    let (data, _) = try await performRequest(url: "purchase/latest", method: "GET")
    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
      return json
    }
    throw NSError(domain: "APIError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid purchase response"])
  }
  
  // Chat methods
  func getChatMessages() async throws -> [ChatRecord] {
    let (data, _) = try await performRequest(url: "chat/messages", method: "GET")
    let decoder = JSONDecoder()
    return try decoder.decode([ChatRecord].self, from: data)
  }
  
  func sendChatMessage(_ message: String) async throws -> [ChatRecord] {
    let body: [String: Any] = ["message": message]
    let (data, _) = try await performRequest(url: "chat/send", method: "POST", body: body)
    let decoder = JSONDecoder()
    return try decoder.decode([ChatRecord].self, from: data)
  }
  
  // Document methods
  func getDoc(_ docName: String) async throws -> String {
    let (data, _) = try await performRequest(url: "docs/\(docName)", method: "GET")
    return String(data: data, encoding: .utf8) ?? ""
  }
  
  func acceptEULA() async throws {
    let _ = try await performRequest(url: "accept/eula", method: "POST")
  }
  
  func acceptGDPR() async throws {
    let _ = try await performRequest(url: "accept/gdpr", method: "POST")
  }

  //codes

  enum ServerErrorCodes: Int {
    case none = 0
    case error = 1
    case notEnoughCredit = 2
    case validationError = 3
    case chatbotMessageProcessing = 401
    case promptContainsProfanity = 402
  }

  func extractErrorCode(resp: Error) -> ServerErrorCodes {
    if let resp = resp as? HTTPURLResponse {
      let code = resp.statusCode
      return ServerErrorCodes(rawValue: code) ?? .error
    }
    return .none
  }
}
