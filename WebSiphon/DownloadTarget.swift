//
//  DownloadTarget.swift
//  WebSiphon
//
//  Created by Armando Meabe on 22/06/2026.
//

import Foundation
import SwiftData

@Model
final class DownloadTarget {
    var sessionID: UUID
    var url: String
    var normalizedURL: String
    var parentURL: String?
    var depth: Int
    var state: String
    var kind: String
    var httpStatusCode: Int?
    var mimeType: String?
    var byteCount: Int64
    var localRelativePath: String?
    var errorMessage: String?
    var discoveryOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        sessionID: UUID,
        url: String,
        normalizedURL: String,
        parentURL: String? = nil,
        depth: Int = 0,
        state: String = "Discovered",
        kind: String = "Unknown",
        httpStatusCode: Int? = nil,
        mimeType: String? = nil,
        byteCount: Int64 = 0,
        localRelativePath: String? = nil,
        errorMessage: String? = nil,
        discoveryOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.sessionID = sessionID
        self.url = url
        self.normalizedURL = normalizedURL
        self.parentURL = parentURL
        self.depth = depth
        self.state = state
        self.kind = kind
        self.httpStatusCode = httpStatusCode
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.localRelativePath = localRelativePath
        self.errorMessage = errorMessage
        self.discoveryOrder = discoveryOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
