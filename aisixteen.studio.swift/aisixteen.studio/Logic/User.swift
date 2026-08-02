//
//  User.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 19.11.2023.
//

import Foundation
class FantasticUser: Decodable {
    var email: String!
    var usageTotal: Int!
    var acceptedEULAat: Int!
    var acceptedGDPRat: Int!
    var credits: Int!
    var disabled: Int!

    enum CodingKeys: String, CodingKey {
        case email
        case usageTotal
        case acceptedEULAat
        case acceptedGDPRat
        case credits
        case disabled
    }
    
    init() {
        
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = try container.decode(String.self, forKey: .email)
        usageTotal = try container.decode(Int.self, forKey: .usageTotal)
        acceptedEULAat = try container.decode(Int.self, forKey: .acceptedEULAat)
        acceptedGDPRat = try container.decode(Int.self, forKey: .acceptedGDPRat)
        credits = try container.decode(Int.self, forKey: .credits)
        disabled = try container.decode(Int.self, forKey: .disabled)
    }
}
