//
//  Item.swift
//  Exorcise Anything
//
//  Created by yowenomo on 9/29/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
