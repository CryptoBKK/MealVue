//
//  Item.swift
//  Kidney Foods
//
//  Created by Quinn Rieman on 28/4/26.
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
