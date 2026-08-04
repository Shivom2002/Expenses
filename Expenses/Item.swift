//
//  Item.swift
//  Expenses
//
//  Created by Shivom Dhamija on 8/3/26.
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
