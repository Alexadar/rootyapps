//
//  CreditPack.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 19.11.2023.
//

import Foundation
struct CreditsPack: Decodable {
    let id: Int
    let label: String
    let amount: Int
    let cost: Int
    let order: Int
    let highlight: Bool
}
