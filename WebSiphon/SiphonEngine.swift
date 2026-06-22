//
//  SiphonEngine.swift
//  WebSiphon
//
//  Created by Armando Meabe on 22/06/2026.
//

import Foundation
import Combine

final class SiphonEngine: ObservableObject {
    @MainActor @Published private(set) var logEntries: [LogEntry] = []

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func startDownload(urlString: String) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.runDownload(urlString: urlString)
        }
    }

    func clearLogs() {
        Task { @MainActor in
            logEntries.removeAll()
        }
    }

    private func runDownload(urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await appendLog(level: 0, status: "Error", location: "Invalid URL: empty input", size: "-", progress: 0)
            return
        }

        guard let rootURL = URL(string: trimmed),
              let scheme = rootURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              rootURL.host != nil else {
            await appendLog(level: 0, status: "Error", location: "Invalid URL: \(trimmed)", size: "-", progress: 0)
            return
        }

        await appendLog(level: 0, status: "Analyzing", location: rootURL.absoluteString, size: "-", progress: 0.05)
        await appendLog(level: 0, status: "Downloading", location: rootURL.absoluteString, size: "-", progress: 0.15)

        do {
            let (data, response) = try await session.data(from: rootURL)
            let expectedSize = (response as? HTTPURLResponse)?.expectedContentLength ?? Int64(data.count)
            let sizeString = Self.humanReadableSize(bytes: expectedSize)
            await appendLog(level: 0, status: "Complete", location: rootURL.absoluteString, size: sizeString, progress: 1.0)

            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                await appendLog(level: 0, status: "Error", location: "Unable to decode HTML for \(rootURL.absoluteString)", size: sizeString, progress: 1.0)
                return
            }

            let discoveredLinks = Self.extractSameHostLinks(from: html, baseURL: rootURL)
            for link in discoveredLinks {
                await appendLog(level: 1, status: "Queued", location: link.absoluteString, size: "-", progress: 0.0)
            }
        } catch {
            await appendLog(level: 0, status: "Error", location: "\(rootURL.absoluteString) - \(error.localizedDescription)", size: "-", progress: 0)
        }
    }

    private func appendLog(level: Int, status: String, location: String, size: String, progress: Double) async {
        await MainActor.run {
            logEntries.insert(
                LogEntry(
                    level: level,
                    status: status,
                    location: location,
                    size: size,
                    progress: progress
                ),
                at: 0
            )
        }
    }

    private static func extractSameHostLinks(from html: String, baseURL: URL) -> [URL] {
        // Capture href/src values from anchor and image tags.
        let pattern = #"<(?:a\b[^>]*\bhref|img\b[^>]*\bsrc)\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: nsRange)
        let targetHost = baseURL.host?.lowercased()

        var results: [URL] = []
        var seen = Set<String>()

        for match in matches {
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: html) else {
                continue
            }

            let raw = String(html[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, !raw.hasPrefix("#") else {
                continue
            }

            guard let resolved = URL(string: raw, relativeTo: baseURL)?.absoluteURL,
                  resolved.host?.lowercased() == targetHost else {
                continue
            }

            if seen.insert(resolved.absoluteString).inserted {
                results.append(resolved)
            }
        }

        return results
    }

    private static func humanReadableSize(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(bytes, 0))
    }
}
