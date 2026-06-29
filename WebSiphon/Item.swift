//
//  Item.swift
//  WebSiphon
//
//  Created by Armando Meabe on 22/06/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var sessionID: UUID
    var rootURL: String
    var normalizedRootURL: String
    var host: String
    var status: String
    var destinationFolderPath: String
    var rootLocalRelativePath: String?
    var createdAt: Date
    var completedAt: Date?

    init(
        sessionID: UUID = UUID(),
        rootURL: String,
        normalizedRootURL: String,
        host: String,
        status: String = "Idle",
        destinationFolderPath: String,
        rootLocalRelativePath: String? = nil,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.sessionID = sessionID
        self.rootURL = rootURL
        self.normalizedRootURL = normalizedRootURL
        self.host = host
        self.status = status
        self.destinationFolderPath = destinationFolderPath
        self.rootLocalRelativePath = rootLocalRelativePath
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}
