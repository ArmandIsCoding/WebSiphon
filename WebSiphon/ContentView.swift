//
//  ContentView.swift
//  WebSiphon
//
//  Created by Armando Meabe on 22/06/2026.
//

import SwiftUI
import SwiftData
import AppKit

@MainActor
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.createdAt, order: .reverse) private var sessions: [Item]
    @Query(sort: \DownloadTarget.discoveryOrder) private var allTargets: [DownloadTarget]

    @State private var targetURL = ""
    @State private var logLines: [String] = ["[system] WebSiphon listo."]
    @State private var currentTask: Task<Void, Never>?
    @State private var isShowingSettings = false
    @State private var activeSessionID: UUID?

    @AppStorage("downloadBasePath") private var downloadBasePath = defaultDesktopPath
    @AppStorage("downloadBaseBookmark") private var downloadBaseBookmark = Data()

    private let engine = SiphonEngine()
    private let maxDepth = 5

    private static var defaultDesktopPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .path
    }

    private var currentSession: Item? {
        if let activeSessionID,
           let match = sessions.first(where: { $0.sessionID == activeSessionID }) {
            return match
        }
        return sessions.first
    }

    private var sessionTargets: [DownloadTarget] {
        guard let sessionID = currentSession?.sessionID else { return [] }
        return allTargets
            .filter { $0.sessionID == sessionID }
            .sorted { lhs, rhs in
                if lhs.discoveryOrder == rhs.discoveryOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.discoveryOrder < rhs.discoveryOrder
            }
    }

    private var isRunning: Bool {
        currentTask != nil || currentSession?.status == "Running"
    }

    private var discoveredCount: Int { sessionTargets.count }
    private var downloadedCount: Int { sessionTargets.filter { $0.state == "Downloaded" }.count }
    private var failedCount: Int { sessionTargets.filter { $0.state == "Failed" }.count }
    private var pendingCount: Int {
        sessionTargets.filter { ["Discovered", "Queued", "Analyzing", "Downloading"].contains($0.state) }.count
    }
    private var deepestLevel: Int { sessionTargets.map(\.depth).max() ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            headerPanel
                .padding()

            Divider()

            listPanel
                .frame(maxHeight: .infinity)

            Divider()

            logArea
                .frame(minHeight: 170, maxHeight: 220)
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .sheet(isPresented: $isShowingSettings) {
            settingsView
        }
        .frame(minWidth: 1040, minHeight: 680)
        .onAppear {
            activeSessionID = currentSession?.sessionID
        }
    }

    private var headerPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField("https://example.com", text: $targetURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isRunning)

                Button("Siphon", action: startSiphon)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRunning)

                Button("Stop", role: .destructive, action: stopCurrentSession)
                    .disabled(!isRunning)
            }

            if let session = currentSession {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(session.rootURL)
                            .font(.headline)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(session.status)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(statusColor(for: session.status))
                    }

                    HStack(spacing: 10) {
                        statCard(title: "Descubiertas", value: "\(discoveredCount)", color: .blue)
                        statCard(title: "Descargadas", value: "\(downloadedCount)", color: .green)
                        statCard(title: "Pendientes", value: "\(pendingCount)", color: .orange)
                        statCard(title: "Errores", value: "\(failedCount)", color: .red)
                        statCard(title: "Nivel", value: "\(deepestLevel)", color: .purple)
                    }

                    HStack(spacing: 12) {
                        Label(session.destinationFolderPath, systemImage: "folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if session.rootLocalRelativePath != nil {
                            Button("Abrir offline") {
                                openOfflineRoot(for: session)
                            }
                        }
                    }
                }
            } else {
                Text("Ingresa un sitio raíz y WebSiphon descubrirá y descargará sus URLs una por una.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var listPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Estado").frame(width: 100, alignment: .leading)
                Text("Nivel").frame(width: 50, alignment: .leading)
                Text("Tipo").frame(width: 70, alignment: .leading)
                Text("URL / Ruta").frame(maxWidth: .infinity, alignment: .leading)
                Text("Peso").frame(width: 90, alignment: .trailing)
                Text("HTTP").frame(width: 60, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.35))

            List(sessionTargets) { target in
                URLRowView(target: target)
            }
            .listStyle(.plain)
        }
    }

    private var bottomBar: some View {
        HStack {
            Button("Clear", role: .destructive) {
                clearAllState()
            }
            .disabled(currentSession == nil && logLines.count <= 1)

            Spacer()

            Button("Settings") {
                isShowingSettings = true
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func startSiphon() {
        guard !isRunning else {
            appendLog("Ya hay un sitio procesandose. Detenlo antes de iniciar otro.")
            return
        }

        guard let rootURL = engine.normalizeSeedURL(targetURL) else {
            appendLog("Entrada invalida: ingresa una URL http(s) valida.")
            return
        }

        var baseFolderURL = resolvedBaseFolderURL()
        if !ensureWritableBaseFolder(baseFolderURL) {
            appendLog("Sin permiso de escritura en: \(baseFolderURL.path)")
            guard requestFolderAuthorization(startingAt: baseFolderURL) else {
                appendLog("Descarga cancelada: no se concedio acceso a carpeta de destino.")
                return
            }
            baseFolderURL = resolvedBaseFolderURL()
            guard ensureWritableBaseFolder(baseFolderURL) else {
                appendLog("La carpeta seleccionada sigue sin permisos de escritura.")
                return
            }
        }

        clearAllState(preserveLogs: false)

        let newSession = Item(
            rootURL: rootURL.absoluteString,
            normalizedRootURL: rootURL.absoluteString,
            host: rootURL.host ?? "",
            status: "Running",
            destinationFolderPath: baseFolderURL.path
        )
        modelContext.insert(newSession)
        activeSessionID = newSession.sessionID
        targetURL = ""
        appendLog("Analizando y descargando sitio raiz: \(rootURL.absoluteString)")

        let siteFolderName = engine.siteFolderName(for: rootURL)
        let scopeStarted = baseFolderURL.startAccessingSecurityScopedResource()
        let context = CrawlRunContext(rootURL: rootURL, baseFolderURL: baseFolderURL, siteFolderName: siteFolderName, maxDepth: maxDepth)

        currentTask = Task {
            defer {
                if scopeStarted {
                    baseFolderURL.stopAccessingSecurityScopedResource()
                }
                currentTask = nil
            }

            do {
                try await crawl(url: rootURL, parentURL: nil, depth: 0, session: newSession, context: context)

                if Task.isCancelled {
                    finalizeSession(newSession, status: "Cancelled", rootLocalRelativePath: context.localPaths[rootURL.absoluteString])
                    appendLog("Sesion detenida.")
                } else {
                    finalizeSession(newSession, status: "Completed", rootLocalRelativePath: context.localPaths[rootURL.absoluteString])
                    appendLog("Sitio descargado para navegacion offline.")
                }
            } catch is CancellationError {
                finalizeSession(newSession, status: "Cancelled", rootLocalRelativePath: context.localPaths[rootURL.absoluteString])
                appendLog("Sesion detenida.")
            } catch {
                finalizeSession(newSession, status: "Failed", rootLocalRelativePath: context.localPaths[rootURL.absoluteString])
                appendLog("Error fatal en la sesion: \(error.localizedDescription)")
            }
        }
    }

    private func crawl(url: URL, parentURL: String?, depth: Int, session: Item, context: CrawlRunContext) async throws {
        try Task.checkCancellation()
        guard let normalizedURL = engine.normalizedURL(for: url) else { return }
        guard engine.shouldCrawl(normalizedURL, fromRoot: context.rootURL, depth: depth, maxDepth: context.maxDepth) else { return }

        let normalizedString = normalizedURL.absoluteString
        if context.visitedURLs.contains(normalizedString) {
            return
        }

        let target = upsertTarget(
            sessionID: session.sessionID,
            normalizedURL: normalizedString,
            parentURL: parentURL,
            depth: depth,
            discoveryOrder: context.nextDiscoveryOrderIfNeeded(for: normalizedString)
        )
        context.knownURLs.insert(normalizedString)
        context.visitedURLs.insert(normalizedString)

        target.state = "Downloading"
        target.errorMessage = nil
        target.updatedAt = Date()
        appendLog("[L\(depth)] Descargando: \(normalizedString)")

        do {
            let (data, response) = try await URLSession.shared.data(from: normalizedURL)
            try Task.checkCancellation()

            let httpResponse = response as? HTTPURLResponse
            let mimeType = httpResponse?.mimeType
            let localPath = engine.localRelativePath(for: normalizedURL, mimeType: mimeType, siteFolderName: context.siteFolderName)
            let isHTML = isHTMLResource(url: normalizedURL, mimeType: mimeType)

            context.localPaths[normalizedString] = localPath
            target.mimeType = mimeType
            target.httpStatusCode = httpResponse?.statusCode
            target.byteCount = Int64(data.count)
            target.kind = engine.kind(for: normalizedURL, mimeType: mimeType)
            target.localRelativePath = localPath
            target.updatedAt = Date()

            if isHTML, let html = engine.decodeHTML(from: data) {
                target.state = "Analyzing"
                let references = engine.extractReferences(from: html, baseURL: normalizedURL, rootURL: context.rootURL)
                let crawlableReferences = references.filter {
                    engine.shouldCrawl($0, fromRoot: context.rootURL, depth: depth + 1, maxDepth: context.maxDepth)
                }

                for childURL in crawlableReferences {
                    let childKey = childURL.absoluteString
                    if !context.knownURLs.contains(childKey) {
                        context.knownURLs.insert(childKey)
                        _ = upsertTarget(
                            sessionID: session.sessionID,
                            normalizedURL: childKey,
                            parentURL: normalizedString,
                            depth: depth + 1,
                            discoveryOrder: context.nextDiscoveryOrderIfNeeded(for: childKey)
                        )
                        appendLog("[L\(depth + 1)] Descubierta: \(childKey)")
                    }
                }

                for childURL in crawlableReferences {
                    try Task.checkCancellation()
                    try await crawl(
                        url: childURL,
                        parentURL: normalizedString,
                        depth: depth + 1,
                        session: session,
                        context: context
                    )
                }

                let rewrittenHTML = engine.rewriteHTML(
                    html,
                    pageURL: normalizedURL,
                    pageLocalRelativePath: localPath,
                    localPathsByRemoteURL: context.localPaths,
                    rootURL: context.rootURL
                )
                try saveFile(data: Data(rewrittenHTML.utf8), relativePath: localPath, baseFolderURL: context.baseFolderURL)
            } else {
                try saveFile(data: data, relativePath: localPath, baseFolderURL: context.baseFolderURL)
            }

            target.state = "Downloaded"
            target.updatedAt = Date()
            if depth == 0 {
                session.rootLocalRelativePath = localPath
            }
            appendLog("Guardado: \(localPath) · \(engine.humanReadableSize(bytes: Int64(data.count)))")
        } catch is CancellationError {
            target.state = "Stopped"
            target.updatedAt = Date()
            throw CancellationError()
        } catch {
            target.state = "Failed"
            target.errorMessage = error.localizedDescription
            target.updatedAt = Date()
            appendLog("Error en \(normalizedString): \(error.localizedDescription)")
        }
    }

    private func upsertTarget(
        sessionID: UUID,
        normalizedURL: String,
        parentURL: String?,
        depth: Int,
        discoveryOrder: Int
    ) -> DownloadTarget {
        if let existing = sessionTargets.first(where: { $0.normalizedURL == normalizedURL }) {
            if existing.parentURL == nil {
                existing.parentURL = parentURL
            }
            if existing.depth > depth {
                existing.depth = depth
            }
            existing.updatedAt = Date()
            return existing
        }

        let target = DownloadTarget(
            sessionID: sessionID,
            url: normalizedURL,
            normalizedURL: normalizedURL,
            parentURL: parentURL,
            depth: depth,
            state: depth == 0 ? "Queued" : "Discovered",
            kind: "Unknown",
            discoveryOrder: discoveryOrder
        )
        modelContext.insert(target)
        return target
    }

    private func finalizeSession(_ session: Item, status: String, rootLocalRelativePath: String?) {
        session.status = status
        session.completedAt = Date()
        if let rootLocalRelativePath {
            session.rootLocalRelativePath = rootLocalRelativePath
        }
    }

    private func stopCurrentSession() {
        guard isRunning else { return }
        currentSession?.status = "Stopping"
        currentTask?.cancel()
        appendLog("Solicitando detencion...")
    }

    private func clearAllState(preserveLogs: Bool = false) {
        currentTask?.cancel()
        currentTask = nil

        for target in allTargets {
            modelContext.delete(target)
        }
        for session in sessions {
            modelContext.delete(session)
        }

        activeSessionID = nil
        if preserveLogs {
            appendLog("Sesion anterior limpiada.")
        } else {
            logLines = ["[system] WebSiphon listo."]
        }
    }

    private func isHTMLResource(url: URL, mimeType: String?) -> Bool {
        let extensionValue = url.pathExtension.lowercased()
        if ["html", "htm", "php", "asp", "aspx", "jsp"].contains(extensionValue) {
            return true
        }
        if extensionValue.isEmpty {
            return mimeType?.lowercased().contains("html") ?? true
        }
        return mimeType?.lowercased().contains("html") ?? false
    }

    private func openOfflineRoot(for session: Item) {
        guard let rootLocalRelativePath = session.rootLocalRelativePath else { return }
        let baseFolderURL = URL(fileURLWithPath: session.destinationFolderPath, isDirectory: true)
        let localURL = baseFolderURL.appendingPathComponent(rootLocalRelativePath)
        NSWorkspace.shared.open(localURL)
    }

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Carpeta de descargas")
                .font(.headline)

            Text("Ruta actual")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(downloadBasePath)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Button("Elegir carpeta...") {
                    pickDownloadFolder()
                }

                Button("Default: Escritorio") {
                    setDesktopAsDefaultDestination()
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cerrar") {
                    isShowingSettings = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 560)
    }

    private func pickDownloadFolder() {
        let panel = NSOpenPanel()
        panel.title = "Selecciona carpeta de descargas"
        panel.message = "Elige la carpeta donde se guardaran los sitios espejados."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: downloadBasePath, isDirectory: true)

        guard panel.runModal() == .OK, let selected = panel.url else {
            return
        }

        downloadBasePath = selected.path
        if let bookmark = try? selected.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            downloadBaseBookmark = bookmark
        }
        appendLog("Nueva ruta de descarga: \(selected.path)")
    }

    private func requestFolderAuthorization(startingAt folderURL: URL) -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Permiso de carpeta requerido"
        panel.message = "Selecciona la carpeta donde WebSiphon puede guardar archivos."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = folderURL

        guard panel.runModal() == .OK, let selected = panel.url else {
            return false
        }

        downloadBasePath = selected.path
        if let bookmark = try? selected.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            downloadBaseBookmark = bookmark
        }
        appendLog("Acceso concedido para: \(selected.path)")
        return true
    }

    private func setDesktopAsDefaultDestination() {
        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)

        downloadBasePath = desktopURL.path

        if ensureWritableBaseFolder(desktopURL) {
            downloadBaseBookmark = Data()
            appendLog("Ruta de descarga restaurada a Escritorio.")
            return
        }

        appendLog("Escritorio requiere autorizacion de acceso.")
        if !requestFolderAuthorization(startingAt: desktopURL) {
            appendLog("No se concedio acceso al Escritorio.")
        }
    }

    private func ensureWritableBaseFolder(_ folderURL: URL) -> Bool {
        let needsScope = !downloadBaseBookmark.isEmpty
        let gainedScope = needsScope ? folderURL.startAccessingSecurityScopedResource() : false
        defer {
            if gainedScope {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let probeURL = folderURL.appendingPathComponent(".ws-permission-check-\(UUID().uuidString)", isDirectory: false)
            try Data("ok".utf8).write(to: probeURL, options: .atomic)
            try FileManager.default.removeItem(at: probeURL)
            return true
        } catch {
            return false
        }
    }

    private func resolvedBaseFolderURL() -> URL {
        if !downloadBaseBookmark.isEmpty {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: downloadBaseBookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale,
                   let refreshed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    downloadBaseBookmark = refreshed
                }
                return url
            }
        }
        return URL(fileURLWithPath: downloadBasePath, isDirectory: true)
    }

    private func saveFile(data: Data, relativePath: String, baseFolderURL: URL) throws {
        let fileURL = baseFolderURL.appendingPathComponent(relativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private var logArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(logLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: logLines.count) { _, count in
                guard count > 0 else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
    }

    private func appendLog(_ message: String) {
        logLines.append("[\(timeStamp())] \(message)")
    }

    private func timeStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "Completed", "Downloaded":
            return .green
        case "Running", "Downloading", "Analyzing":
            return .blue
        case "Stopping", "Stopped", "Cancelled":
            return .orange
        case "Failed":
            return .red
        default:
            return .secondary
        }
    }
}

