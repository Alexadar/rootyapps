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

  //codes

  enum ServerErrorCodes: Int {
    case none = 0
    case error = 1
    case notEnoughCredit = 2
    case validationError = 3
    case chatbotMessageProcessing = 401
  }

  func extractErrorCode(resp: Error) -> ServerErrorCodes {
    if let resp = resp as? HTTPURLResponse {
      let code = resp.statusCode
      return ServerErrorCodes(rawValue: code) ?? .error
    }
    return .none
  }
}
