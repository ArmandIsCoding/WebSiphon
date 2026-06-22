//
//  ContentView.swift
//  WebSiphon
//
//  Created by Armando Meabe on 22/06/2026.
//

import SwiftUI
import SwiftData
import AppKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DownloadTarget.createdAt) private var downloadTargets: [DownloadTarget]

    @State private var targetURL = ""
    @State private var logLines: [String] = ["[system] WebSiphon listo."]
    @State private var runningTasks: [String: Task<Void, Never>] = [:]
    @State private var runtimeStatusByURL: [String: String] = [:]
    @State private var isShowingSettings = false

    @AppStorage("downloadBasePath") private var downloadBasePath = defaultDesktopPath
    @AppStorage("downloadBaseBookmark") private var downloadBaseBookmark = Data()

    private static var defaultDesktopPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .path
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        TextField("https://example.com", text: $targetURL)
                            .textFieldStyle(.roundedBorder)

                        Button("Siphon", action: startSiphon)
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }

                    Text("Sitios en cola: \(downloadTargets.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    List(downloadTargets) { target in
                        HStack {
                            Text(target.url)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(status(for: target))
                                .foregroundStyle(.secondary)

                            Button {
                                startDownload(for: target)
                            } label: {
                                Image(systemName: "play.fill")
                            }
                            .buttonStyle(.borderless)
                            .help("Iniciar descarga")
                            .disabled(isRunning(target))

                            Button {
                                stopDownload(for: target)
                            } label: {
                                Image(systemName: "stop.fill")
                            }
                            .buttonStyle(.borderless)
                            .help("Detener descarga")
                            .disabled(!isRunning(target))

                            Button {
                                removeTarget(target)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Eliminar sitio de la cola")
                        }
                    }
                }
                .padding()
                .frame(maxHeight: .infinity)

                Divider()

                logArea
                    .frame(maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Procesar todos") {
                    processAllDownloads()
                }
                .disabled(downloadTargets.isEmpty)

                Button("Clear", role: .destructive) {
                    cancelAllDownloads()
                    for target in downloadTargets {
                        modelContext.delete(target)
                    }
                    logLines.removeAll()
                    appendLog("Cola y log limpiados.")
                }

                Spacer()

                Button("Settings") {
                    isShowingSettings = true
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .sheet(isPresented: $isShowingSettings) {
            settingsView
        }
        .frame(minWidth: 900, minHeight: 540)
    }

    private func startSiphon() {
        let normalizedURL = targetURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedURL.isEmpty else {
            appendLog("Entrada vacia: ingresa una URL valida.")
            return
        }

        guard let candidate = URL(string: normalizedURL),
              let scheme = candidate.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              candidate.host != nil else {
            appendLog("URL invalida: \(normalizedURL)")
            return
        }

        if downloadTargets.contains(where: { $0.url == normalizedURL }) {
            appendLog("Ya estaba en cola: \(normalizedURL)")
            targetURL = ""
            return
        }

        modelContext.insert(DownloadTarget(url: normalizedURL))
        runtimeStatusByURL[normalizedURL] = "Queued"
        appendLog("Agregado a cola: \(normalizedURL)")
        targetURL = ""
    }

    private func startDownload(for target: DownloadTarget) {
        guard !isRunning(target) else { return }
        guard let url = URL(string: target.url) else {
            runtimeStatusByURL[target.url] = "Error"
            appendLog("No se pudo iniciar (URL invalida): \(target.url)")
            return
        }

        var baseFolderURL = resolvedBaseFolderURL()
        if !ensureWritableBaseFolder(baseFolderURL) {
            appendLog("Sin permiso de escritura en: \(baseFolderURL.path)")
            guard requestFolderAuthorization(startingAt: baseFolderURL) else {
                runtimeStatusByURL[target.url] = "Error"
                appendLog("Descarga cancelada: no se concedio acceso a carpeta de destino.")
                return
            }
            baseFolderURL = resolvedBaseFolderURL()
            guard ensureWritableBaseFolder(baseFolderURL) else {
                runtimeStatusByURL[target.url] = "Error"
                appendLog("La carpeta seleccionada sigue sin permisos de escritura.")
                return
            }
        }

        runtimeStatusByURL[target.url] = "Downloading"
        appendLog("Iniciando descarga: \(target.url)")

        let task = Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try Task.checkCancellation()

                let gainedScope = baseFolderURL.startAccessingSecurityScopedResource()
                defer {
                    if gainedScope {
                        baseFolderURL.stopAccessingSecurityScopedResource()
                    }
                }

                let savedFileURL = try saveHTML(data: data, siteURL: url, baseFolderURL: baseFolderURL)

                await MainActor.run {
                    runtimeStatusByURL[target.url] = "Complete"
                    runningTasks[target.url] = nil
                    appendLog("Descarga completa: \(target.url) -> \(savedFileURL.path)")
                }
            } catch is CancellationError {
                await MainActor.run {
                    runtimeStatusByURL[target.url] = "Stopped"
                    runningTasks[target.url] = nil
                    appendLog("Descarga detenida: \(target.url)")
                }
            } catch {
                await MainActor.run {
                    runtimeStatusByURL[target.url] = "Error"
                    runningTasks[target.url] = nil
                    appendLog("Error descargando \(target.url): \(error.localizedDescription)")
                }
            }
        }

        runningTasks[target.url] = task
    }

    private func stopDownload(for target: DownloadTarget) {
        runningTasks[target.url]?.cancel()
    }

    private func removeTarget(_ target: DownloadTarget) {
        stopDownload(for: target)
        runningTasks[target.url] = nil
        runtimeStatusByURL[target.url] = nil
        modelContext.delete(target)
        appendLog("Sitio eliminado de la cola: \(target.url)")
    }

    private func processAllDownloads() {
        guard !downloadTargets.isEmpty else {
            appendLog("No hay sitios en cola para procesar.")
            return
        }

        appendLog("Procesando todos los sitios en cola (\(downloadTargets.count)).")
        for target in downloadTargets where !isRunning(target) {
            startDownload(for: target)
        }
    }

    private func cancelAllDownloads() {
        for task in runningTasks.values {
            task.cancel()
        }
        runningTasks.removeAll()
        runtimeStatusByURL.removeAll()
    }

    private func isRunning(_ target: DownloadTarget) -> Bool {
        runningTasks[target.url] != nil
    }

    private func status(for target: DownloadTarget) -> String {
        runtimeStatusByURL[target.url] ?? "Queued"
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
        panel.message = "Elige la carpeta donde se guardaran los sitios."
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
            // If Desktop is writable directly (e.g. non-sandbox preview), no bookmark is required.
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

    private func saveHTML(data: Data, siteURL: URL, baseFolderURL: URL) throws -> URL {
        let folderName = siteFolderName(for: siteURL)
        let siteFolderURL = baseFolderURL.appendingPathComponent(folderName, isDirectory: true)

        try FileManager.default.createDirectory(at: siteFolderURL, withIntermediateDirectories: true)

        let htmlFileURL = siteFolderURL.appendingPathComponent("index.html", isDirectory: false)
        try data.write(to: htmlFileURL, options: .atomic)
        return htmlFileURL
    }

    private func siteFolderName(for url: URL) -> String {
        let host = (url.host ?? "site").lowercased()
        let hostWithoutWWW = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let firstComponent = hostWithoutWWW.split(separator: ".").first.map(String.init) ?? hostWithoutWWW
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = firstComponent.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }.joined()
        return sanitized.isEmpty ? "site" : sanitized
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
}

#Preview {
    ContentView()
        .modelContainer(for: [DownloadTarget.self], inMemory: true)
}
