//
//  SiphonEngine.swift
//  WebSiphon
//
//  Created by Armando Meabe on 22/06/2026.
//

import Foundation
import AppKit

actor SiphonEngine {
    struct Reference: Hashable {
        let rawValue: String
        let resolvedURL: URL
    }

    nonisolated func normalizeSeedURL(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed) else {
            return nil
        }
        return normalizedURL(for: url)
    }

    nonisolated func normalizedURL(for url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return nil
        }

        guard var components = URLComponents(url: url.absoluteURL, resolvingAgainstBaseURL: true) else {
            return nil
        }

        components.scheme = scheme
        components.host = components.host?.lowercased()
        components.fragment = nil

        if let port = components.port,
           (scheme == "http" && port == 80) || (scheme == "https" && port == 443) {
            components.port = nil
        }

        return components.url
    }

    nonisolated func isSameHost(_ lhs: URL, _ rhs: URL) -> Bool {
        cleanHost(lhs.host) == cleanHost(rhs.host)
    }

    nonisolated func shouldCrawl(_ url: URL, fromRoot rootURL: URL, depth: Int, maxDepth: Int) -> Bool {
        guard depth <= maxDepth else { return false }
        guard isSameHost(url, rootURL) else { return false }
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return false }
        return true
    }

    nonisolated func decodeHTML(from data: Data) -> String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(data: data, encoding: .windowsCP1252)
    }

    nonisolated func kind(for url: URL, mimeType: String?) -> String {
        let mime = mimeType?.lowercased() ?? ""
        if mime.contains("html") { return "HTML" }
        if mime.contains("css") { return "CSS" }
        if mime.contains("javascript") || mime.contains("ecmascript") { return "JS" }
        if mime.contains("image") { return "Image" }
        if mime.contains("font") { return "Font" }
        if mime.contains("json") { return "JSON" }
        if !url.pathExtension.isEmpty { return url.pathExtension.uppercased() }
        return "File"
    }

    nonisolated func extractReferences(from html: String, baseURL: URL, rootURL: URL) -> [URL] {
        var discovered: [URL] = []
        var seen = Set<String>()

        let attributePattern = #"(?:href|src)\s*=\s*["']([^"']+)["']"#
        collectReferences(matching: attributePattern, in: html, baseURL: baseURL, rootURL: rootURL, seen: &seen, into: &discovered)

        let srcsetPattern = #"srcset\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: srcsetPattern, options: [.caseInsensitive]) else {
            return discovered
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let valueRange = Range(match.range(at: 1), in: html) else { continue }
            let srcset = String(html[valueRange])
            for candidate in srcset.split(separator: ",") {
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let token = trimmed.split(separator: " ").first else { continue }
                if let normalized = normalizedDiscoveredURL(String(token), baseURL: baseURL, rootURL: rootURL),
                   seen.insert(normalized.absoluteString).inserted {
                    discovered.append(normalized)
                }
            }
        }

        return discovered
    }

    nonisolated func localRelativePath(for url: URL, mimeType: String?, siteFolderName: String) -> String {
        let sanitizedPath = sanitizedPathComponents(for: url)
        let querySuffix = hashedQuerySuffix(for: url)
        let finalComponent = sanitizedPath.last ?? ""
        let hasPathExtension = !URL(fileURLWithPath: finalComponent).pathExtension.isEmpty
        let isHTML = (mimeType?.lowercased().contains("html") ?? false)

        var components = [siteFolderName]
        if sanitizedPath.isEmpty {
            components.append("index.html")
            return components.joined(separator: "/")
        }

        if hasPathExtension {
            let fileURL = URL(fileURLWithPath: finalComponent)
            let baseName = fileURL.deletingPathExtension().lastPathComponent + querySuffix
            let filename = baseName + "." + fileURL.pathExtension
            components.append(contentsOf: sanitizedPath.dropLast())
            components.append(filename)
            return components.joined(separator: "/")
        }

        if isHTML || url.pathExtension.isEmpty {
            components.append(contentsOf: sanitizedPath)
            components.append("index\(querySuffix).html")
            return components.joined(separator: "/")
        }

        components.append(contentsOf: sanitizedPath.dropLast())
        components.append(finalComponent + querySuffix)
        return components.joined(separator: "/")
    }

    nonisolated func rewriteHTML(
        _ html: String,
        pageURL: URL,
        pageLocalRelativePath: String,
        localPathsByRemoteURL: [String: String],
        rootURL: URL
    ) -> String {
        var output = html

        let attributePattern = #"((?:href|src)\s*=\s*["'])([^"']+)(["'])"#
        output = replaceAttributeMatches(
            in: output,
            pattern: attributePattern,
            pageURL: pageURL,
            pageLocalRelativePath: pageLocalRelativePath,
            localPathsByRemoteURL: localPathsByRemoteURL,
            rootURL: rootURL
        )

        let srcsetPattern = #"(srcset\s*=\s*["'])([^"']+)(["'])"#
        output = replaceSrcsetMatches(
            in: output,
            pattern: srcsetPattern,
            pageURL: pageURL,
            pageLocalRelativePath: pageLocalRelativePath,
            localPathsByRemoteURL: localPathsByRemoteURL,
            rootURL: rootURL
        )

        return output
    }

    nonisolated func humanReadableSize(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(bytes, 0))
    }

    nonisolated func siteFolderName(for url: URL) -> String {
        let host = cleanHost(url.host)
        let hostWithoutWWW = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitized = hostWithoutWWW.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }.joined()
        return sanitized.isEmpty ? "site" : sanitized
    }

    nonisolated private func collectReferences(
        matching pattern: String,
        in html: String,
        baseURL: URL,
        rootURL: URL,
        seen: inout Set<String>,
        into output: inout [URL]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let valueRange = Range(match.range(at: 1), in: html) else { continue }
            let rawValue = String(html[valueRange])
            if let normalized = normalizedDiscoveredURL(rawValue, baseURL: baseURL, rootURL: rootURL),
               seen.insert(normalized.absoluteString).inserted {
                output.append(normalized)
            }
        }
    }

    nonisolated private func normalizedDiscoveredURL(_ rawValue: String, baseURL: URL, rootURL: URL) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        guard !lowered.hasPrefix("#"),
              !lowered.hasPrefix("mailto:"),
              !lowered.hasPrefix("tel:"),
              !lowered.hasPrefix("javascript:"),
              !lowered.hasPrefix("data:") else {
            return nil
        }

        guard let resolved = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL,
              let normalized = normalizedURL(for: resolved),
              isSameHost(normalized, rootURL) else {
            return nil
        }

        return normalized
    }

    nonisolated private func replaceAttributeMatches(
        in html: String,
        pattern: String,
        pageURL: URL,
        pageLocalRelativePath: String,
        localPathsByRemoteURL: [String: String],
        rootURL: URL
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return html
        }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html))
        var result = html

        for match in matches.reversed() {
            guard let prefixRange = Range(match.range(at: 1), in: result),
                  let valueRange = Range(match.range(at: 2), in: result),
                  let suffixRange = Range(match.range(at: 3), in: result) else {
                continue
            }

            let rawValue = String(result[valueRange])
            guard let replacement = rewrittenValue(
                for: rawValue,
                pageURL: pageURL,
                pageLocalRelativePath: pageLocalRelativePath,
                localPathsByRemoteURL: localPathsByRemoteURL,
                rootURL: rootURL
            ) else {
                continue
            }

            let fullRange = prefixRange.lowerBound..<suffixRange.upperBound
            let originalPrefix = String(result[prefixRange])
            let originalSuffix = String(result[suffixRange])
            result.replaceSubrange(fullRange, with: originalPrefix + replacement + originalSuffix)
        }

        return result
    }

    nonisolated private func replaceSrcsetMatches(
        in html: String,
        pattern: String,
        pageURL: URL,
        pageLocalRelativePath: String,
        localPathsByRemoteURL: [String: String],
        rootURL: URL
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return html
        }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html))
        var result = html

        for match in matches.reversed() {
            guard let prefixRange = Range(match.range(at: 1), in: result),
                  let valueRange = Range(match.range(at: 2), in: result),
                  let suffixRange = Range(match.range(at: 3), in: result) else {
                continue
            }

            let srcsetValue = String(result[valueRange])
            let rewritten = srcsetValue
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { item -> String in
                    let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let token = trimmed.split(separator: " ").first else { return trimmed }
                    let descriptor = trimmed.dropFirst(token.count)
                    let replaced = rewrittenValue(
                        for: String(token),
                        pageURL: pageURL,
                        pageLocalRelativePath: pageLocalRelativePath,
                        localPathsByRemoteURL: localPathsByRemoteURL,
                        rootURL: rootURL
                    ) ?? String(token)
                    return replaced + descriptor
                }
                .joined(separator: ", ")

            let fullRange = prefixRange.lowerBound..<suffixRange.upperBound
            let originalPrefix = String(result[prefixRange])
            let originalSuffix = String(result[suffixRange])
            result.replaceSubrange(fullRange, with: originalPrefix + rewritten + originalSuffix)
        }

        return result
    }

    nonisolated private func rewrittenValue(
        for rawValue: String,
        pageURL: URL,
        pageLocalRelativePath: String,
        localPathsByRemoteURL: [String: String],
        rootURL: URL
    ) -> String? {
        guard let resolved = URL(string: rawValue, relativeTo: pageURL)?.absoluteURL,
              let normalized = normalizedURL(for: resolved),
              isSameHost(normalized, rootURL),
              let targetLocalPath = localPathsByRemoteURL[normalized.absoluteString] else {
            return nil
        }

        let fragment = URLComponents(string: rawValue)?.fragment.map { "#\($0)" } ?? ""
        return relativePath(from: pageLocalRelativePath, to: targetLocalPath) + fragment
    }

    nonisolated private func relativePath(from currentFile: String, to destinationFile: String) -> String {
        let currentDirectory = currentFile.split(separator: "/").dropLast().map(String.init)
        let destination = destinationFile.split(separator: "/").map(String.init)

        var commonIndex = 0
        while commonIndex < currentDirectory.count,
              commonIndex < destination.count,
              currentDirectory[commonIndex] == destination[commonIndex] {
            commonIndex += 1
        }

        let upward = Array(repeating: "..", count: currentDirectory.count - commonIndex)
        let downward = Array(destination.dropFirst(commonIndex))
        let combined = upward + downward
        return combined.isEmpty ? "index.html" : combined.joined(separator: "/")
    }

    nonisolated private func sanitizedPathComponents(for url: URL) -> [String] {
        url.pathComponents
            .filter { $0 != "/" && !$0.isEmpty }
            .map { component in
                let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
                let sanitized = component.unicodeScalars.map { scalar in
                    allowed.contains(scalar) ? String(scalar) : "-"
                }.joined()
                return sanitized.isEmpty ? "file" : sanitized
            }
    }

    nonisolated private func hashedQuerySuffix(for url: URL) -> String {
        guard let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery,
              !query.isEmpty else {
            return ""
        }

        var hash: UInt64 = 1469598103934665603
        for byte in query.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }

        return "__q\(String(hash, radix: 16))"
    }

    nonisolated private func cleanHost(_ host: String?) -> String {
        (host ?? "").lowercased()
    }
}
