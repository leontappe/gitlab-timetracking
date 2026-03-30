//
//  Item.swift
//  My GitLab Timetracking
//
//  Created by Leon Tappe on 30.03.26.
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
