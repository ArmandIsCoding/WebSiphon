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
    var url: String
    var createdAt: Date

    init(url: String, createdAt: Date = Date()) {
        self.url = url
        self.createdAt = createdAt
    }
}
