//
//  Item.swift
//  DrySpell
//
//  Created by Justin Chapdelaine on 2026-04-17.
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
