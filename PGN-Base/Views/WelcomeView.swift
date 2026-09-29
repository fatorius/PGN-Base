import AppKit
import SwiftUI

/// The identifier of the welcome window scene.
let welcomeWindowID = "welcome"

/// The launch window: open a PGN file, or pick up a recently opened one.
struct WelcomeView: View {
    @Environment(\.openDocument) private var openDocument
    @State private var recentFiles: [RecentGameFile] = []
    @State private var selection: RecentGameFile.ID?
    @State private var openErrorMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            appPanel
                .frame(width: 300)
            Divider()
            recentFilesPanel
                .frame(width: 380)
        }
        .frame(height: 420)
        .task {
            await loadRecentFiles()
        }
        .alert(
            "Couldn't Open File",
            isPresented: Binding(get: { openErrorMessage != nil }, set: { if !$0 { openErrorMessage = nil } }),
            presenting: openErrorMessage
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    private var appPanel: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)
            Text("PGN Annotator")
                .font(.largeTitle.bold())
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("Version \(version)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                // Shows the standard open panel; the document group opens whatever is chosen.
                NSDocumentController.shared.openDocument(nil)
            } label: {
                Label("Open PGN File…", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    @ViewBuilder
    private var recentFilesPanel: some View {
        if recentFiles.isEmpty {
            ContentUnavailableView(
                "No Recent Games",
                systemImage: "clock",
                description: Text("PGN files you open will appear here.")
            )
        } else {
            VStack(spacing: 0) {
                List(recentFiles, selection: $selection) { file in
                    RecentGameFileRow(file: file)
                }
                .contextMenu(forSelectionType: RecentGameFile.ID.self) { urls in
                    Button("Open") { urls.forEach(open) }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(Array(urls))
                    }
                } primaryAction: { urls in
                    urls.forEach(open)
                }

                Divider()
                HStack {
                    Spacer()
                    Button("Clear History") {
                        NSDocumentController.shared.clearRecentDocuments(nil)
                        recentFiles = []
                    }
                    .buttonStyle(.link)
                }
                .padding(8)
            }
        }
    }

    private func open(_ url: URL) {
        Task {
            do {
                try await openDocument(at: url)
            } catch {
                openErrorMessage = error.localizedDescription
            }
        }
    }

    /// Lists the recent files right away, then fills in each game summary as it's read.
    private func loadRecentFiles() async {
        let urls = NSDocumentController.shared.recentDocumentURLs
        recentFiles = urls.map { RecentGameFile(url: $0) }
        for url in urls {
            let summary = await RecentGameFile.loadSummary(of: url)
            if let index = recentFiles.firstIndex(where: { $0.url == url }) {
                recentFiles[index].summary = summary
            }
        }
    }
}

/// A recently opened PGN file, with a short description of its first game.
struct RecentGameFile: Identifiable, Hashable {
    let url: URL
    var summary: String?

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }

    /// Describes the first game using only the start of the file, so large databases stay fast.
    @concurrent
    nonisolated static func loadSummary(of url: URL) async -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 32_768) else { return nil }
        guard let game = PGNParser.parseGames(from: String(decoding: data, as: UTF8.self)).first else { return nil }
        return [game.title, game.tag("Event"), game.date].compactMap(\.self).joined(separator: " · ")
    }
}

private struct RecentGameFileRow: View {
    let file: RecentGameFile

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkerboard.rectangle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(file.summary ?? " ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .help(file.url.path(percentEncoded: false))
    }
}

#Preview {
    WelcomeView()
}
