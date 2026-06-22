//
//  LogEntry.swift
//  WebSiphon
//
//  Created by Armando Meabe on 22/06/2026.
//

import Foundation
import Combine

final class LogEntry: Identifiable, ObservableObject {
    let id: UUID
    var level: Int
    var status: String
    var location: String
    var size: String
    var progress: Double

    init(
        id: UUID = UUID(),
        level: Int,
        status: String,
        location: String,
        size: String,
        progress: Double
    ) {
        self.id = id
        self.level = level
        self.status = status
        self.location = location
        self.size = size
        self.progress = progress
    }
}