private final class CrawlRunContext {
    let rootURL: URL
    let baseFolderURL: URL
    let siteFolderName: String
    let maxDepth: Int
    var knownURLs: Set<String> = []
    var visitedURLs: Set<String> = []
    var localPaths: [String: String] = [:]
    private var orderByURL: [String: Int] = [:]
    private var nextOrder: Int = 0

    init(rootURL: URL, baseFolderURL: URL, siteFolderName: String, maxDepth: Int) {
        self.rootURL = rootURL
        self.baseFolderURL = baseFolderURL
        self.siteFolderName = siteFolderName
        self.maxDepth = maxDepth
    }

    func nextDiscoveryOrderIfNeeded(for url: String) -> Int {
        if let existing = orderByURL[url] {
            return existing
        }
        let value = nextOrder
        orderByURL[url] = value
        nextOrder += 1
        return value
    }
}

private struct URLRowView: View {
    let target: DownloadTarget

    var body: some View {
        HStack(spacing: 12) {
            Text(target.state)
                .font(.caption.weight(.semibold))
                .foregroundStyle(stateColor)
                .frame(width: 100, alignment: .leading)

            Text("\(target.depth)")
                .font(.caption.monospacedDigit())
                .frame(width: 50, alignment: .leading)

            Text(target.kind)
                .font(.caption)
                .frame(width: 70, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.url)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    if let localRelativePath = target.localRelativePath {
                        Text(localRelativePath)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let errorMessage = target.errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(byteCountString)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)

            Text(httpCodeString)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private var byteCountString: String {
        guard target.byteCount > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: target.byteCount)
    }

    private var httpCodeString: String {
        guard let httpStatusCode = target.httpStatusCode else { return "—" }
        return String(httpStatusCode)
    }

    private var stateColor: Color {
        switch target.state {
        case "Downloaded":
            return .green
        case "Downloading", "Analyzing":
            return .blue
        case "Failed":
            return .red
        case "Stopped":
            return .orange
        default:
            return .secondary
        }
    }
}

#Preview {
    ContentView().modelContainer(for: [Item.self, DownloadTarget.self], inMemory: true)
}
